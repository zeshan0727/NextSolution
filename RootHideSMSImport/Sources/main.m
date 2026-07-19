#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <sqlite3.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

static NSString *const kBundleIdentifier = @"com.nextsolution.dailyledger";
static NSString *const kChangeNotification = @"com.nextsolution.dailyledger.external-change";
static NSString *const kDefaultMatchText = @"**6760";
static NSString *const kLegacyAccountID = @"00000000-0000-4000-8000-000000000001";

typedef NS_ENUM(NSInteger, AppendResult) {
    AppendResultFailed = 0,
    AppendResultImported = 1,
    AppendResultDuplicate = 2,
    AppendResultDisabled = 3
};

static NSString *MobilePath(NSString *relativePath) {
    NSString *rootHidePath = [@"/rootfs" stringByAppendingString:relativePath];
    NSString *rootHideParent = [rootHidePath stringByDeletingLastPathComponent];
    if ([[NSFileManager defaultManager] fileExistsAtPath:rootHideParent]) return rootHidePath;
    return relativePath;
}

static NSString *StateDirectory(void) {
    return MobilePath(@"/var/mobile/Library/DailyLedgerSMSImport");
}

static void Log(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void Log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[DailyLedgerSMS] %@", message);

    NSString *directory = StateDirectory();
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *path = [directory stringByAppendingPathComponent:@"sms-import.log"];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if ([attributes fileSize] > 262144) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:[NSDate date]], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [data writeToFile:path options:NSDataWritingAtomic error:nil];
    } else {
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    }
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
    NSArray<NSString *> *parts = [value componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    for (NSString *part in parts) if (part.length > 0) [clean addObject:part];
    return [clean componentsJoinedByString:@" "];
}

static NSDate *DatabaseDate(sqlite3_int64 rawValue) {
    double value = (double)rawValue;
    if (value > 1000000000000000.0) value /= 1000000000.0;
    else if (value > 1000000000000.0) value /= 1000000.0;
    return [NSDate dateWithTimeIntervalSinceReferenceDate:value];
}

static NSDate *TransactionDate(NSString *text, NSDate *fallback) {
    NSString *day = Capture(@"\\b(\\d{1,2}-[A-Za-z]{3}-\\d{2,4})\\b", text, 1);
    NSString *time = Capture(@"\\bat\\s+(\\d{1,2}:\\d{2})(?::\\d{2})?\\s+(?=\\d{1,2}-[A-Za-z]{3}-\\d{2,4}\\b)", text, 1);
    if (!day) return fallback;

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone localTimeZone];
    BOOL fourDigitYear = [[[day componentsSeparatedByString:@"-"] lastObject] length] == 4;
    formatter.dateFormat = fourDigitYear
        ? (time ? @"dd-MMM-yyyy HH:mm" : @"dd-MMM-yyyy")
        : (time ? @"dd-MMM-yy HH:mm" : @"dd-MMM-yy");
    NSDate *parsed = [formatter dateFromString:time ? [NSString stringWithFormat:@"%@ %@", day, time] : day];
    return parsed ?: fallback;
}

static NSDictionary *ParseTransaction(NSString *text, NSDate *fallbackDate) {
    NSString *lower = text.lowercaseString;
    BOOL expense = [lower containsString:@"used for"] || [lower containsString:@"debited"] ||
        [lower containsString:@"purchase"] || [lower containsString:@"spent"] ||
        [lower containsString:@"withdrawn"] || [lower containsString:@"paid"];
    BOOL income = [lower containsString:@"credited"] || [lower containsString:@"received"] ||
        [lower containsString:@"refund"] || [lower containsString:@"reversed"];
    if (!expense && !income) return nil;

    NSString *amountText = Capture(@"\\b(?:QAR|QR)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b", text, 1);
    if (!amountText) return nil;
    amountText = [amountText stringByReplacingOccurrencesOfString:@"," withString:@""];
    NSDecimalNumber *amount = [NSDecimalNumber decimalNumberWithString:amountText locale:@{NSLocaleDecimalSeparator: @"."}];
    if ([amount isEqualToNumber:[NSDecimalNumber notANumber]] || amount.doubleValue <= 0) return nil;

    NSString *vendor = Capture(
        @"\\b(?:at|to)\\s+(.+?)(?=\\s+at\\s+\\d{1,2}:\\d{2}(?::\\d{2})?\\b|\\s+on\\s+\\d|\\s+\\d{1,2}-[A-Za-z]{3}-\\d{2,4}\\b|\\s+Available\\s+(?:Limit|Balance)\\b|\\s+Balance\\b|$)",
        text,
        1
    );
    vendor = vendor ? CleanWhitespace(vendor) : @"Unknown Vendor";
    return @{
        @"type": income && !expense ? @"income" : @"expense",
        @"amount": amount,
        @"vendor": vendor,
        @"date": TransactionDate(text, fallbackDate ?: [NSDate date]),
        @"details": text
    };
}

static NSArray<NSDictionary *> *DefaultRules(void) {
    return @[
        @{@"keyword": @"restaurant", @"category": @"Restaurant"},
        @{@"keyword": @"cafe", @"category": @"Restaurant"},
        @{@"keyword": @"coffee", @"category": @"Restaurant"},
        @{@"keyword": @"grocery", @"category": @"Grocery"},
        @{@"keyword": @"supermarket", @"category": @"Grocery"},
        @{@"keyword": @"hypermarket", @"category": @"Grocery"},
        @{@"keyword": @"woqod", @"category": @"Fuel"},
        @{@"keyword": @"petrol", @"category": @"Fuel"},
        @{@"keyword": @"fuel", @"category": @"Fuel"},
        @{@"keyword": @"uber", @"category": @"Transport"},
        @{@"keyword": @"karwa", @"category": @"Transport"},
        @{@"keyword": @"taxi", @"category": @"Transport"},
        @{@"keyword": @"pharmacy", @"category": @"Health"},
        @{@"keyword": @"clinic", @"category": @"Health"},
        @{@"keyword": @"hospital", @"category": @"Health"}
    ];
}

static NSString *CategoryForVendor(NSString *vendor, NSArray *rules) {
    NSArray *effectiveRules = rules.count > 0 ? rules : DefaultRules();
    for (NSDictionary *rule in effectiveRules) {
        NSString *keyword = rule[@"keyword"];
        NSString *category = rule[@"category"];
        if (keyword.length > 0 && category.length > 0 &&
            [vendor rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) return category;
    }
    return @"Other";
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

static NSString *ISODate(NSDate *date) {
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    return [formatter stringFromDate:date];
}

static NSString *LedgerFilePath(void) {
    NSArray<NSString *> *bases = @[
        @"/rootfs/var/mobile/Containers/Data/Application",
        @"/var/mobile/Containers/Data/Application"
    ];
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *base in bases) {
        for (NSString *container in [manager contentsOfDirectoryAtPath:base error:nil]) {
            NSString *root = [base stringByAppendingPathComponent:container];
            NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:
                [root stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
            if ([metadata[@"MCMMetadataIdentifier"] isEqualToString:kBundleIdentifier]) {
                return [root stringByAppendingPathComponent:@"Library/Application Support/DailyLedger/ledger.json"];
            }
        }
    }
    return nil;
}

static NSMutableDictionary *NewLedger(void) {
    NSMutableArray *rules = [NSMutableArray array];
    for (NSDictionary *item in DefaultRules()) {
        [rules addObject:@{@"id": [NSUUID UUID].UUIDString, @"keyword": item[@"keyword"], @"category": item[@"category"]}];
    }
    NSString *now = ISODate([NSDate date]);
    return [@{
        @"version": @3,
        @"transactions": [NSMutableArray array],
        @"accounts": [NSMutableArray arrayWithObject:@{
            @"id": kLegacyAccountID,
            @"name": @"Main Account",
            @"currencyCode": @"QAR",
            @"group": @"qatar",
            @"icon": @"wallet.pass.fill",
            @"openingBalance": @0,
            @"isArchived": @NO,
            @"createdAt": now
        }],
        @"settings": [@{
            @"currencyCode": @"QAR",
            @"vendorRules": rules,
            @"smsAutoImportEnabled": @YES,
            @"defaultAccountID": kLegacyAccountID,
            @"smsMatchText": kDefaultMatchText,
            @"smsDestinationAccountID": kLegacyAccountID,
            @"smsRescanRequestID": @0
        } mutableCopy]
    } mutableCopy];
}

static NSMutableDictionary *ReadLedger(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    return [value isKindOfClass:[NSMutableDictionary class]] ? value : NewLedger();
}

static BOOL WriteLedger(NSMutableDictionary *ledger, NSString *path) {
    NSData *output = [NSJSONSerialization dataWithJSONObject:ledger
                                                     options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                       error:nil];
    if (!output) return NO;
    BOOL success = [output writeToFile:path options:NSDataWritingAtomic error:nil];
    if (success) {
        [[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}
                                         ofItemAtPath:path
                                                error:nil];
    }
    return success;
}

static int LockLedger(NSString *ledgerPath) {
    NSString *directory = [ledgerPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    int descriptor = open([[directory stringByAppendingPathComponent:@"ledger.lock"] fileSystemRepresentation],
                          O_CREAT | O_RDWR, S_IRUSR | S_IWUSR);
    if (descriptor < 0) return -1;
    struct flock lock = {.l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0};
    if (fcntl(descriptor, F_SETLKW, &lock) != 0) {
        close(descriptor);
        return -1;
    }
    return descriptor;
}

static void UnlockLedger(int descriptor) {
    if (descriptor < 0) return;
    struct flock lock = {.l_type = F_UNLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0};
    fcntl(descriptor, F_SETLK, &lock);
    close(descriptor);
}

static NSString *DestinationAccountID(NSDictionary *ledger, NSDictionary *settings) {
    NSArray *accounts = ledger[@"accounts"];
    NSString *preferred = settings[@"smsDestinationAccountID"] ?: settings[@"defaultAccountID"];
    for (NSDictionary *account in accounts) if ([account[@"id"] isEqualToString:preferred]) return preferred;
    return [accounts.firstObject objectForKey:@"id"] ?: kLegacyAccountID;
}

static NSString *DestinationAccountName(NSDictionary *ledger, NSString *identifier) {
    for (NSDictionary *account in ledger[@"accounts"]) {
        if ([account[@"id"] isEqualToString:identifier]) return account[@"name"] ?: @"selected account";
    }
    return @"selected account";
}

static AppendResult AppendTransaction(NSString *ledgerPath, NSDictionary *parsed, NSString *sourceKey) {
    int descriptor = LockLedger(ledgerPath);
    if (descriptor < 0) return AppendResultFailed;
    AppendResult result = AppendResultFailed;
    @try {
        NSMutableDictionary *ledger = ReadLedger(ledgerPath);
        NSMutableDictionary *settings = ledger[@"settings"];
        if (![settings isKindOfClass:[NSMutableDictionary class]]) {
            settings = [NewLedger()[@"settings"] mutableCopy];
            ledger[@"settings"] = settings;
        }
        if (settings[@"smsAutoImportEnabled"] && ![settings[@"smsAutoImportEnabled"] boolValue]) {
            result = AppendResultDisabled;
            @throw [NSException exceptionWithName:@"DailyLedgerDisabled" reason:nil userInfo:nil];
        }

        NSMutableArray *transactions = ledger[@"transactions"];
        if (![transactions isKindOfClass:[NSMutableArray class]]) {
            transactions = [NSMutableArray array];
            ledger[@"transactions"] = transactions;
        }
        NSString *identifier = DeterministicUUID(sourceKey).UUIDString;
        for (NSDictionary *item in transactions) {
            BOOL sameIdentifier = [item[@"id"] isEqualToString:identifier];
            BOOL sameSMS = [item[@"details"] isEqualToString:parsed[@"details"]] &&
                [item[@"amount"] compare:parsed[@"amount"]] == NSOrderedSame;
            if (sameIdentifier || sameSMS) {
                result = AppendResultDuplicate;
                @throw [NSException exceptionWithName:@"DailyLedgerDuplicate" reason:nil userInfo:nil];
            }
        }

        NSString *accountID = DestinationAccountID(ledger, settings);
        NSString *category = CategoryForVendor(parsed[@"vendor"], settings[@"vendorRules"]);
        [transactions addObject:@{
            @"id": identifier,
            @"type": parsed[@"type"],
            @"amount": parsed[@"amount"],
            @"date": ISODate(parsed[@"date"]),
            @"category": category,
            @"vendor": parsed[@"vendor"],
            @"details": parsed[@"details"],
            @"accountID": accountID,
            @"createdAt": ISODate([NSDate date])
        }];
        ledger[@"version"] = @3;
        result = WriteLedger(ledger, ledgerPath) ? AppendResultImported : AppendResultFailed;
        if (result == AppendResultImported) {
            Log(@"Recorded %@ %@ as %@ (%@)", parsed[@"type"], parsed[@"amount"], parsed[@"vendor"], category);
        }
    } @catch (NSException *exception) {
        if (![exception.name hasPrefix:@"DailyLedger"]) {
            Log(@"Ledger write exception: %@", exception.reason ?: exception.name);
            result = AppendResultFailed;
        }
    } @finally {
        UnlockLedger(descriptor);
    }
    return result;
}

static void UpdateStatus(NSString *ledgerPath, NSString *message) {
    int descriptor = LockLedger(ledgerPath);
    if (descriptor < 0) return;
    NSMutableDictionary *ledger = ReadLedger(ledgerPath);
    NSMutableDictionary *settings = ledger[@"settings"];
    if (![settings isKindOfClass:[NSMutableDictionary class]]) {
        settings = [NewLedger()[@"settings"] mutableCopy];
        ledger[@"settings"] = settings;
    }
    settings[@"smsImporterLastCheck"] = ISODate([NSDate date]);
    settings[@"smsImporterLastResult"] = message;
    WriteLedger(ledger, ledgerPath);
    UnlockLedger(descriptor);
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kChangeNotification,
        NULL,
        NULL,
        true
    );
}

static NSString *SMSDatabasePath(void) {
    NSArray *paths = @[@"/rootfs/var/mobile/Library/SMS/sms.db", @"/var/mobile/Library/SMS/sms.db"];
    for (NSString *path in paths) if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    return nil;
}

static sqlite3_int64 MaximumRowID(sqlite3 *database) {
    sqlite3_stmt *statement = NULL;
    sqlite3_int64 value = 0;
    if (sqlite3_prepare_v2(database, "SELECT COALESCE(MAX(ROWID), 0) FROM message", -1, &statement, NULL) == SQLITE_OK &&
        sqlite3_step(statement) == SQLITE_ROW) value = sqlite3_column_int64(statement, 0);
    sqlite3_finalize(statement);
    return value;
}

static NSString *StatePath(void) {
    return [StateDirectory() stringByAppendingPathComponent:@"state.plist"];
}

static NSMutableDictionary *LoadState(void) {
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:StatePath()];
    return stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
}

static void SaveState(NSDictionary *state) {
    [[NSFileManager defaultManager] createDirectoryAtPath:StateDirectory()
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [state writeToFile:StatePath() atomically:YES];
}

// On iOS 16 some messages keep their body in attributedBody rather than text.
// The archived body still contains the visible ASCII runs, so recover and join them.
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
    return runs.count > 0 ? [runs componentsJoinedByString:@"\n"] : nil;
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
            id value = [NSKeyedUnarchiver unarchiveObjectWithData:data];
#pragma clang diagnostic pop
            if ([value isKindOfClass:[NSAttributedString class]]) {
                NSString *decoded = [value string];
                if (decoded.length > 0) return decoded;
            }
            if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
        } @catch (__unused NSException *exception) {
            // Fall through to the resilient archive scanner below.
        }
    }
    return TextFromAttributedBody(bytes, length);
}

static void SignalSuccessfulImport(void) {
    // Exactly one short vibration per successful scan batch, never for a
    // non-match, parse failure, or duplicate transaction.
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

static void ProcessMessages(BOOL forceRecent) {
    NSString *ledgerPath = LedgerFilePath();
    if (!ledgerPath) {
        Log(@"Daily Ledger container was not found. Open the app once, then reinstall or restart this service.");
        return;
    }

    NSDictionary *ledgerSnapshot = ReadLedger(ledgerPath);
    NSDictionary *settings = ledgerSnapshot[@"settings"];
    BOOL enabled = settings[@"smsAutoImportEnabled"] ? [settings[@"smsAutoImportEnabled"] boolValue] : YES;
    NSString *matchText = [settings[@"smsMatchText"] isKindOfClass:[NSString class]] ? settings[@"smsMatchText"] : kDefaultMatchText;
    if (matchText.length == 0) matchText = kDefaultMatchText;
    NSInteger requestID = [settings[@"smsRescanRequestID"] integerValue];
    NSString *accountID = DestinationAccountID(ledgerSnapshot, settings ?: @{});
    NSString *accountName = DestinationAccountName(ledgerSnapshot, accountID);
    if (!enabled) {
        if (forceRecent) UpdateStatus(ledgerPath, @"Automatic SMS import is turned off.");
        return;
    }

    NSString *databasePath = SMSDatabasePath();
    if (!databasePath) {
        if (forceRecent) UpdateStatus(ledgerPath, @"Messages database could not be opened by the RootHide service.");
        return;
    }
    sqlite3 *database = NULL;
    if (sqlite3_open_v2(databasePath.fileSystemRepresentation, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
        if (database) sqlite3_close(database);
        if (forceRecent) UpdateStatus(ledgerPath, @"Messages database could not be opened by the RootHide service.");
        return;
    }
    sqlite3_busy_timeout(database, 2500);

    NSMutableDictionary *state = LoadState();
    NSNumber *savedRow = state[@"lastRowID"];
    NSInteger savedRequestID = [state[@"lastRescanRequestID"] integerValue];
    NSInteger stateVersion = [state[@"version"] integerValue];
    sqlite3_int64 maximum = MaximumRowID(database);
    BOOL scanRecent = forceRecent || !savedRow || stateVersion < 3 || requestID != savedRequestID;
    sqlite3_int64 lastRowID = scanRecent ? MAX((sqlite3_int64)0, maximum - 2000) : savedRow.longLongValue;
    BOOL hasNewRows = maximum > lastRowID;
    if (!hasNewRows && !scanRecent) {
        sqlite3_close(database);
        return;
    }

    const char *query =
        "SELECT m.ROWID, COALESCE(m.guid, ''), m.text, m.attributedBody, m.date "
        "FROM message m "
        "WHERE m.ROWID > ? AND m.ROWID <= ? AND m.is_from_me = 0 "
        "AND (m.text IS NOT NULL OR m.attributedBody IS NOT NULL) "
        "ORDER BY m.ROWID ASC";
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, query, -1, &statement, NULL) != SQLITE_OK) {
        sqlite3_close(database);
        UpdateStatus(ledgerPath, @"Messages database format is not supported.");
        return;
    }
    sqlite3_bind_int64(statement, 1, lastRowID);
    sqlite3_bind_int64(statement, 2, maximum);

    sqlite3_int64 processedRowID = lastRowID;
    NSInteger matched = 0;
    NSInteger imported = 0;
    NSInteger duplicates = 0;
    NSInteger parseFailures = 0;
    BOOL writeFailed = NO;
    while (sqlite3_step(statement) == SQLITE_ROW) {
        sqlite3_int64 rowID = sqlite3_column_int64(statement, 0);
        NSString *text = MessageText(statement);
        if (text.length == 0 || [text rangeOfString:matchText options:NSCaseInsensitiveSearch].location == NSNotFound) {
            processedRowID = rowID;
            continue;
        }
        matched += 1;
        NSDictionary *parsed = ParseTransaction(text, DatabaseDate(sqlite3_column_int64(statement, 4)));
        if (!parsed) {
            parseFailures += 1;
            processedRowID = rowID;
            continue;
        }
        const unsigned char *guidBytes = sqlite3_column_text(statement, 1);
        NSString *guid = guidBytes ? [NSString stringWithUTF8String:(const char *)guidBytes] : @"";
        NSString *source = guid.length > 0 ? guid : [NSString stringWithFormat:@"%lld|%@", rowID, text];
        AppendResult result = AppendTransaction(ledgerPath, parsed, source);
        if (result == AppendResultFailed) {
            writeFailed = YES;
            Log(@"Could not store SMS row %lld; it will be retried.", rowID);
            break;
        }
        if (result == AppendResultImported) imported += 1;
        if (result == AppendResultDuplicate) duplicates += 1;
        processedRowID = rowID;
    }
    sqlite3_finalize(statement);
    sqlite3_close(database);

    if (!writeFailed) processedRowID = maximum;
    state[@"lastRowID"] = @(processedRowID);
    state[@"lastRescanRequestID"] = @(requestID);
    state[@"version"] = @3;
    SaveState(state);

    NSString *status;
    if (writeFailed) {
        status = @"A matching SMS was found, but Daily Ledger could not save it. It will retry automatically.";
    } else if (imported > 0) {
        status = [NSString stringWithFormat:@"Imported %ld matching SMS%@ to %@.", (long)imported, imported == 1 ? @"" : @" messages", accountName];
        SignalSuccessfulImport();
    } else if (parseFailures > 0) {
        status = [NSString stringWithFormat:@"Found %ld SMS containing %@, but its transaction fields could not be parsed.", (long)parseFailures, matchText];
    } else if (matched > 0 && duplicates > 0) {
        status = [NSString stringWithFormat:@"The latest matching SMS containing %@ was already recorded.", matchText];
    } else {
        status = [NSString stringWithFormat:@"No recent SMS containing %@ was found.", matchText];
    }
    UpdateStatus(ledgerPath, status);
    Log(@"%@", status);
}

static int RunSelfTest(void) {
    NSString *sample = @"Your card ending **6760\nused for QAR 20.00\nat NEW NASCO RESTAURANT\nat 14:03\n07-May-26\nAvailable Limit: QAR 107.01";
    NSDictionary *parsed = ParseTransaction(sample, [NSDate dateWithTimeIntervalSince1970:0]);
    NSString *category = CategoryForVendor(parsed[@"vendor"], DefaultRules());
    BOOL markerMatches = [sample rangeOfString:kDefaultMatchText].location != NSNotFound;
    BOOL passed = parsed && markerMatches &&
        [parsed[@"amount"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"20.00"]] &&
        [parsed[@"vendor"] isEqualToString:@"NEW NASCO RESTAURANT"] && [category isEqualToString:@"Restaurant"];
    NSDictionary *result = parsed ? @{
        @"passed": @(passed), @"marker": kDefaultMatchText, @"amount": parsed[@"amount"],
        @"vendor": parsed[@"vendor"], @"category": category, @"type": parsed[@"type"],
        @"date": ISODate(parsed[@"date"])
    } : @{@"passed": @NO};
    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    fprintf(stdout, "%s\n", [[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] UTF8String]);
    return passed ? 0 : 1;
}

#if defined(DAILYLEDGER_TWEAK)
static dispatch_source_t gDailyLedgerTimer;

__attribute__((constructor))
static void DailyLedgerSMSImportInitialize(void) {
    @autoreleasepool {
        Log(@"Daily Ledger SMS Import 1.2.0 tweak loaded in SpringBoard; exact marker is %@.", kDefaultMatchText);
        dispatch_queue_t queue = dispatch_queue_create("com.nextsolution.dailyledger.smsimport", DISPATCH_QUEUE_SERIAL);
        gDailyLedgerTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_timer(gDailyLedgerTimer, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(gDailyLedgerTimer, ^{
            @autoreleasepool { ProcessMessages(NO); }
        });
        dispatch_resume(gDailyLedgerTimer);
    }
}
#else
int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--self-test") == 0) return RunSelfTest();
        if (argc > 1 && strcmp(argv[1], "--scan-recent") == 0) {
            ProcessMessages(YES);
            return 0;
        }
        Log(@"Daily Ledger SMS Import 1.1.3 started in mobile GUI domain; exact marker is %@.", kDefaultMatchText);
        while (true) {
            @autoreleasepool { ProcessMessages(NO); }
            sleep(5);
        }
    }
    return 0;
}
#endif
