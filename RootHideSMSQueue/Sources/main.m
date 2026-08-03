#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <sqlite3.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

static NSString *const kBundleIdentifier = @"com.nextsolution.dailyledger";
static NSString *const kDarwinChangeNotification = @"com.nextsolution.dailyledger.external-change";
static NSString *const kDaemonVersion = @"2.0.0";

static NSMutableDictionary *gState;

typedef NS_ENUM(NSInteger, ImportResult) {
    ImportResultFailed = 0,
    ImportResultImported = 1,
    ImportResultDuplicate = 2,
    ImportResultWaitingForMapping = 3
};

static NSString *ExistingPath(NSArray<NSString *> *paths) {
    NSFileManager *manager = NSFileManager.defaultManager;
    for (NSString *path in paths) {
        if ([manager fileExistsAtPath:path]) return path;
    }
    return paths.firstObject;
}

static NSString *StateDirectory(void) {
    return ExistingPath(@[
        @"/rootfs/var/mobile/Library/NextLedgerSMSImport",
        @"/var/mobile/Library/NextLedgerSMSImport"
    ]);
}

static NSString *StatePath(void) {
    return [StateDirectory() stringByAppendingPathComponent:@"state.plist"];
}

static NSString *PendingDirectory(void) {
    return [StateDirectory() stringByAppendingPathComponent:@"pending"];
}

static NSString *ProcessedDirectory(void) {
    return [StateDirectory() stringByAppendingPathComponent:@"processed"];
}

static void EnsureDirectory(NSString *path) {
    [NSFileManager.defaultManager createDirectoryAtPath:path
                            withIntermediateDirectories:YES
                                             attributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}
                                                  error:nil];
}

static NSString *ISODate(NSDate *date) {
    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    return [formatter stringFromDate:date ?: NSDate.date];
}

static NSDate *DatabaseDate(sqlite3_int64 rawValue) {
    double value = (double)rawValue;
    if (value > 1000000000000000.0) value /= 1000000000.0;
    else if (value > 1000000000000.0) value /= 1000000.0;
    return [NSDate dateWithTimeIntervalSinceReferenceDate:value];
}

static NSString *Capture(NSString *pattern, NSString *text, NSUInteger group) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                            options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                                                                              error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match || group >= match.numberOfRanges || [match rangeAtIndex:group].location == NSNotFound) return nil;
    return [text substringWithRange:[match rangeAtIndex:group]];
}

static NSString *CleanWhitespace(NSString *value) {
    if (value.length == 0) return @"";
    NSArray<NSString *> *parts = [value componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    for (NSString *part in parts) if (part.length > 0) [clean addObject:part];
    return [clean componentsJoinedByString:@" "];
}

static NSUUID *DeterministicUUID(NSString *source) {
    NSData *data = [source dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    uuid_t bytes;
    memcpy(bytes, digest, 16);
    bytes[6] = (bytes[6] & 0x0F) | 0x50;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    return [[NSUUID alloc] initWithUUIDBytes:bytes];
}

static void SaveState(void) {
    EnsureDirectory(StateDirectory());
    [gState writeToFile:StatePath() atomically:YES];
}

static void LoadState(void) {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:StatePath()];
    gState = saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    if (![gState[@"logs"] isKindOfClass:NSArray.class]) gState[@"logs"] = [NSMutableArray array];
    if (!gState[@"totalImported"]) gState[@"totalImported"] = @0;
    if (!gState[@"totalDuplicates"]) gState[@"totalDuplicates"] = @0;
    if (!gState[@"totalParseFailures"]) gState[@"totalParseFailures"] = @0;
}

static void AddLog(NSString *level, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
static void AddLog(NSString *level, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSMutableArray *logs = [gState[@"logs"] mutableCopy] ?: [NSMutableArray array];
    [logs addObject:@{
        @"id": NSUUID.UUID.UUIDString,
        @"date": ISODate(NSDate.date),
        @"level": level ?: @"info",
        @"message": message ?: @""
    }];
    while (logs.count > 100) [logs removeObjectAtIndex:0];
    gState[@"logs"] = logs;
    NSLog(@"[NextLedgerSMS] %@: %@", level.uppercaseString, message);
    SaveState();
}

static NSString *ApplicationContainer(void) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSArray<NSString *> *bases = @[
        @"/rootfs/var/mobile/Containers/Data/Application",
        @"/var/mobile/Containers/Data/Application"
    ];
    for (NSString *base in bases) {
        NSArray *children = [manager contentsOfDirectoryAtPath:base error:nil];
        for (NSString *child in children) {
            NSString *container = [base stringByAppendingPathComponent:child];
            NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:
                [container stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
            if ([metadata[@"MCMMetadataIdentifier"] isEqualToString:kBundleIdentifier]) return container;
        }
    }
    return nil;
}

static NSString *AppSupportDirectory(void) {
    NSString *container = ApplicationContainer();
    if (!container) return nil;
    return [container stringByAppendingPathComponent:@"Library/Application Support/DailyLedger"];
}

static NSString *LedgerPath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"ledger.json"] : nil;
}

static NSString *ConfigurationPath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"sms-import-config.json"] : nil;
}

static NSString *ConsolePath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"sms-import-console.json"] : nil;
}

static NSDictionary *ReadJSON(NSString *path) {
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    if (!data) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static BOOL WriteJSON(id object, NSString *path) {
    if (!path || ![NSJSONSerialization isValidJSONObject:object]) return NO;
    EnsureDirectory(path.stringByDeletingLastPathComponent);
    NSData *data = [NSJSONSerialization dataWithJSONObject:object
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    if (!data) return NO;
    BOOL written = [data writeToFile:path options:NSDataWritingAtomic error:nil];
    if (written) {
        [NSFileManager.defaultManager setAttributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}
                                       ofItemAtPath:path
                                              error:nil];
    }
    return written;
}

static NSDictionary *LoadConfiguration(void) {
    NSDictionary *config = ReadJSON(ConfigurationPath());
    return config ?: @{
        @"enabled": @YES,
        @"cardAccountIDs": @{},
        @"scanRequestID": @0
    };
}

static NSInteger PendingCount(void) {
    EnsureDirectory(PendingDirectory());
    return [NSFileManager.defaultManager contentsOfDirectoryAtPath:PendingDirectory() error:nil].count;
}

static void WriteConsole(NSString *lastResult) {
    NSString *path = ConsolePath();
    if (!path) return;
    gState[@"lastHeartbeat"] = ISODate(NSDate.date);
    if (lastResult.length > 0) gState[@"lastResult"] = lastResult;
    NSDictionary *console = @{
        @"daemonRunning": @YES,
        @"lastHeartbeat": gState[@"lastHeartbeat"] ?: ISODate(NSDate.date),
        @"lastScanDate": gState[@"lastScanDate"] ?: [NSNull null],
        @"lastImportDate": gState[@"lastImportDate"] ?: [NSNull null],
        @"lastResult": gState[@"lastResult"] ?: @"Daemon started.",
        @"totalImported": gState[@"totalImported"] ?: @0,
        @"totalDuplicates": gState[@"totalDuplicates"] ?: @0,
        @"totalParseFailures": gState[@"totalParseFailures"] ?: @0,
        @"pendingCount": @(PendingCount()),
        @"logs": gState[@"logs"] ?: @[]
    };
    NSMutableDictionary *clean = [console mutableCopy];
    if (clean[@"lastScanDate"] == NSNull.null) [clean removeObjectForKey:@"lastScanDate"];
    if (clean[@"lastImportDate"] == NSNull.null) [clean removeObjectForKey:@"lastImportDate"];
    WriteJSON(clean, path);
    SaveState();
}

static NSDate *TransactionDate(NSString *text, NSDate *fallback) {
    NSArray<NSDictionary *> *patterns = @[
        @{@"pattern": @"\\b(\\d{1,2}/\\d{1,2}/\\d{4})\\s+(\\d{1,2}:\\d{2})\\b", @"format": @"dd/MM/yyyy HH:mm"},
        @{@"pattern": @"\\b(\\d{1,2}/\\d{1,2}/\\d{2})\\s+(\\d{1,2}:\\d{2})\\b", @"format": @"dd/MM/yy HH:mm"},
        @{@"pattern": @"\\b(\\d{1,2}-[A-Za-z]{3}-\\d{4})\\s+(\\d{1,2}:\\d{2})\\b", @"format": @"dd-MMM-yyyy HH:mm"},
        @{@"pattern": @"\\b(\\d{1,2}-[A-Za-z]{3}-\\d{2})\\s+(\\d{1,2}:\\d{2})\\b", @"format": @"dd-MMM-yy HH:mm"}
    ];
    for (NSDictionary *item in patterns) {
        NSString *datePart = Capture(item[@"pattern"], text, 1);
        NSString *timePart = Capture(item[@"pattern"], text, 2);
        if (!datePart || !timePart) continue;
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = NSTimeZone.localTimeZone;
        formatter.dateFormat = item[@"format"];
        NSDate *date = [formatter dateFromString:[NSString stringWithFormat:@"%@ %@", datePart, timePart]];
        if (date) return date;
    }
    return fallback ?: NSDate.date;
}

static NSDictionary *ParseTransaction(NSString *text, NSDate *fallbackDate) {
    NSString *clean = CleanWhitespace(text);
    NSString *lower = clean.lowercaseString;
    NSString *kind = nil;
    if ([lower containsString:@"cashback"] && [lower containsString:@"credited"]) kind = @"cashback";
    else if ([lower containsString:@"withdrawal using"]) kind = @"withdrawal";
    else if ([lower containsString:@"bill payment"] && [lower containsString:@"from card"]) kind = @"billPayment";
    else if ([lower containsString:@"used for"] || [lower containsString:@"purchase"] || [lower containsString:@"debited"]) kind = @"expense";
    else if ([lower containsString:@"credited to"] || [lower containsString:@"received"]) kind = @"income";
    if (!kind) return nil;

    NSString *currency = Capture(@"\\b(QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b", clean, 1);
    NSString *amountText = Capture(@"\\b(QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b", clean, 2);
    if (!currency || !amountText) return nil;
    if ([currency.uppercaseString isEqualToString:@"QR"]) currency = @"QAR";
    amountText = [amountText stringByReplacingOccurrencesOfString:@"," withString:@""];
    NSDecimalNumber *amount = [NSDecimalNumber decimalNumberWithString:amountText locale:@{NSLocaleDecimalSeparator: @"."}];
    if ([amount isEqualToNumber:NSDecimalNumber.notANumber] || amount.doubleValue <= 0) return nil;

    NSString *ending = Capture(@"\\*\\*(\\d{4})", clean, 1);
    if (!ending) return nil;

    NSString *vendor = nil;
    if ([kind isEqualToString:@"expense"]) {
        vendor = Capture(@"\\bused for\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,.]*\\s+at\\s+(.+?)(?=\\s+at\\s+\\d{1,2}/\\d{1,2}/\\d{2,4}|\\s+on\\s+\\d{1,2}/|\\s+available\\s+limit|$)", clean, 1);
    } else if ([kind isEqualToString:@"withdrawal"]) {
        vendor = Capture(@"\\bat\\s+(.+?)(?=\\s+your available|\\s+available balance|$)", clean, 1);
    } else if ([kind isEqualToString:@"billPayment"]) {
        vendor = Capture(@"\\bto\\s+(.+?)(?=\\s+on\\s+\\d{1,2}/|\\s+was successful|$)", clean, 1);
    } else if ([kind isEqualToString:@"cashback"]) {
        vendor = @"Credit Card Cashback";
    } else {
        vendor = Capture(@"\\bfrom\\s+(.+?)(?=\\s+on\\s+\\d|\\s+at\\s+\\d|$)", clean, 1) ?: @"Bank Credit";
    }
    vendor = CleanWhitespace(vendor ?: @"Unknown");

    return @{
        @"kind": kind,
        @"currency": currency.uppercaseString,
        @"amount": amount,
        @"cardEnding": ending,
        @"vendor": vendor,
        @"date": ISODate(TransactionDate(clean, fallbackDate)),
        @"details": clean
    };
}

static NSString *SMSDatabasePath(void) {
    return ExistingPath(@[
        @"/rootfs/var/mobile/Library/SMS/sms.db",
        @"/var/mobile/Library/SMS/sms.db"
    ]);
}

static NSString *TextFromAttributedBody(const void *bytes, int length) {
    if (!bytes || length <= 0) return nil;
    const unsigned char *raw = bytes;
    NSMutableArray<NSString *> *runs = [NSMutableArray array];
    int start = -1;
    for (int index = 0; index <= length; index++) {
        BOOL printable = index < length && raw[index] >= 32 && raw[index] <= 126;
        if (printable && start < 0) start = index;
        if (!printable && start >= 0) {
            int runLength = index - start;
            if (runLength >= 4) {
                NSString *run = [[NSString alloc] initWithBytes:raw + start length:(NSUInteger)runLength encoding:NSUTF8StringEncoding];
                if (run.length > 0) [runs addObject:run];
            }
            start = -1;
        }
    }
    return runs.count ? [runs componentsJoinedByString:@"\n"] : nil;
}

static NSString *MessageText(sqlite3_stmt *statement) {
    const unsigned char *textBytes = sqlite3_column_text(statement, 2);
    if (textBytes) {
        NSString *text = [NSString stringWithUTF8String:(const char *)textBytes];
        if (text.length > 0) return text;
    }
    const void *bytes = sqlite3_column_blob(statement, 3);
    int length = sqlite3_column_bytes(statement, 3);
    if (bytes && length > 0) {
        NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)length];
        @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            id decoded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
#pragma clang diagnostic pop
            if ([decoded isKindOfClass:NSAttributedString.class]) return [decoded string];
            if ([decoded isKindOfClass:NSString.class]) return decoded;
        } @catch (__unused NSException *exception) {}
    }
    return TextFromAttributedBody(bytes, length);
}

static sqlite3_int64 MaximumRowID(sqlite3 *database) {
    sqlite3_stmt *statement = NULL;
    sqlite3_int64 value = 0;
    if (sqlite3_prepare_v2(database, "SELECT COALESCE(MAX(ROWID), 0) FROM message", -1, &statement, NULL) == SQLITE_OK && sqlite3_step(statement) == SQLITE_ROW) {
        value = sqlite3_column_int64(statement, 0);
    }
    sqlite3_finalize(statement);
    return value;
}

static int LockFile(NSString *path) {
    EnsureDirectory(path.stringByDeletingLastPathComponent);
    int descriptor = open(path.fileSystemRepresentation, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR);
    if (descriptor < 0) return -1;
    struct flock lock = {.l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0};
    if (fcntl(descriptor, F_SETLKW, &lock) != 0) {
        close(descriptor);
        return -1;
    }
    return descriptor;
}

static void UnlockFile(int descriptor) {
    if (descriptor < 0) return;
    struct flock lock = {.l_type = F_UNLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0};
    fcntl(descriptor, F_SETLK, &lock);
    close(descriptor);
}

static NSString *AccountIDByName(NSArray *accounts, NSArray<NSString *> *words) {
    for (NSDictionary *account in accounts) {
        if ([account[@"isArchived"] boolValue]) continue;
        NSString *name = [account[@"name"] lowercaseString] ?: @"";
        for (NSString *word in words) {
            if ([name containsString:word.lowercaseString]) return account[@"id"];
        }
    }
    return nil;
}

static BOOL AccountExists(NSArray *accounts, NSString *identifier) {
    if (identifier.length == 0) return NO;
    for (NSDictionary *account in accounts) if ([account[@"id"] isEqualToString:identifier]) return YES;
    return NO;
}

static NSString *CardAccountID(NSDictionary *config, NSDictionary *ledger, NSString *ending) {
    NSArray *accounts = ledger[@"accounts"] ?: @[];
    NSString *configured = [config[@"cardAccountIDs"] isKindOfClass:NSDictionary.class] ? config[@"cardAccountIDs"][ending] : nil;
    if (AccountExists(accounts, configured)) return configured;
    if ([ending isEqualToString:@"6760"]) return AccountIDByName(accounts, @[@"6760", @"credit card", @"credit"]);
    if ([ending isEqualToString:@"0023"]) return AccountIDByName(accounts, @[@"0023", @"debit card", @"debit"]);
    return AccountIDByName(accounts, @[ending]);
}

static NSString *DestinationAccountID(NSDictionary *config, NSDictionary *ledger, NSString *kind) {
    NSArray *accounts = ledger[@"accounts"] ?: @[];
    NSString *configured = [kind isEqualToString:@"withdrawal"] ? config[@"cashAccountID"] : config[@"loanPaymentAccountID"];
    if (AccountExists(accounts, configured)) return configured;
    if ([kind isEqualToString:@"withdrawal"]) return AccountIDByName(accounts, @[@"cash"]);
    return AccountIDByName(accounts, @[@"loan payment", @"loan"]);
}

static NSString *CategoryForVendor(NSDictionary *ledger, NSString *vendor) {
    NSArray *rules = [ledger[@"settings"][@"vendorRules"] isKindOfClass:NSArray.class] ? ledger[@"settings"][@"vendorRules"] : @[];
    for (NSDictionary *rule in rules) {
        NSString *keyword = rule[@"keyword"];
        NSString *category = rule[@"category"];
        if (keyword.length && category.length && [vendor rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) return category;
    }
    NSString *lower = vendor.lowercaseString;
    if ([lower containsString:@"restaurant"] || [lower containsString:@"cafe"] || [lower containsString:@"coffee"]) return @"Restaurants & Cafes";
    if ([lower containsString:@"grocery"] || [lower containsString:@"market"]) return @"Grocery";
    if ([lower containsString:@"woqod"] || [lower containsString:@"fuel"]) return @"Fuel";
    return @"Other";
}

static NSString *QueueEvent(NSDictionary *parsed, NSString *sourceKey, NSString *sender) {
    EnsureDirectory(PendingDirectory());
    NSString *identifier = DeterministicUUID(sourceKey).UUIDString;
    NSString *path = [PendingDirectory() stringByAppendingPathComponent:[identifier stringByAppendingString:@".json"]];
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) return path;
    NSMutableDictionary *event = [parsed mutableCopy];
    event[@"id"] = identifier;
    event[@"sourceKey"] = sourceKey;
    event[@"sender"] = sender ?: @"";
    event[@"queuedAt"] = ISODate(NSDate.date);
    if (!WriteJSON(event, path)) return nil;
    AddLog(@"info", @"Queued %@ QAR %@ for card **%@.", parsed[@"kind"], parsed[@"amount"], parsed[@"cardEnding"]);
    return path;
}

static ImportResult ImportEvent(NSString *eventPath, NSDictionary *config) {
    NSMutableDictionary *event = [ReadJSON(eventPath) mutableCopy];
    NSString *ledgerPath = LedgerPath();
    if (!event || !ledgerPath || ![NSFileManager.defaultManager fileExistsAtPath:ledgerPath]) return ImportResultFailed;

    int descriptor = LockFile([ledgerPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"ledger.lock"]);
    if (descriptor < 0) return ImportResultFailed;
    ImportResult result = ImportResultFailed;
    @try {
        NSMutableDictionary *ledger = [ReadJSON(ledgerPath) mutableCopy];
        if (!ledger) @throw [NSException exceptionWithName:@"LedgerMissing" reason:nil userInfo:nil];
        NSMutableArray *transactions = [ledger[@"transactions"] mutableCopy] ?: [NSMutableArray array];
        NSString *identifier = event[@"id"];
        for (NSDictionary *transaction in transactions) {
            if ([transaction[@"id"] isEqualToString:identifier]) {
                result = ImportResultDuplicate;
                @throw [NSException exceptionWithName:@"Duplicate" reason:nil userInfo:nil];
            }
        }

        NSString *kind = event[@"kind"];
        NSString *sourceAccount = CardAccountID(config, ledger, event[@"cardEnding"]);
        if (!sourceAccount) {
            AddLog(@"warning", @"Waiting for account mapping for card **%@.", event[@"cardEnding"]);
            result = ImportResultWaitingForMapping;
            @throw [NSException exceptionWithName:@"Mapping" reason:nil userInfo:nil];
        }

        NSMutableDictionary *transaction = [@{
            @"id": identifier,
            @"amount": event[@"amount"],
            @"date": event[@"date"],
            @"vendor": event[@"vendor"] ?: @"Bank Transaction",
            @"details": event[@"details"] ?: @"Imported bank SMS",
            @"accountID": sourceAccount,
            @"createdAt": ISODate(NSDate.date)
        } mutableCopy];

        if ([kind isEqualToString:@"withdrawal"] || [kind isEqualToString:@"billPayment"]) {
            NSString *destination = DestinationAccountID(config, ledger, kind);
            if (!destination) {
                AddLog(@"warning", @"Waiting for %@ destination account mapping.", [kind isEqualToString:@"withdrawal"] ? @"Cash" : @"Loan Payment");
                result = ImportResultWaitingForMapping;
                @throw [NSException exceptionWithName:@"Mapping" reason:nil userInfo:nil];
            }
            transaction[@"type"] = @"transfer";
            transaction[@"category"] = @"Transfer";
            transaction[@"destinationAccountID"] = destination;
            transaction[@"destinationAmount"] = event[@"amount"];
        } else if ([kind isEqualToString:@"cashback"]) {
            transaction[@"type"] = @"income";
            transaction[@"category"] = @"Refund";
        } else if ([kind isEqualToString:@"income"]) {
            transaction[@"type"] = @"income";
            transaction[@"category"] = @"Other";
        } else {
            transaction[@"type"] = @"expense";
            transaction[@"category"] = CategoryForVendor(ledger, event[@"vendor"] ?: @"");
        }

        [transactions addObject:transaction];
        ledger[@"transactions"] = transactions;
        if (!WriteJSON(ledger, ledgerPath)) @throw [NSException exceptionWithName:@"WriteFailed" reason:nil userInfo:nil];
        result = ImportResultImported;
    } @catch (NSException *exception) {
        if (![exception.name isEqualToString:@"Duplicate"] && ![exception.name isEqualToString:@"Mapping"]) {
            AddLog(@"error", @"Ledger import failed: %@.", exception.name);
            result = ImportResultFailed;
        }
    } @finally {
        UnlockFile(descriptor);
    }
    return result;
}

static void FinishEvent(NSString *path) {
    EnsureDirectory(ProcessedDirectory());
    NSString *destination = [ProcessedDirectory() stringByAppendingPathComponent:path.lastPathComponent];
    [NSFileManager.defaultManager removeItemAtPath:destination error:nil];
    [NSFileManager.defaultManager moveItemAtPath:path toPath:destination error:nil];
    NSArray *processed = [NSFileManager.defaultManager contentsOfDirectoryAtPath:ProcessedDirectory() error:nil];
    if (processed.count > 100) {
        NSArray *sorted = [processed sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        for (NSUInteger index = 0; index < sorted.count - 100; index++) {
            [NSFileManager.defaultManager removeItemAtPath:[ProcessedDirectory() stringByAppendingPathComponent:sorted[index]] error:nil];
        }
    }
}

static void RetryPending(NSDictionary *config) {
    NSArray *files = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:PendingDirectory() error:nil]
        sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *file in files) {
        if (![file.pathExtension.lowercaseString isEqualToString:@"json"]) continue;
        NSString *path = [PendingDirectory() stringByAppendingPathComponent:file];
        ImportResult result = ImportEvent(path, config);
        if (result == ImportResultImported) {
            gState[@"totalImported"] = @([gState[@"totalImported"] integerValue] + 1);
            gState[@"lastImportDate"] = ISODate(NSDate.date);
            NSDictionary *event = ReadJSON(path);
            AddLog(@"success", @"Recorded %@ %@ %@ from card **%@.", event[@"kind"], event[@"currency"], event[@"amount"], event[@"cardEnding"]);
            FinishEvent(path);
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)kDarwinChangeNotification, NULL, NULL, true);
        } else if (result == ImportResultDuplicate) {
            gState[@"totalDuplicates"] = @([gState[@"totalDuplicates"] integerValue] + 1);
            AddLog(@"info", @"Skipped duplicate queue item %@.", file.stringByDeletingPathExtension);
            FinishEvent(path);
        } else if (result == ImportResultFailed) {
            break;
        }
    }
    SaveState();
}

static void ScanMessages(BOOL forceRecent) {
    NSDictionary *config = LoadConfiguration();
    if (config[@"enabled"] && ![config[@"enabled"] boolValue]) {
        WriteConsole(@"Automatic bank SMS import is disabled in Next Ledger settings.");
        return;
    }

    NSString *databasePath = SMSDatabasePath();
    if (![NSFileManager.defaultManager fileExistsAtPath:databasePath]) {
        AddLog(@"error", @"Messages database was not found at the expected iOS 16 path.");
        WriteConsole(@"Messages database not found.");
        return;
    }
    if (!LedgerPath()) {
        AddLog(@"warning", @"Next Ledger app container was not found. Open Next Ledger once.");
        WriteConsole(@"Open Next Ledger once so its app container can be located.");
        return;
    }

    RetryPending(config);

    sqlite3 *database = NULL;
    if (sqlite3_open_v2(databasePath.fileSystemRepresentation, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
        if (database) sqlite3_close(database);
        AddLog(@"error", @"Root daemon could not open sms.db read-only.");
        WriteConsole(@"Could not open Messages database.");
        return;
    }
    sqlite3_busy_timeout(database, 2500);
    sqlite3_int64 maximum = MaximumRowID(database);
    NSNumber *savedRow = gState[@"lastRowID"];
    NSInteger requestID = [config[@"scanRequestID"] integerValue];
    NSInteger savedRequest = [gState[@"lastScanRequestID"] integerValue];

    if (!savedRow) {
        gState[@"lastRowID"] = @(maximum);
        gState[@"lastScanRequestID"] = @(requestID);
        sqlite3_close(database);
        AddLog(@"info", @"Initialized at SMS row %lld. Existing history was not imported automatically.", maximum);
        WriteConsole(@"Daemon initialized. New matching bank SMS will import automatically.");
        return;
    }

    BOOL manualRecent = forceRecent || requestID != savedRequest;
    sqlite3_int64 startRow = manualRecent ? MAX((sqlite3_int64)0, maximum - 250) : savedRow.longLongValue;
    if (maximum <= startRow && !manualRecent) {
        sqlite3_close(database);
        WriteConsole(nil);
        return;
    }

    const char *query =
        "SELECT m.ROWID, COALESCE(m.guid, ''), m.text, m.attributedBody, m.date, COALESCE(h.id, '') "
        "FROM message m LEFT JOIN handle h ON m.handle_id = h.ROWID "
        "WHERE m.ROWID > ? AND m.ROWID <= ? AND m.is_from_me = 0 "
        "AND (m.text IS NOT NULL OR m.attributedBody IS NOT NULL) ORDER BY m.ROWID ASC";
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, query, -1, &statement, NULL) != SQLITE_OK) {
        sqlite3_close(database);
        AddLog(@"error", @"sms.db query preparation failed: %s", sqlite3_errmsg(database));
        WriteConsole(@"Messages database schema was not recognized.");
        return;
    }
    sqlite3_bind_int64(statement, 1, startRow);
    sqlite3_bind_int64(statement, 2, maximum);

    NSInteger inspected = 0;
    NSInteger matched = 0;
    NSInteger parseFailures = 0;
    while (sqlite3_step(statement) == SQLITE_ROW) {
        inspected += 1;
        sqlite3_int64 rowID = sqlite3_column_int64(statement, 0);
        NSString *text = MessageText(statement);
        if (text.length == 0) continue;
        NSDictionary *parsed = ParseTransaction(text, DatabaseDate(sqlite3_column_int64(statement, 4)));
        if (!parsed) {
            NSString *lower = text.lowercaseString;
            if ([lower containsString:@"**6760"] || [lower containsString:@"**0023"] || [lower containsString:@"bill payment"] || [lower containsString:@"cashback"]) {
                parseFailures += 1;
                AddLog(@"warning", @"SMS row %lld looked like a bank message but could not be classified.", rowID);
            }
            continue;
        }
        matched += 1;
        const unsigned char *guidBytes = sqlite3_column_text(statement, 1);
        const unsigned char *senderBytes = sqlite3_column_text(statement, 5);
        NSString *guid = guidBytes ? [NSString stringWithUTF8String:(const char *)guidBytes] : @"";
        NSString *sender = senderBytes ? [NSString stringWithUTF8String:(const char *)senderBytes] : @"";
        NSString *source = guid.length ? guid : [NSString stringWithFormat:@"%lld|%@", rowID, text];
        QueueEvent(parsed, source, sender);
    }
    sqlite3_finalize(statement);
    sqlite3_close(database);

    gState[@"lastRowID"] = @(maximum);
    gState[@"lastScanRequestID"] = @(requestID);
    gState[@"lastScanDate"] = ISODate(NSDate.date);
    if (parseFailures > 0) gState[@"totalParseFailures"] = @([gState[@"totalParseFailures"] integerValue] + parseFailures);
    SaveState();
    RetryPending(config);

    NSString *result = [NSString stringWithFormat:@"Inspected %ld new/recent messages, classified %ld bank transaction%@, parse failures %ld.",
        (long)inspected, (long)matched, matched == 1 ? @"" : @"s", (long)parseFailures];
    AddLog(@"info", @"%@", result);
    WriteConsole(result);
}

static int RunSelfTest(void) {
    NSArray<NSDictionary *> *tests = @[
        @{
            @"name": @"card expense",
            @"sms": @"Your card ending with **6760 used for QAR 30.00 at NIKE, MALL OF QATAR, QA at 02/08/2026 13:15. Available Limit: QAR 219.59",
            @"kind": @"expense", @"ending": @"6760", @"amount": @"30"
        },
        @{
            @"name": @"cashback income",
            @"sms": @"Cashback amount of QAR 0.20 credited to your Credit Card **6760 on 02/08/2026 12:34. Available Limit is QAR 250.59",
            @"kind": @"cashback", @"ending": @"6760", @"amount": @"0.2"
        },
        @{
            @"name": @"cash withdrawal transfer",
            @"sms": @"Withdrawal using Debit Card **0023 for QAR 1500 on 25/07/2026 17:19 at DOHA BANK ATM. Your available balance is QAR 33.24",
            @"kind": @"withdrawal", @"ending": @"0023", @"amount": @"1500"
        },
        @{
            @"name": @"loan payment transfer",
            @"sms": @"Bill Payment of QAR 1279.31 from card **0023 to LOAN PAYMENT FOR XXXXXXXX on 25/07/2026 17:15 was successful.",
            @"kind": @"billPayment", @"ending": @"0023", @"amount": @"1279.31"
        }
    ];
    NSMutableArray *results = [NSMutableArray array];
    BOOL passed = YES;
    for (NSDictionary *test in tests) {
        NSDictionary *parsed = ParseTransaction(test[@"sms"], NSDate.date);
        NSDecimalNumber *expected = [NSDecimalNumber decimalNumberWithString:test[@"amount"]];
        BOOL ok = parsed && [parsed[@"kind"] isEqualToString:test[@"kind"]] &&
            [parsed[@"cardEnding"] isEqualToString:test[@"ending"]] &&
            [parsed[@"amount"] compare:expected] == NSOrderedSame;
        passed = passed && ok;
        [results addObject:@{
            @"name": test[@"name"],
            @"passed": @(ok),
            @"parsed": parsed ?: @{}
        }];
    }
    NSDictionary *output = @{@"passed": @(passed), @"version": kDaemonVersion, @"tests": results};
    NSData *json = [NSJSONSerialization dataWithJSONObject:output options:NSJSONWritingPrettyPrinted error:nil];
    fprintf(stdout, "%s\n", [[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] UTF8String]);
    return passed ? 0 : 1;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--self-test") == 0) return RunSelfTest();
        LoadState();
        AddLog(@"info", @"Next Ledger SMS daemon %@ started as uid %d.", kDaemonVersion, getuid());
        if (argc > 1 && strcmp(argv[1], "--scan-recent") == 0) {
            ScanMessages(YES);
            return 0;
        }
        while (true) {
            @autoreleasepool {
                ScanMessages(NO);
                WriteConsole(nil);
            }
            sleep(3);
        }
    }
    return 0;
}
