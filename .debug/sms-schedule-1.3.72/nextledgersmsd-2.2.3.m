#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <sqlite3.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>

static NSString *const kBundleIdentifier = @"com.nextsolution.dailyledger";
static NSString *const kDarwinChangeNotification = @"com.nextsolution.dailyledger.external-change";
static NSString *const kDaemonVersion = @"2.2.3";

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
        @"/rootfs/private/var/mobile/Library/NextLedgerSMSImport",
        @"/rootfs/var/mobile/Library/NextLedgerSMSImport",
        @"/private/var/mobile/Library/NextLedgerSMSImport",
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
    while (logs.count > 40) [logs removeObjectAtIndex:0];
    gState[@"logs"] = logs;
    NSLog(@"[NextLedgerSMS] %@: %@", level.uppercaseString, message);
    SaveState();
}

static NSString *ApplicationContainer(void) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSArray<NSString *> *bases = @[
        @"/rootfs/private/var/mobile/Containers/Data/Application",
        @"/rootfs/var/mobile/Containers/Data/Application",
        @"/private/var/mobile/Containers/Data/Application",
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

static NSString *DraftsPath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"sms-import-drafts.json"] : nil;
}

static NSString *ReviewedIDsPath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"sms-import-reviewed.json"] : nil;
}

static NSString *AICandidatesPath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"sms-ai-candidates.json"] : nil;
}

static NSString *AIProcessedIDsPath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"sms-ai-processed.json"] : nil;
}

static NSString *LatestReviewPath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"sms-latest15-review.json"] : nil;
}

static NSString *DraftLockPath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"sms-import-drafts.lock"] : nil;
}

static NSArray *ReadJSONArray(NSString *path) {
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    if (!data) return @[];
    id value = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

static BOOL WriteJSONArray(NSArray *array, NSString *path) {
    if (!path || ![NSJSONSerialization isValidJSONObject:array]) return NO;
    EnsureDirectory(path.stringByDeletingLastPathComponent);
    NSData *data = [NSJSONSerialization dataWithJSONObject:array
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    return data && [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

static int AcquireDraftLock(void) {
    NSString *path = DraftLockPath();
    if (!path) return -1;
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

static void ReleaseDraftLock(int descriptor) {
    if (descriptor < 0) return;
    struct flock lock = {.l_type = F_UNLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0};
    fcntl(descriptor, F_SETLK, &lock);
    close(descriptor);
}

static NSDictionary *LoadConfiguration(void) {
    NSDictionary *config = ReadJSON(ConfigurationPath());
    return config ?: @{
        @"enabled": @YES,
        @"autoRecord": @NO,
        @"customEnding": @"",
        @"customAccountID": @"",
        @"clearLogsRequestID": @0,
        @"cardAccountIDs": @{},
        @"approvedSenders": @[@"Cb SMS"],
        @"automaticScanIntervalHours": @6,
        @"scanRequestID": @0
    };
}

static NSInteger PendingCount(void) {
    return ReadJSONArray(DraftsPath()).count;
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
        @"aiCandidateCount": @(ReadJSONArray(AICandidatesPath()).count),
        @"scanInProgress": gState[@"scanInProgress"] ?: @NO,
        @"scanProgressCurrent": gState[@"scanProgressCurrent"] ?: @0,
        @"scanProgressTotal": gState[@"scanProgressTotal"] ?: @0,
        @"scanPhase": gState[@"scanPhase"] ?: @"Idle",
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
        @{@"pattern": @"\\b(\\d{1,2}-[A-Za-z]{3}-\\d{2})\\s+(\\d{1,2}:\\d{2})\\b", @"format": @"dd-MMM-yy HH:mm"},
        @{@"pattern": @"\\b(\\d{1,2}:\\d{2}),?\\s+(\\d{1,2}-[A-Za-z]{3}-\\d{4})\\b", @"format": @"HH:mm dd-MMM-yyyy"},
        @{@"pattern": @"\\b(\\d{1,2}:\\d{2}),?\\s+(\\d{1,2}-[A-Za-z]{3}-\\d{2})\\b", @"format": @"HH:mm dd-MMM-yy"}
    ];
    for (NSDictionary *item in patterns) {
        NSString *first = Capture(item[@"pattern"], text, 1);
        NSString *second = Capture(item[@"pattern"], text, 2);
        if (!first || !second) continue;
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = NSTimeZone.localTimeZone;
        formatter.dateFormat = item[@"format"];
        NSDate *date = [formatter dateFromString:[NSString stringWithFormat:@"%@ %@", first, second]];
        if (date) return date;
    }
    return fallback ?: NSDate.date;
}

static NSDictionary *ParseTransaction(NSString *text, NSDate *fallbackDate) {
    NSString *clean = CleanWhitespace(text);
    NSString *lower = clean.lowercaseString;
    NSString *kind = nil;
    if ([lower containsString:@"reversal of transaction"] && [lower containsString:@"card ending"]) kind = @"reversal";
    else if ([lower containsString:@"cashback"] && [lower containsString:@"credited"]) kind = @"cashback";
    else if ([lower containsString:@"withdrawal using"]) kind = @"withdrawal";
    else if ([lower containsString:@"current acc"] && [lower containsString:@"credited with"] && [lower containsString:@"atm cash deposit"]) kind = @"cashDeposit";
    else if ([lower containsString:@"current acc"] && [lower containsString:@"credited with"] && [lower containsString:@"fawran instant payment"]) kind = @"incomingTransfer";
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
    if (!ending) ending = Capture(@"\\bCurrent\\s+Acc\\s+x{2,}(\\d{4,8})\\b", clean, 1);
    if (!ending) return nil;

    NSString *vendor = nil;
    if ([kind isEqualToString:@"expense"]) {
        vendor = Capture(@"\\b(?:was\\s+)?used for\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,.]*\\s+at\\s+(.+?)(?=\\s+at\\s+\\d{1,2}:\\d{2}\\s+\\d{1,2}-[A-Za-z]{3}-\\d{2,4}|\\s+at\\s+\\d{1,2}/\\d{1,2}/\\d{2,4}|\\s+on\\s+\\d{1,2}/|\\s+available\\s+limit|\\s+balance:|\\s+enquiry\\s+\\d+|$)", clean, 1);
    } else if ([kind isEqualToString:@"withdrawal"]) {
        vendor = Capture(@"\\bat\\s+(.+?)(?=\\s+your available|\\s+available balance|$)", clean, 1);
    } else if ([kind isEqualToString:@"incomingTransfer"]) {
        vendor = Capture(@"\\bref\\s+(.+?)(?=\\s+withM-|\\s+at\\s+\\d{1,2}:\\d{2}|$)", clean, 1) ?: @"Fawran Instant Payment";
    } else if ([kind isEqualToString:@"cashback"]) {
        vendor = @"Credit Card Cashback";
    } else if ([kind isEqualToString:@"reversal"]) {
        vendor = Capture(@"\\bat\\s+(.+?)(?=\\s+for\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)|$)", clean, 1) ?: @"Transaction Reversal";
    } else if ([kind isEqualToString:@"cashDeposit"]) {
        vendor = @"ATM Cash Deposit";
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

static NSArray<NSString *> *SMSDatabaseCandidates(void) {
    return @[
        @"/rootfs/private/var/mobile/Library/SMS/sms.db",
        @"/rootfs/var/mobile/Library/SMS/sms.db",
        @"/private/var/mobile/Library/SMS/sms.db",
        @"/var/mobile/Library/SMS/sms.db"
    ];
}


static BOOL LooksLikeTransactionForReview(NSString *text) {
    NSString *clean = CleanWhitespace(text);
    NSString *lower = clean.lowercaseString;
    NSString *currency = Capture(@"\\b(QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b", clean, 1);
    if (currency.length == 0) return NO;

    NSArray<NSString *> *signals = @[
        @"credited", @"debited", @"a/c debit", @"account debit",
        @"used for", @"purchase", @"withdrawal", @"transfer", @"fawran",
        @"instant payment", @"card payment", @"received", @"sent",
        @"payment", @"remittance"
    ];
    for (NSString *signal in signals) {
        if ([lower containsString:signal]) return YES;
    }
    return YES; // approved-bank currency movement: never silently drop; user/AI reviews it.
}

static NSDictionary *ReviewDraftForUnrecognizedBankSMS(NSString *text, NSDate *fallbackDate) {
    NSString *clean = CleanWhitespace(text);
    if (!LooksLikeTransactionForReview(clean)) return nil;

    NSString *currency = Capture(@"\\b(QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b", clean, 1);
    NSString *amountText = Capture(@"\\b(QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b", clean, 2);
    if (!currency || !amountText) return nil;
    if ([currency.uppercaseString isEqualToString:@"QR"]) currency = @"QAR";
    amountText = [amountText stringByReplacingOccurrencesOfString:@"," withString:@""];
    NSDecimalNumber *amount = [NSDecimalNumber decimalNumberWithString:amountText locale:@{NSLocaleDecimalSeparator: @"."}];
    if ([amount isEqualToNumber:NSDecimalNumber.notANumber] || amount.doubleValue <= 0) return nil;

    NSString *lower = clean.lowercaseString;
    BOOL accountDebit = [lower containsString:@"a/c debit"] || [lower containsString:@"account debit"];
    NSString *kind = @"reviewTransaction";
    if ((accountDebit && [lower containsString:@"card payment"]) ||
        [lower containsString:@"transfer"] ||
        [lower containsString:@"fawran"] ||
        [lower containsString:@"instant payment"] ||
        [lower containsString:@"remittance"] ||
        [lower containsString:@"sent to"]) {
        kind = @"reviewTransfer";
    } else if ([lower containsString:@"credited"] || [lower containsString:@"received"]) {
        kind = @"reviewIncome";
    } else if ([lower containsString:@"debited"] ||
               accountDebit ||
               [lower containsString:@"used for"] ||
               [lower containsString:@"purchase"] ||
               [lower containsString:@"withdrawal"]) {
        kind = @"reviewExpense";
    }

    NSString *ending = Capture(@"\\*\\*(\\d{4,8})", clean, 1);
    if (!ending) ending = Capture(@"\\b(?:Current\\s+)?Acc(?:ount)?\\s+x{2,}(\\d{4,8})\\b", clean, 1);
    if (!ending) ending = Capture(@"\\b([A-Za-z][A-Za-z0-9_-]{1,15})\\s+a/c\\s+debit\\b", clean, 1);
    if (!ending) ending = Capture(@"\\b([A-Za-z][A-Za-z0-9_-]{1,15})\\s+account\\s+debit\\b", clean, 1);
    if (!ending) ending = @"";
    ending = ending.uppercaseString;

    NSString *vendor = nil;
    if (accountDebit) {
        vendor = Capture(@"\\bfor\\s+(.+?)(?=\\s+at\\s+\\d{1,2}:\\d{2}|$)", clean, 1);
    }
    if (!vendor) vendor = Capture(@"\\bref\\s+(.+?)(?=\\s+withM-|\\s+at\\s+\\d{1,2}:\\d{2}|$)", clean, 1);
    if (!vendor) vendor = Capture(@"\\bat\\s+(.+?)(?=\\s+at\\s+\\d{1,2}:\\d{2}|\\s+on\\s+\\d|\\s+balance|\\s+available|$)", clean, 1);
    if (!vendor) vendor = Capture(@"\\bfrom\\s+(.+?)(?=\\s+at\\s+\\d|\\s+on\\s+\\d|$)", clean, 1);
    vendor = CleanWhitespace(vendor ?: @"Review Required");

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
    for (NSString *path in SMSDatabaseCandidates()) {
        errno = 0;
        if (access(path.fileSystemRepresentation, R_OK) == 0) return path;
    }
    return nil;
}

static NSString *PathProbe(NSString *path) {
    struct stat info;
    errno = 0;
    if (stat(path.fileSystemRepresentation, &info) == 0) {
        unsigned int mode = (unsigned int)(info.st_mode & 0777);
        errno = 0;
        if (access(path.fileSystemRepresentation, R_OK) == 0) {
            return [NSString stringWithFormat:@"%@ = readable (mode %03o uid %u gid %u)",
                path, mode, (unsigned int)info.st_uid, (unsigned int)info.st_gid];
        }
        int code = errno;
        return [NSString stringWithFormat:@"%@ = exists but unreadable: %s (%d), mode %03o uid %u gid %u",
            path, strerror(code), code, mode, (unsigned int)info.st_uid, (unsigned int)info.st_gid];
    }

    int code = errno;
    NSString *parent = path.stringByDeletingLastPathComponent;
    struct stat parentInfo;
    errno = 0;
    BOOL parentExists = stat(parent.fileSystemRepresentation, &parentInfo) == 0;
    int parentCode = errno;
    NSString *parentStatus = parentExists
        ? [NSString stringWithFormat:@"parent exists mode %03o uid %u gid %u",
            (unsigned int)(parentInfo.st_mode & 0777),
            (unsigned int)parentInfo.st_uid,
            (unsigned int)parentInfo.st_gid]
        : [NSString stringWithFormat:@"parent unavailable: %s (%d)", strerror(parentCode), parentCode];
    return [NSString stringWithFormat:@"%@ = unavailable: %s (%d); %@",
        path, strerror(code), code, parentStatus];
}

__attribute__((unused)) static NSString *SMSDatabaseDiagnostics(void) {
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:
        [NSString stringWithFormat:@"process uid=%d euid=%d gid=%d egid=%d",
            getuid(), geteuid(), getgid(), getegid()]];
    for (NSString *path in SMSDatabaseCandidates()) [parts addObject:PathProbe(path)];
    return [parts componentsJoinedByString:@" | "];
}

__attribute__((unused)) static NSString *StringFromDecodedObject(id object) {
    if ([object isKindOfClass:NSAttributedString.class]) return [object string];
    if ([object isKindOfClass:NSString.class]) return object;
    NSString *best = nil;
    NSArray *values = nil;
    if ([object isKindOfClass:NSDictionary.class]) values = [(NSDictionary *)object allValues];
    else if ([object isKindOfClass:NSArray.class]) values = object;
    for (id value in values ?: @[]) {
        NSString *candidate = StringFromDecodedObject(value);
        if (candidate.length > best.length) best = candidate;
    }
    return best;
}

static NSString *CleanBankMessage(NSString *candidate) {
    NSString *clean = CleanWhitespace(candidate ?: @"");
    if (clean.length == 0) return nil;

    NSArray<NSString *> *completePatterns = @[
        @"\\b(Your card ending\\s+\\*\\*\\d{4}\\s+(?:was\\s+)?used for\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?.*?Available Limit(?:\\s+is|:)?\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)?\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b",
        @"\\b(Debit Card\\s+\\*\\*\\d{4}\\s+(?:was\\s+)?used for\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?.*?Enquiry\\s+\\d+)\\b",
        @"\\b(Debit Card\\s+\\*\\*\\d{4}\\s+(?:was\\s+)?used for\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?.*?Balance:\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b",
        @"\\b(Withdrawal using Debit Card\\s+\\*\\*\\d{4}\\s+for\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?.*?available balance is\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b",
        @"\\b(Bill Payment of\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?.*?was successful\\.?)",
        @"\\b(Cashback amount of\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?.*?Available Limit(?:\\s+is|:)?\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b",
        @"\\b(Current Acc\\s+x{2,}\\d{4,8}\\s+credited with\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?\\s+for ATM Cash Deposit.*?Current Acc Bal:\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b",
        @"\\b(Reversal of transaction on your card ending\\s+\\*\\*\\d{4}.*?for\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?.*?Available Limit(?:\\s+is|:)?\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)?\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b",
        @"\\b(Current Acc\\s+x{2,}\\d{4,8}\\s+credited with\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?\\s+for Fawran instant payment.*?Current Acc Bal:\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b"
    ];
    for (NSString *pattern in completePatterns) {
        NSString *match = Capture(pattern, clean, 1);
        if (match.length > 0) return CleanWhitespace(match);
    }

    NSArray<NSString *> *archiveMarkers = @[
        @"streamtyped", @"NSAttributedString", @"NSMutableAttributedString",
        @"NSKeyedArchiver", @"NSDictionary", @"NS.rangeval", @"NS.objects",
        @"$classname", @"$classes"
    ];
    BOOL containsArchiveData = NO;
    for (NSString *marker in archiveMarkers) {
        if ([clean rangeOfString:marker options:NSCaseInsensitiveSearch].location != NSNotFound) {
            containsArchiveData = YES;
            break;
        }
    }
    if (containsArchiveData) return nil;
    return clean;
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
    if (runs.count == 0) return nil;

    NSString *joined = [runs componentsJoinedByString:@" "];
    NSString *direct = CleanBankMessage(joined);
    if (direct.length > 0) return direct;

    NSArray<NSString *> *metadataMarkers = @[
        @"streamtyped", @"NSAttributedString", @"NSMutableAttributedString",
        @"NSKeyedArchiver", @"NSDictionary", @"NSArray", @"NSObject",
        @"NS.objects", @"NS.keys", @"NS.rangeval", @"$classname", @"$classes",
        @"__kIMMessagePartAttributeName", @"__kIMFileTransferGUIDAttributeName"
    ];
    NSMutableArray<NSString *> *useful = [NSMutableArray array];
    for (NSString *run in runs) {
        NSString *candidate = CleanWhitespace(run);
        if (candidate.length == 0) continue;
        BOOL metadata = NO;
        for (NSString *marker in metadataMarkers) {
            if ([candidate rangeOfString:marker options:NSCaseInsensitiveSearch].location != NSNotFound) {
                metadata = YES;
                break;
            }
        }
        if (!metadata) [useful addObject:candidate];
    }

    NSString *filtered = CleanWhitespace([useful componentsJoinedByString:@" "]);
    NSString *clean = CleanBankMessage(filtered);
    if (clean.length > 0) return clean;

    NSString *lower = filtered.lowercaseString;
    BOOL hasCurrency = Capture(@"\\b(QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9]", filtered, 1).length > 0;
    BOOL transactional = [lower containsString:@"a/c debit"] ||
        [lower containsString:@"account debit"] || [lower containsString:@"card payment"] ||
        [lower containsString:@"used for"] || [lower containsString:@"credited"] ||
        [lower containsString:@"withdrawal"] || [lower containsString:@"transfer"] ||
        [lower containsString:@"fawran"] || [lower containsString:@"payment"];
    return hasCurrency && transactional ? filtered : nil;
}

static NSString *MessageText(sqlite3_stmt *statement) {
    const unsigned char *textBytes = sqlite3_column_text(statement, 2);
    if (textBytes) {
        NSString *text = [NSString stringWithUTF8String:(const char *)textBytes];
        NSString *clean = CleanBankMessage(text);
        if (clean.length > 0) return clean;
    }

    const void *bytes = sqlite3_column_blob(statement, 3);
    int length = sqlite3_column_bytes(statement, 3);
    if (!bytes || length <= 0) return nil;

    // Typedstream-safe bounded scan. Never invoke NSKeyedUnarchiver here.
    int safeLength = MIN(length, 524288);
    return TextFromAttributedBody(bytes, safeLength);
}

static NSString *ReviewTextFromAttributedBody(const void *bytes, int length) {
    if (!bytes || length <= 0) return nil;
    const unsigned char *raw = bytes;
    NSMutableArray<NSString *> *runs = [NSMutableArray array];
    int start = -1;
    for (int index = 0; index <= length; index++) {
        BOOL printable = index < length && raw[index] >= 32 && raw[index] <= 126;
        if (printable && start < 0) start = index;
        if (!printable && start >= 0) {
            int runLength = index - start;
            if (runLength >= 3) {
                NSString *run = [[NSString alloc] initWithBytes:raw + start
                                                         length:(NSUInteger)runLength
                                                       encoding:NSUTF8StringEncoding];
                if (run.length > 0) [runs addObject:run];
            }
            start = -1;
        }
    }
    if (runs.count == 0) return nil;

    NSArray<NSString *> *metadata = @[
        @"streamtyped", @"NSAttributedString", @"NSMutableAttributedString",
        @"NSString", @"NSDictionary", @"NSArray", @"NSObject", @"NSValue",
        @"NS.objects", @"NS.keys", @"NS.rangeval", @"$classname", @"$classes",
        @"__kIMMessagePartAttributeName", @"__kIMFileTransferGUIDAttributeName"
    ];
    NSMutableArray<NSString *> *useful = [NSMutableArray array];
    for (NSString *run in runs) {
        BOOL archiveMetadata = NO;
        for (NSString *marker in metadata) {
            if ([run rangeOfString:marker options:NSCaseInsensitiveSearch].location != NSNotFound) {
                archiveMetadata = YES;
                break;
            }
        }
        if (!archiveMetadata) [useful addObject:run];
    }
    NSString *result = [[useful componentsJoinedByString:@"\n"]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return result.length ? result : nil;
}

static NSString *ReviewMessageText(sqlite3_stmt *statement) {
    const unsigned char *textBytes = sqlite3_column_text(statement, 2);
    if (textBytes) {
        NSString *value = [NSString stringWithUTF8String:(const char *)textBytes];
        if (value.length > 0) return value; // preserve complete m.text verbatim
    }

    const void *bytes = sqlite3_column_blob(statement, 3);
    int length = sqlite3_column_bytes(statement, 3);
    if (!bytes || length <= 0) return nil;

    // Manual review must never hang on typedstream data. Scan a bounded amount
    // and prefer the transaction-aware extractor, then the generic full-text one.
    int safeLength = MIN(length, 524288);
    NSString *transactionText = TextFromAttributedBody(bytes, safeLength);
    if (transactionText.length > 0) return transactionText;
    return ReviewTextFromAttributedBody(bytes, safeLength);
}

static NSInteger CollectLatestIncomingMessagesForReview(sqlite3 *database, NSInteger limit) {
    if (!database || limit <= 0) return 0;
    const char *query =
        "SELECT m.ROWID, COALESCE(m.guid, ''), m.text, m.attributedBody, m.date, COALESCE(h.id, '') "
        "FROM message m LEFT JOIN handle h ON m.handle_id = h.ROWID "
        "WHERE m.is_from_me = 0 AND (m.text IS NOT NULL OR m.attributedBody IS NOT NULL) "
        "ORDER BY m.ROWID DESC LIMIT ?";

    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, query, -1, &statement, NULL) != SQLITE_OK) {
        AddLog(@"error", @"Latest-15 review query failed: %s", sqlite3_errmsg(database));
        return 0;
    }
    sqlite3_bind_int(statement, 1, (int)limit);

    NSMutableArray *items = [NSMutableArray array];
    NSInteger rowNumber = 0;
    while (sqlite3_step(statement) == SQLITE_ROW) {
        rowNumber += 1;
        sqlite3_int64 rowID = sqlite3_column_int64(statement, 0);

        gState[@"scanProgressCurrent"] = @(MIN(rowNumber, limit));
        gState[@"scanProgressTotal"] = @(limit);
        gState[@"scanPhase"] = [NSString stringWithFormat:@"Reading message %ld of %ld",
                                 (long)MIN(rowNumber, limit), (long)limit];
        WriteConsole(@"Reading latest incoming Messages database rows…");

        NSString *details = ReviewMessageText(statement);
        if (details.length == 0) {
            details = [NSString stringWithFormat:@"[Message row %lld: body could not be decoded safely. Keep for user review.]", rowID];
            AddLog(@"warning", @"Latest-15 row %lld was kept for review with an unreadable-body marker.", rowID);
        }

        const unsigned char *guidBytes = sqlite3_column_text(statement, 1);
        const unsigned char *senderBytes = sqlite3_column_text(statement, 5);
        NSString *guid = guidBytes ? [NSString stringWithUTF8String:(const char *)guidBytes] : @"";
        NSString *sender = senderBytes ? [NSString stringWithUTF8String:(const char *)senderBytes] : @"";
        NSString *sourceKey = guid.length ? guid : [NSString stringWithFormat:@"%lld|%@", rowID, details];
        NSString *identifier = DeterministicUUID(sourceKey).UUIDString;

        [items addObject:@{
            @"id": identifier,
            @"sourceKey": sourceKey,
            @"sender": sender ?: @"",
            @"rowID": @(rowID),
            @"date": ISODate(DatabaseDate(sqlite3_column_int64(statement, 4))),
            @"details": details,
            @"queuedAt": ISODate(NSDate.date)
        }];
    }
    sqlite3_finalize(statement);

    BOOL written = WriteJSONArray(items, LatestReviewPath());
    if (!written) {
        AddLog(@"error", @"Could not write latest-15 review queue to the app container.");
        return 0;
    }
    gState[@"manualReviewCount"] = @(items.count);
    AddLog(@"success", @"Collected %ld latest incoming message%@ for user review.",
           (long)items.count, items.count == 1 ? @"" : @"s");
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kDarwinChangeNotification,
        NULL, NULL, true
    );
    return items.count;
}

static BOOL SenderMatchesCaptureList(NSDictionary *config, NSString *sender) {
    NSString *probe = CleanWhitespace(sender ?: @"").lowercaseString;
    if (probe.length == 0) return NO;
    NSArray *approved = [config[@"approvedSenders"] isKindOfClass:NSArray.class] ? config[@"approvedSenders"] : @[@"Cb SMS"];
    if (approved.count == 0) approved = @[@"Cb SMS"];
    for (id item in approved) {
        if (![item isKindOfClass:NSString.class]) continue;
        NSString *allowed = CleanWhitespace((NSString *)item).lowercaseString;
        if (allowed.length == 0) continue;
        if ([probe isEqualToString:allowed] || [probe containsString:allowed] || [allowed containsString:probe]) return YES;
    }
    return NO;
}

static NSInteger CaptureLatestApprovedMessagesForReview(sqlite3 *database, NSDictionary *config, NSInteger limit) {
    if (!database || limit <= 0) return 0;
    const char *query =
        "SELECT m.ROWID, COALESCE(m.guid, ''), m.text, m.attributedBody, m.date, COALESCE(h.id, '') "
        "FROM message m LEFT JOIN handle h ON m.handle_id = h.ROWID "
        "WHERE m.is_from_me = 0 AND (m.text IS NOT NULL OR m.attributedBody IS NOT NULL) "
        "ORDER BY m.ROWID DESC LIMIT ?";
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, query, -1, &statement, NULL) != SQLITE_OK) return 0;
    sqlite3_bind_int(statement, 1, (int)limit);

    NSMutableArray *items = [ReadJSONArray(LatestReviewPath()) mutableCopy] ?: [NSMutableArray array];
    NSMutableSet<NSString *> *known = [NSMutableSet set];
    for (NSDictionary *item in items) {
        NSString *key = [item[@"sourceKey"] isKindOfClass:NSString.class] ? item[@"sourceKey"] : nil;
        if (key.length > 0) [known addObject:key];
    }

    NSInteger added = 0;
    while (sqlite3_step(statement) == SQLITE_ROW) {
        const unsigned char *senderBytes = sqlite3_column_text(statement, 5);
        NSString *sender = senderBytes ? [NSString stringWithUTF8String:(const char *)senderBytes] : @"";
        if (!SenderMatchesCaptureList(config, sender)) continue;

        sqlite3_int64 rowID = sqlite3_column_int64(statement, 0);
        const unsigned char *guidBytes = sqlite3_column_text(statement, 1);
        NSString *guid = guidBytes ? [NSString stringWithUTF8String:(const char *)guidBytes] : @"";
        NSString *details = ReviewMessageText(statement);
        if (details.length == 0) details = [NSString stringWithFormat:@"[SMS row %lld from %@: full body could not be decoded safely]", rowID, sender ?: @"Unknown"];
        NSString *sourceKey = guid.length ? guid : [NSString stringWithFormat:@"%lld|%@|%@", rowID, sender ?: @"", details];
        if ([known containsObject:sourceKey]) continue;

        [known addObject:sourceKey];
        [items addObject:@{
            @"id": DeterministicUUID(sourceKey).UUIDString,
            @"sourceKey": sourceKey,
            @"sender": sender ?: @"",
            @"rowID": @(rowID),
            @"date": ISODate(DatabaseDate(sqlite3_column_int64(statement, 4))),
            @"details": details,
            @"queuedAt": ISODate(NSDate.date)
        }];
        added += 1;
    }
    sqlite3_finalize(statement);

    if (added == 0) return 0;
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSNumber *a = [left[@"rowID"] isKindOfClass:NSNumber.class] ? left[@"rowID"] : @0;
        NSNumber *b = [right[@"rowID"] isKindOfClass:NSNumber.class] ? right[@"rowID"] : @0;
        return [b compare:a];
    }];
    while (items.count > 100) [items removeLastObject];
    if (!WriteJSONArray(items, LatestReviewPath())) return 0;
    gState[@"manualReviewCount"] = @(items.count);
    AddLog(@"success", @"Captured %ld new approved-bank SMS into the persistent review inbox before parsing.", (long)added);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)kDarwinChangeNotification, NULL, NULL, true);
    return added;
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
    NSString *customEnding = [config[@"customEnding"] isKindOfClass:NSString.class] ? config[@"customEnding"] : @"";
    NSString *customAccountID = [config[@"customAccountID"] isKindOfClass:NSString.class] ? config[@"customAccountID"] : @"";
    if ([customEnding isEqualToString:ending] && AccountExists(accounts, customAccountID)) return customAccountID;
    if ([ending isEqualToString:@"6760"]) return AccountIDByName(accounts, @[@"6760", @"credit card", @"credit"]);
    if ([ending isEqualToString:@"0023"]) return AccountIDByName(accounts, @[@"0023", @"debit card", @"debit"]);
    return AccountIDByName(accounts, @[ending]);
}

static NSString *CashDestinationAccountID(NSDictionary *config, NSDictionary *ledger) {
    NSArray *accounts = ledger[@"accounts"] ?: @[];
    NSString *configured = config[@"cashAccountID"];
    if (AccountExists(accounts, configured)) return configured;
    return AccountIDByName(accounts, @[@"cash"]);
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

static BOOL QueueAICandidate(NSString *text, NSString *sourceKey, NSString *sender, sqlite3_int64 rowID, NSDate *date) {
    if (text.length == 0 || sourceKey.length == 0) return NO;
    NSString *identifier = DeterministicUUID(sourceKey).UUIDString;
    int descriptor = AcquireDraftLock();
    if (descriptor < 0) return NO;
    BOOL queued = NO;
    @try {
        NSArray *processed = ReadJSONArray(AIProcessedIDsPath());
        if ([processed containsObject:identifier]) return NO;
        NSMutableArray *items = [ReadJSONArray(AICandidatesPath()) mutableCopy];
        for (NSDictionary *item in items) {
            if ([item[@"id"] isEqualToString:identifier] || [item[@"sourceKey"] isEqualToString:sourceKey]) {
                return NO;
            }
        }
        [items addObject:@{
            @"id": identifier,
            @"sourceKey": sourceKey,
            @"sender": sender ?: @"",
            @"rowID": @(rowID),
            @"date": ISODate(date ?: NSDate.date),
            @"details": CleanWhitespace(text),
            @"queuedAt": ISODate(NSDate.date)
        }];
        [items sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSNumber *leftRow = [left[@"rowID"] isKindOfClass:NSNumber.class] ? left[@"rowID"] : @0;
            NSNumber *rightRow = [right[@"rowID"] isKindOfClass:NSNumber.class] ? right[@"rowID"] : @0;
            return [rightRow compare:leftRow];
        }];
        while (items.count > 100) [items removeLastObject];
        queued = WriteJSONArray(items, AICandidatesPath());
    } @finally {
        ReleaseDraftLock(descriptor);
    }
    if (queued) {
        AddLog(@"info", @"Queued SMS row %lld for OpenAI database recovery.", rowID);
    }
    return queued;
}

static NSString *NormalizedSender(NSString *value) {
    NSString *lower = value.lowercaseString ?: @"";
    NSMutableString *result = [NSMutableString string];
    NSCharacterSet *allowed = NSCharacterSet.alphanumericCharacterSet;
    for (NSUInteger index = 0; index < lower.length; index++) {
        unichar character = [lower characterAtIndex:index];
        if ([allowed characterIsMember:character]) [result appendFormat:@"%C", character];
    }
    return result;
}

static BOOL SenderApproved(NSDictionary *config, NSString *sender) {
    NSArray *approved = [config[@"approvedSenders"] isKindOfClass:NSArray.class]
        ? config[@"approvedSenders"] : @[@"Cb SMS"];
    NSString *candidate = NormalizedSender(sender);
    if (candidate.length == 0) return NO;
    for (NSString *item in approved) {
        NSString *needle = NormalizedSender(item);
        if (needle.length > 0 && ([candidate isEqualToString:needle] || [candidate containsString:needle] || [needle containsString:candidate])) {
            return YES;
        }
    }
    return NO;
}

static BOOL CardEndingApproved(NSDictionary *config, NSString *ending) {
    NSString *customEnding = [config[@"customEnding"] isKindOfClass:NSString.class]
        ? config[@"customEnding"] : @"";
    NSString *customAccountID = [config[@"customAccountID"] isKindOfClass:NSString.class]
        ? config[@"customAccountID"] : @"";
    if (customEnding.length > 0 && customAccountID.length > 0 && [customEnding isEqualToString:ending]) {
        return YES;
    }
    NSDictionary *mappings = [config[@"cardAccountIDs"] isKindOfClass:NSDictionary.class]
        ? config[@"cardAccountIDs"] : @{};
    if (mappings.count > 0) return mappings[ending] != nil;
    return [@[@"6760", @"0023"] containsObject:ending];
}

typedef NS_ENUM(NSInteger, DraftResult) {
    DraftResultCreated = 1,
    DraftResultAlreadyPending = 2,
    DraftResultAlreadyReviewed = 3,
    DraftResultFailed = 4
};

static DraftResult CreateDraft(NSDictionary *parsed, NSString *sourceKey, NSString *sender, sqlite3_int64 rowID) {
    NSString *identifier = DeterministicUUID(sourceKey).UUIDString;
    int descriptor = AcquireDraftLock();
    if (descriptor < 0) return DraftResultFailed;
    DraftResult result = DraftResultFailed;
    @try {
        NSArray *reviewed = ReadJSONArray(ReviewedIDsPath());
        if ([reviewed containsObject:identifier]) {
            result = DraftResultAlreadyReviewed;
            return result;
        }
        NSMutableArray *drafts = [ReadJSONArray(DraftsPath()) mutableCopy];
        for (NSDictionary *draft in drafts) {
            if ([draft[@"id"] isEqualToString:identifier]) {
                result = DraftResultAlreadyPending;
                return result;
            }
        }
        NSMutableDictionary *draft = [parsed mutableCopy];
        draft[@"id"] = identifier;
        draft[@"sourceKey"] = sourceKey;
        draft[@"sender"] = sender ?: @"";
        draft[@"rowID"] = @(rowID);
        draft[@"queuedAt"] = ISODate(NSDate.date);
        [drafts addObject:draft];
        [drafts sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSNumber *leftRow = [left[@"rowID"] isKindOfClass:NSNumber.class] ? left[@"rowID"] : @0;
            NSNumber *rightRow = [right[@"rowID"] isKindOfClass:NSNumber.class] ? right[@"rowID"] : @0;
            return [rightRow compare:leftRow];
        }];
        result = WriteJSONArray(drafts, DraftsPath()) ? DraftResultCreated : DraftResultFailed;
    } @finally {
        ReleaseDraftLock(descriptor);
    }
    if (result == DraftResultCreated) {
        AddLog(@"info", @"Created approval draft for %@ %@ %@ from **%@ (%@).",
            parsed[@"kind"], parsed[@"currency"], parsed[@"amount"], parsed[@"cardEnding"], sender ?: @"unknown sender");
    }
    return result;
}

__attribute__((unused)) __attribute__((unused)) static NSString *QueueEvent(NSDictionary *parsed, NSString *sourceKey, NSString *sender) {
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

        if ([kind isEqualToString:@"withdrawal"]) {
            NSString *destination = CashDestinationAccountID(config, ledger);
            if (!destination) {
                AddLog(@"warning", @"Waiting for Cash destination account mapping.");
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

__attribute__((unused)) __attribute__((unused)) static void RetryPending(NSDictionary *config) {
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


static BOOL AutomaticRecordDateIsLocked(NSString *isoDate) {
    NSString *container = ApplicationContainer();
    if (!container || isoDate.length == 0) return NO;
    NSString *preferencesPath = [container stringByAppendingPathComponent:
        @"Library/Preferences/com.nextsolution.dailyledger.plist"];
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:preferencesPath];
    if (![preferences[@"AccountingPeriodLockEnabled"] boolValue]) return NO;
    NSTimeInterval lockTimestamp = [preferences[@"AccountingPeriodLockThroughTimestamp"] doubleValue];
    if (lockTimestamp <= 0) return NO;

    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    NSDate *transactionDate = [formatter dateFromString:isoDate];
    if (!transactionDate) return NO;
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDate *lockDate = [NSDate dateWithTimeIntervalSince1970:lockTimestamp];
    NSDate *firstOpenDate = [calendar dateByAddingUnit:NSCalendarUnitDay value:1
                                                toDate:[calendar startOfDayForDate:lockDate]
                                               options:0];
    return [transactionDate compare:firstOpenDate] == NSOrderedAscending;
}

static BOOL CompleteDraftAfterAutomaticRecord(NSString *identifier) {
    int descriptor = AcquireDraftLock();
    if (descriptor < 0) return NO;
    BOOL success = NO;
    @try {
        NSMutableArray *drafts = [ReadJSONArray(DraftsPath()) mutableCopy];
        NSIndexSet *matches = [drafts indexesOfObjectsPassingTest:^BOOL(NSDictionary *draft, NSUInteger index, BOOL *stop) {
            return [draft[@"id"] isEqualToString:identifier];
        }];
        if (matches.count > 0) [drafts removeObjectsAtIndexes:matches];
        if (!WriteJSONArray(drafts, DraftsPath())) return NO;

        NSMutableArray *reviewed = [ReadJSONArray(ReviewedIDsPath()) mutableCopy];
        if (![reviewed containsObject:identifier]) [reviewed addObject:identifier];
        success = WriteJSONArray(reviewed, ReviewedIDsPath());
    } @finally {
        ReleaseDraftLock(descriptor);
    }
    return success;
}

static ImportResult AutoRecordParsedEvent(
    NSDictionary *parsed,
    NSString *sourceKey,
    NSString *sender,
    NSDictionary *config
) {
    if (![config[@"autoRecord"] boolValue]) return ImportResultWaitingForMapping;
    if ([parsed[@"kind"] isEqualToString:@"incomingTransfer"] ||
        [parsed[@"kind"] isEqualToString:@"cashDeposit"] ||
        [parsed[@"kind"] isEqualToString:@"reversal"]) {
        AddLog(@"info", @"%@ kept as draft for user review.", parsed[@"kind"]);
        return ImportResultWaitingForMapping;
    }
    if (AutomaticRecordDateIsLocked(parsed[@"date"])) {
        AddLog(@"warning", @"SMS transaction is inside the locked accounting period and remains a draft.");
        return ImportResultWaitingForMapping;
    }

    NSString *identifier = DeterministicUUID(sourceKey).UUIDString;
    if ([ReadJSONArray(ReviewedIDsPath()) containsObject:identifier]) {
        return ImportResultDuplicate;
    }
    NSString *eventPath = QueueEvent(parsed, sourceKey, sender);
    if (!eventPath) return ImportResultFailed;
    ImportResult result = ImportEvent(eventPath, config);
    if (result == ImportResultImported || result == ImportResultDuplicate) {
        FinishEvent(eventPath);
        CompleteDraftAfterAutomaticRecord(identifier);
        if (result == ImportResultImported) {
            gState[@"totalImported"] = @([gState[@"totalImported"] integerValue] + 1);
            gState[@"lastImportDate"] = ISODate(NSDate.date);
            AddLog(@"success", @"Auto recorded %@ %@ %@ from **%@.",
                parsed[@"kind"], parsed[@"currency"], parsed[@"amount"], parsed[@"cardEnding"]);
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                (__bridge CFStringRef)kDarwinChangeNotification,
                NULL, NULL, true
            );
        }
    }
    return result;
}

static void ApplyMaintenanceRequests(NSDictionary *config) {
    NSInteger requested = [config[@"clearLogsRequestID"] integerValue];
    NSInteger completed = [gState[@"lastClearLogsRequestID"] integerValue];
    if (requested == completed) return;
    gState[@"logs"] = [NSMutableArray array];
    gState[@"lastClearLogsRequestID"] = @(requested);
    SaveState();
    WriteConsole(@"Logs cleared.");
}

static NSInteger ConfiguredAutomaticScanHours(NSDictionary *config) {
    NSInteger hours = [config[@"automaticScanIntervalHours"] integerValue];
    if (hours < 1) hours = 6;
    return MIN(hours, 168);
}

__attribute__((unused)) static BOOL AutomaticScanIsDue(NSDictionary *config, NSDate *now) {
    NSTimeInterval last = [gState[@"lastAutomaticScanUnix"] doubleValue];
    if (last <= 0) return YES;
    NSTimeInterval interval = (NSTimeInterval)ConfiguredAutomaticScanHours(config) * 60.0 * 60.0;
    return now.timeIntervalSince1970 - last >= interval;
}

static void ScanMessages(BOOL forceRecent) {
    NSDictionary *config = LoadConfiguration();
    ApplyMaintenanceRequests(config);

    NSInteger requestID = [config[@"scanRequestID"] integerValue];
    NSInteger savedRequest = [gState[@"lastScanRequestID"] integerValue];
    BOOL manualRequested = forceRecent || requestID != savedRequest;
    NSDate *scanDate = NSDate.date;

    if (config[@"enabled"] && ![config[@"enabled"] boolValue] && !manualRequested) {
        WriteConsole(@"Automatic bank SMS detection is disabled in Next Ledger settings.");
        return;
    }

    if (manualRequested) {
        gState[@"lastScanRequestID"] = @(requestID);
        gState[@"manualScanClaimedAt"] = ISODate(scanDate);
        gState[@"scanInProgress"] = @YES;
        gState[@"scanProgressCurrent"] = @0;
        gState[@"scanProgressTotal"] = @15;
        gState[@"scanPhase"] = @"Manual scan claimed";
        SaveState();
    }

    // Capture-first mode: discovery is realtime; interval no longer gates sms.db reads.

    NSString *databasePath = SMSDatabasePath();
    if (![NSFileManager.defaultManager isReadableFileAtPath:databasePath]) {
        AddLog(@"error", @"Messages database is not readable at %@.", databasePath ?: @"unknown path");
        WriteConsole(@"Messages database is unavailable or unreadable.");
        if (manualRequested) {
            gState[@"scanInProgress"] = @NO;
            gState[@"scanProgressCurrent"] = @0;
            gState[@"scanProgressTotal"] = @15;
            gState[@"scanPhase"] = @"Manual scan failed · Messages database unreadable";
            SaveState();
            WriteConsole(@"Manual scan stopped because the Messages database is unreadable.");
        }
        return;
    }
    if (!AppSupportDirectory()) {
        AddLog(@"warning", @"Next Ledger app container was not found. Open Next Ledger once.");
        WriteConsole(@"Open Next Ledger once so its app container can be located.");
        if (manualRequested) { gState[@"scanInProgress"] = @NO; gState[@"scanProgressCurrent"] = @0; gState[@"scanProgressTotal"] = @15; gState[@"scanPhase"] = @"Manual scan failed"; SaveState(); WriteConsole(@"Manual scan failed and stopped."); }
        return;
    }

    sqlite3 *database = NULL;
    int openResult = sqlite3_open_v2(databasePath.fileSystemRepresentation, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, NULL);
    if (openResult != SQLITE_OK) {
        NSString *detail = database ? [NSString stringWithUTF8String:sqlite3_errmsg(database)] : @"unknown SQLite error";
        if (database) sqlite3_close(database);
        AddLog(@"error", @"Could not open sms.db read-only: %@.", detail);
        WriteConsole(@"Could not open Messages database.");
        if (manualRequested) { gState[@"scanInProgress"] = @NO; gState[@"scanProgressCurrent"] = @0; gState[@"scanProgressTotal"] = @15; gState[@"scanPhase"] = @"Manual scan failed"; SaveState(); WriteConsole(@"Manual scan failed and stopped."); }
        return;
    }
    sqlite3_busy_timeout(database, 2500);

    NSInteger newlyCapturedForReview = CaptureLatestApprovedMessagesForReview(database, config, 100);
    if (newlyCapturedForReview > 0) {
        WriteConsole([NSString stringWithFormat:@"Captured %ld new bank SMS for review before classification.", (long)newlyCapturedForReview]);
    }

    if (manualRequested) {
        gState[@"scanInProgress"] = @YES;
        gState[@"scanProgressCurrent"] = @0;
        gState[@"scanProgressTotal"] = @15;
        gState[@"scanPhase"] = @"Collecting latest 15 incoming messages";
        WriteConsole(@"Manual review scan started. Collecting the latest 15 incoming messages…");

        NSInteger collected = CollectLatestIncomingMessagesForReview(database, 15);
        sqlite3_close(database);

        gState[@"lastScanRequestID"] = @(requestID);
        gState[@"lastScanDate"] = ISODate(NSDate.date);
        gState[@"scanInProgress"] = @NO;
        gState[@"scanProgressCurrent"] = @(collected);
        gState[@"scanProgressTotal"] = @15;
        gState[@"scanPhase"] = collected > 0 ? @"Completed · Ready for review" : @"Completed · No readable messages";
        SaveState();

        NSString *result = [NSString stringWithFormat:@"Manual scan finished. %ld of the latest 15 incoming messages are ready for review.", (long)collected];
        WriteConsole(result);
        return;
    }
    sqlite3_int64 maximum = MaximumRowID(database);

    NSInteger approvedMessageLimit = manualRequested ? 15 : 50;
    NSInteger databaseRowLimit = manualRequested ? 15 : 500;
    const char *query =
        "SELECT m.ROWID, COALESCE(m.guid, ''), m.text, m.attributedBody, m.date, COALESCE(h.id, '') "
        "FROM message m LEFT JOIN handle h ON m.handle_id = h.ROWID "
        "WHERE m.is_from_me = 0 AND (m.text IS NOT NULL OR m.attributedBody IS NOT NULL) "
        "ORDER BY m.ROWID DESC LIMIT ?";
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, query, -1, &statement, NULL) != SQLITE_OK) {
        NSString *detail = [NSString stringWithUTF8String:sqlite3_errmsg(database)];
        sqlite3_close(database);
        AddLog(@"error", @"sms.db query preparation failed: %@.", detail);
        WriteConsole(@"Messages database schema was not recognized.");
        return;
    }
    sqlite3_bind_int(statement, 1, (int)databaseRowLimit);

    NSInteger databaseRowsRead = 0;
    NSInteger approvedMessagesChecked = 0;
    NSInteger matched = 0;
    NSInteger draftsCreated = 0;
    NSInteger autoRecorded = 0;
    NSInteger alreadyHandled = 0;
    NSInteger ignoredSender = 0;
    NSInteger ignoredCard = 0;
    NSInteger parseFailures = 0;
    NSInteger reviewFallbacks = 0;
    NSInteger blankBodies = 0;
    NSInteger draftFailures = 0;

    if (manualRequested) {
        gState[@"scanInProgress"] = @YES;
        gState[@"scanProgressCurrent"] = @0;
        gState[@"scanProgressTotal"] = @(databaseRowLimit);
        gState[@"scanPhase"] = @"Starting latest-15 SMS scan";
        WriteConsole(@"Manual scan started. Reading the latest 15 incoming messages…");
    }

    while (sqlite3_step(statement) == SQLITE_ROW) {
        databaseRowsRead += 1;
        if (manualRequested) {
            gState[@"scanProgressCurrent"] = @(MIN(databaseRowsRead, databaseRowLimit));
            gState[@"scanPhase"] = [NSString stringWithFormat:@"Scanning message %ld of %ld", (long)MIN(databaseRowsRead, databaseRowLimit), (long)databaseRowLimit];
            WriteConsole(@"Manual scan in progress…");
        }
        sqlite3_int64 rowID = sqlite3_column_int64(statement, 0);
        const unsigned char *senderBytes = sqlite3_column_text(statement, 5);
        NSString *sender = senderBytes ? [NSString stringWithUTF8String:(const char *)senderBytes] : @"";
        if (!SenderApproved(config, sender)) {
            ignoredSender += 1;
            continue;
        }

        if (approvedMessagesChecked >= approvedMessageLimit) break;
        approvedMessagesChecked += 1;

        NSString *text = MessageText(statement);
        if (text.length == 0) {
            blankBodies += 1;
            AddLog(@"warning", @"Approved-bank SMS row %lld had no readable message body.", rowID);
            continue;
        }

        NSDictionary *parsed = ParseTransaction(text, DatabaseDate(sqlite3_column_int64(statement, 4)));
        BOOL reviewFallback = NO;
        if (!parsed) {
            parsed = ReviewDraftForUnrecognizedBankSMS(
                text, DatabaseDate(sqlite3_column_int64(statement, 4))
            );
            if (!parsed) {
                parseFailures += 1;
                const unsigned char *guidBytesForAI = sqlite3_column_text(statement, 1);
                NSString *guidForAI = guidBytesForAI ? [NSString stringWithUTF8String:(const char *)guidBytesForAI] : @"";
                NSString *sourceForAI = guidForAI.length ? guidForAI : [NSString stringWithFormat:@"%lld|%@", rowID, text];
                QueueAICandidate(text, sourceForAI, sender, rowID, DatabaseDate(sqlite3_column_int64(statement, 4)));
                NSString *preview = text.length > 160 ? [[text substringToIndex:160] stringByAppendingString:@"…"] : text;
                AddLog(@"warning", @"Approved-bank SMS row %lld was not classified locally; queued for OpenAI recovery: %@", rowID, preview);
                continue;
            }
            reviewFallback = YES;
            reviewFallbacks += 1;
            const unsigned char *guidBytesForAI = sqlite3_column_text(statement, 1);
            NSString *guidForAI = guidBytesForAI ? [NSString stringWithUTF8String:(const char *)guidBytesForAI] : @"";
            NSString *sourceForAI = guidForAI.length ? guidForAI : [NSString stringWithFormat:@"%lld|%@", rowID, text];
            QueueAICandidate(text, sourceForAI, sender, rowID, DatabaseDate(sqlite3_column_int64(statement, 4)));
            AddLog(@"info", @"SMS row %lld could not be classified confidently; created a manual-review candidate (%@) and queued OpenAI enrichment.", rowID, parsed[@"kind"]);
        }
        BOOL requiresMappedEnding = !reviewFallback && ![parsed[@"kind"] isEqualToString:@"incomingTransfer"];
        if (requiresMappedEnding && !CardEndingApproved(config, parsed[@"cardEnding"])) {
            ignoredCard += 1;
            AddLog(@"warning", @"SMS row %lld matched a transaction, but card **%@ is not mapped/approved.", rowID, parsed[@"cardEnding"] ?: @"unknown");
            continue;
        }

        matched += 1;
        const unsigned char *guidBytes = sqlite3_column_text(statement, 1);
        NSString *guid = guidBytes ? [NSString stringWithUTF8String:(const char *)guidBytes] : @"";
        NSString *sourceKey = guid.length ? guid : [NSString stringWithFormat:@"%lld|%@", rowID, text];
        DraftResult result = CreateDraft(parsed, sourceKey, sender, rowID);
        if (result == DraftResultAlreadyReviewed) {
            alreadyHandled += 1;
        } else if (result == DraftResultCreated || result == DraftResultAlreadyPending) {
            ImportResult automaticResult = reviewFallback ? ImportResultWaitingForMapping : AutoRecordParsedEvent(parsed, sourceKey, sender, config);
            if (automaticResult == ImportResultImported) {
                autoRecorded += 1;
            } else if (automaticResult == ImportResultDuplicate && [config[@"autoRecord"] boolValue]) {
                alreadyHandled += 1;
            } else if (result == DraftResultCreated) {
                draftsCreated += 1;
            } else {
                alreadyHandled += 1;
            }
        } else {
            draftFailures += 1;
            AddLog(@"error", @"Could not save approval draft for SMS row %lld. It will be retried on the next scan.", rowID);
        }
    }
    sqlite3_finalize(statement);
    sqlite3_close(database);

    gState[@"lastRowID"] = @(maximum);
    gState[@"lastScanRequestID"] = @(requestID);
    gState[@"lastScanDate"] = ISODate(scanDate);
    gState[@"lastAutomaticScanUnix"] = @(scanDate.timeIntervalSince1970);
    gState[@"automaticScanIntervalHours"] = @(ConfiguredAutomaticScanHours(config));
    if (manualRequested) {
        gState[@"scanInProgress"] = @NO;
        gState[@"scanProgressCurrent"] = @(databaseRowLimit);
        gState[@"scanProgressTotal"] = @(databaseRowLimit);
        gState[@"scanPhase"] = @"Completed";
    }
    if (parseFailures > 0) {
        gState[@"totalParseFailures"] = @([gState[@"totalParseFailures"] integerValue] + parseFailures);
    }
    SaveState();

    NSString *mode = manualRequested ? @"Manual recovery scan" : @"Realtime capture/parser scan";
    NSString *result = [NSString stringWithFormat:
        @"%@: read %ld rows; checked %ld bank SMS; matched %ld; auto recorded %ld; created %ld drafts; handled %ld; ignored sender %ld; ignored card %ld; unreadable %ld; review fallback %ld; parse failures %ld; draft failures %ld. Next scan in %ld hour%@.",
        mode,
        (long)databaseRowsRead,
        (long)approvedMessagesChecked,
        (long)matched,
        (long)autoRecorded,
        (long)draftsCreated,
        (long)alreadyHandled,
        (long)ignoredSender,
        (long)ignoredCard,
        (long)blankBodies,
        (long)reviewFallbacks,
        (long)parseFailures,
        (long)draftFailures,
        (long)ConfiguredAutomaticScanHours(config),
        ConfiguredAutomaticScanHours(config) == 1 ? @"" : @"s"];
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
            @"name": @"ATM cash deposit",
            @"sms": @"Current Acc xxx364001 credited with QAR 14,000.00 for ATM Cash Deposit at 13:27, 09-Aug-26 Current Acc Bal: QAR 15,332.55",
            @"kind": @"cashDeposit", @"ending": @"364001", @"amount": @"14000"
        },
        @{
            @"name": @"CB card purchase exact format",
            @"sms": @"Your card ending **6760 used for QAR 8.73 at MFT*badrgo W.L.L Doh at 15:31 09-Aug-26 Available Limit: QAR 105.60",
            @"kind": @"expense", @"ending": @"6760", @"amount": @"8.73"
        },
        @{
            @"name": @"CB reversal refund",
            @"sms": @"Reversal of transaction on your card ending **6760 at MFT*badrgo W.L.L Doh for QAR 8.73 at 15:35, 09-Aug-26 Available Limit: 114.33",
            @"kind": @"reversal", @"ending": @"6760", @"amount": @"8.73"
        },
        @{
            @"name": @"incoming Fawran transfer",
            @"sms": @"Current Acc xxx364001 credited with QAR 1,000.00 for Fawran instant payment ref zeeshan,MOHAMED ASHFAAQ MOHAMED AZW withM-33510982 at 16:09, 03-Aug-26 Current Acc Bal: QAR 2,596.69",
            @"kind": @"incomingTransfer", @"ending": @"364001", @"amount": @"1000"
        },
        @{
            @"name": @"unrecognized transfer review fallback",
            @"sms": @"Transfer notification QAR 825.50 sent to beneficiary TEST PERSON reference X992 at 18:42, 07-Aug-26 account balance QAR 1,900.00",
            @"kind": @"reviewTransfer", @"ending": @"", @"amount": @"825.50", @"reviewFallback": @YES
        },
        @{
            @"name": @"current account card payment transfer",
            @"sms": @"CUR1 a/c debit\nQAR 200.00\nfor Card Payment\nat 19:48, 07-Aug-26\nCUR1 Balance: QAR 1,358.55\nCard Available Balance: QAR -3,495.91",
            @"kind": @"reviewTransfer", @"ending": @"CUR1", @"amount": @"200", @"reviewFallback": @YES
        }
    ];
    NSMutableArray *results = [NSMutableArray array];
    BOOL passed = YES;
    const unsigned char syntheticAttributedBody[] =
        "streamtyped\0NSAttributedString\0NSString\0CUR1 a/c debit\0QAR 350.00\0for Card Payment\0at 20:01, 07-Aug-26\0CUR1 Balance: QAR 1,208.55\0Card Available Balance: QAR -3,345.91\0";
    NSString *recoveredBody = TextFromAttributedBody(
        syntheticAttributedBody,
        (int)sizeof(syntheticAttributedBody) - 1
    );
    NSDictionary *recoveredParsed = recoveredBody.length
        ? ReviewDraftForUnrecognizedBankSMS(recoveredBody, NSDate.date)
        : nil;
    BOOL bodyRecoveryPassed = recoveredParsed &&
        [recoveredParsed[@"kind"] isEqualToString:@"reviewTransfer"] &&
        [recoveredParsed[@"cardEnding"] isEqualToString:@"CUR1"] &&
        [recoveredParsed[@"amount"] compare:[NSDecimalNumber decimalNumberWithString:@"350"]] == NSOrderedSame;
    passed = passed && bodyRecoveryPassed;
    [results addObject:@{
        @"name": @"attributed-body CUR1 recovery",
        @"passed": @(bodyRecoveryPassed),
        @"parsed": recoveredParsed ?: @{}
    }];

    for (NSDictionary *test in tests) {
        NSDictionary *parsed = ParseTransaction(test[@"sms"], NSDate.date);
        if (!parsed && [test[@"reviewFallback"] boolValue]) {
            parsed = ReviewDraftForUnrecognizedBankSMS(test[@"sms"], NSDate.date);
        }
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
        if ([gState[@"scanInProgress"] boolValue]) {
            gState[@"scanInProgress"] = @NO;
            gState[@"scanPhase"] = @"Previous scan interrupted — tap Manual Scan to retry";
            gState[@"lastAutomaticScanUnix"] = @(NSDate.date.timeIntervalSince1970);
            SaveState();
        }
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
            sleep(5);
        }
    }
    return 0;
}
