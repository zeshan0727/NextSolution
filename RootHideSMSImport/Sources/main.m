#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <sqlite3.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

static NSString *const kBundleIdentifier = @"com.nextsolution.dailyledger";
static NSString *const kChangeNotification = @"com.nextsolution.dailyledger.external-change";

static NSString *MobilePath(NSString *relativePath) {
    NSString *rootHidePath = [@"/rootfs" stringByAppendingString:relativePath];
    NSString *rootHideParent = [rootHidePath stringByDeletingLastPathComponent];
    if ([[NSFileManager defaultManager] fileExistsAtPath:rootHideParent]) {
        return rootHidePath;
    }
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
    if ([attributes fileSize] > 262144) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
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
    if (!match || group >= match.numberOfRanges || [match rangeAtIndex:group].location == NSNotFound) {
        return nil;
    }
    return [text substringWithRange:[match rangeAtIndex:group]];
}

static NSString *CleanWhitespace(NSString *value) {
    NSArray<NSString *> *parts = [value componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) [clean addObject:part];
    }
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
    NSDate *date = TransactionDate(text, fallbackDate ?: [NSDate date]);
    return @{
        @"type": income && !expense ? @"income" : @"expense",
        @"amount": amount,
        @"vendor": vendor,
        @"date": date,
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
            [vendor rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return category;
        }
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
        NSArray<NSString *> *containers = [manager contentsOfDirectoryAtPath:base error:nil];
        for (NSString *container in containers) {
            NSString *root = [base stringByAppendingPathComponent:container];
            NSString *metadataPath = [root stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
            NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
            NSString *identifier = metadata[@"MCMMetadataIdentifier"];
            if (![identifier isKindOfClass:[NSString class]] || ![identifier isEqualToString:kBundleIdentifier]) continue;
            return [root stringByAppendingPathComponent:@"Library/Application Support/DailyLedger/ledger.json"];
        }
    }
    return nil;
}

static NSMutableDictionary *NewLedger(void) {
    NSMutableArray *rules = [NSMutableArray array];
    for (NSDictionary *item in DefaultRules()) {
        [rules addObject:@{
            @"id": [NSUUID UUID].UUIDString,
            @"keyword": item[@"keyword"],
            @"category": item[@"category"]
        }];
    }
    return [@{
        @"version": @2,
        @"transactions": [NSMutableArray array],
        @"settings": [@{
            @"currencyCode": @"QAR",
            @"vendorRules": rules,
            @"smsAutoImportEnabled": @YES
        } mutableCopy]
    } mutableCopy];
}

static BOOL AppendTransaction(NSString *ledgerPath, NSDictionary *parsed, NSString *sourceKey) {
    NSString *directory = [ledgerPath stringByDeletingLastPathComponent];
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]) return NO;
    NSString *lockPath = [directory stringByAppendingPathComponent:@"ledger.lock"];
    int descriptor = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR);
    if (descriptor < 0) return NO;
    if (flock(descriptor, LOCK_EX) != 0) {
        close(descriptor);
        return NO;
    }

    BOOL success = NO;
    @try {
        NSData *existingData = [NSData dataWithContentsOfFile:ledgerPath];
        NSMutableDictionary *ledger = existingData
            ? [NSJSONSerialization JSONObjectWithData:existingData options:NSJSONReadingMutableContainers error:nil]
            : NewLedger();
        if (![ledger isKindOfClass:[NSMutableDictionary class]]) ledger = NewLedger();

        NSMutableDictionary *settings = ledger[@"settings"];
        if (![settings isKindOfClass:[NSMutableDictionary class]]) {
            settings = [NewLedger()[@"settings"] mutableCopy];
            ledger[@"settings"] = settings;
        }
        if (settings[@"smsAutoImportEnabled"] && ![settings[@"smsAutoImportEnabled"] boolValue]) {
            success = YES;
            @throw [NSException exceptionWithName:@"DailyLedgerImportDisabled" reason:nil userInfo:nil];
        }

        NSMutableArray *transactions = ledger[@"transactions"];
        if (![transactions isKindOfClass:[NSMutableArray class]]) {
            transactions = [NSMutableArray array];
            ledger[@"transactions"] = transactions;
        }
        NSString *identifier = DeterministicUUID(sourceKey).UUIDString;
        for (NSDictionary *item in transactions) {
            if ([item[@"id"] isEqualToString:identifier]) {
                success = YES;
                @throw [NSException exceptionWithName:@"DailyLedgerDuplicate" reason:nil userInfo:nil];
            }
        }

        NSString *category = CategoryForVendor(parsed[@"vendor"], settings[@"vendorRules"]);
        NSString *now = ISODate([NSDate date]);
        [transactions addObject:@{
            @"id": identifier,
            @"type": parsed[@"type"],
            @"amount": parsed[@"amount"],
            @"date": ISODate(parsed[@"date"]),
            @"category": category,
            @"vendor": parsed[@"vendor"],
            @"details": parsed[@"details"],
            @"createdAt": now
        }];
        ledger[@"version"] = @2;

        NSData *output = [NSJSONSerialization dataWithJSONObject:ledger
                                                         options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                           error:nil];
        success = output && [output writeToFile:ledgerPath options:NSDataWritingAtomic error:nil];
        if (success) {
            [manager setAttributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}
                      ofItemAtPath:ledgerPath
                             error:nil];
            Log(@"Recorded %@ %@ as %@ (%@)", parsed[@"type"], parsed[@"amount"], parsed[@"vendor"], category);
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                (__bridge CFStringRef)kChangeNotification,
                NULL,
                NULL,
                true
            );
        }
    } @catch (NSException *exception) {
        if (![exception.name hasPrefix:@"DailyLedger"]) {
            Log(@"Ledger write exception: %@", exception.reason ?: exception.name);
            success = NO;
        }
    } @finally {
        flock(descriptor, LOCK_UN);
        close(descriptor);
    }
    return success;
}

static NSString *SMSDatabasePath(void) {
    NSArray *paths = @[
        @"/rootfs/var/mobile/Library/SMS/sms.db",
        @"/var/mobile/Library/SMS/sms.db"
    ];
    for (NSString *path in paths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    }
    return nil;
}

static sqlite3_int64 MaximumRowID(sqlite3 *database) {
    sqlite3_stmt *statement = NULL;
    sqlite3_int64 value = 0;
    if (sqlite3_prepare_v2(database, "SELECT COALESCE(MAX(ROWID), 0) FROM message", -1, &statement, NULL) == SQLITE_OK &&
        sqlite3_step(statement) == SQLITE_ROW) {
        value = sqlite3_column_int64(statement, 0);
    }
    sqlite3_finalize(statement);
    return value;
}

static NSString *StatePath(void) {
    return [StateDirectory() stringByAppendingPathComponent:@"state.plist"];
}

static NSNumber *SavedRowID(void) {
    NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:StatePath()];
    return state[@"lastRowID"];
}

static void SaveRowID(sqlite3_int64 rowID) {
    [[NSFileManager defaultManager] createDirectoryAtPath:StateDirectory()
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [@{@"lastRowID": @(rowID)} writeToFile:StatePath() atomically:YES];
}

static void ProcessMessages(void) {
    NSString *ledgerPath = LedgerFilePath();
    NSString *databasePath = SMSDatabasePath();
    if (!ledgerPath || !databasePath) return;

    sqlite3 *database = NULL;
    if (sqlite3_open_v2(databasePath.fileSystemRepresentation, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
        if (database) sqlite3_close(database);
        return;
    }
    sqlite3_busy_timeout(database, 2500);

    NSNumber *saved = SavedRowID();
    if (!saved) {
        sqlite3_int64 current = MaximumRowID(database);
        SaveRowID(current);
        Log(@"Ready. New incoming transaction messages after row %lld will be imported.", current);
        sqlite3_close(database);
        return;
    }

    sqlite3_int64 lastRowID = saved.longLongValue;
    sqlite3_int64 processedRowID = lastRowID;
    const char *query =
        "SELECT m.ROWID, COALESCE(m.guid, ''), m.text, m.date "
        "FROM message m "
        "WHERE m.ROWID > ? AND m.is_from_me = 0 AND m.text IS NOT NULL "
        "ORDER BY m.ROWID ASC";
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, query, -1, &statement, NULL) != SQLITE_OK) {
        sqlite3_close(database);
        return;
    }
    sqlite3_bind_int64(statement, 1, lastRowID);

    while (sqlite3_step(statement) == SQLITE_ROW) {
        sqlite3_int64 rowID = sqlite3_column_int64(statement, 0);
        const unsigned char *guidBytes = sqlite3_column_text(statement, 1);
        const unsigned char *textBytes = sqlite3_column_text(statement, 2);
        sqlite3_int64 rawDate = sqlite3_column_int64(statement, 3);
        NSString *guid = guidBytes ? [NSString stringWithUTF8String:(const char *)guidBytes] : @"";
        NSString *text = textBytes ? [NSString stringWithUTF8String:(const char *)textBytes] : nil;
        if (!text) {
            processedRowID = rowID;
            continue;
        }

        NSDictionary *parsed = ParseTransaction(text, DatabaseDate(rawDate));
        if (!parsed) {
            processedRowID = rowID;
            continue;
        }
        NSString *source = guid.length > 0 ? guid : [NSString stringWithFormat:@"%lld|%lld|%@", rowID, rawDate, text];
        if (!AppendTransaction(ledgerPath, parsed, source)) {
            Log(@"Could not store SMS row %lld; it will be retried.", rowID);
            break;
        }
        processedRowID = rowID;
    }
    sqlite3_finalize(statement);
    sqlite3_close(database);
    if (processedRowID != lastRowID) SaveRowID(processedRowID);
}

static int RunSelfTest(void) {
    NSString *sample = @"Your card ending **0023\nused for QAR 20.00\nat NEW NASCO RESTAURANT\nat 14:03\n07-May-26\nAvailable Limit: QAR 107.01";
    NSDictionary *parsed = ParseTransaction(sample, [NSDate dateWithTimeIntervalSince1970:0]);
    NSString *category = CategoryForVendor(parsed[@"vendor"], DefaultRules());
    BOOL passed = parsed && [parsed[@"amount"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"20.00"]] &&
        [parsed[@"vendor"] isEqualToString:@"NEW NASCO RESTAURANT"] && [category isEqualToString:@"Restaurant"];
    NSDictionary *result = parsed ? @{
        @"passed": @(passed),
        @"amount": parsed[@"amount"],
        @"vendor": parsed[@"vendor"],
        @"category": category,
        @"type": parsed[@"type"],
        @"date": ISODate(parsed[@"date"])
    } : @{@"passed": @NO};
    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    fprintf(stdout, "%s\n", [[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] UTF8String]);
    return passed ? 0 : 1;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--self-test") == 0) return RunSelfTest();
        Log(@"Daily Ledger SMS Import started.");
        while (true) {
            @autoreleasepool {
                ProcessMessages();
            }
            sleep(10);
        }
    }
    return 0;
}
