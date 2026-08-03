from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:220]!r}")
    write(path, text.replace(old, new, 1))


def regex_replace_once(path: str, pattern: str, replacement: str) -> None:
    text = read(path)
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"Expected one regex match in {path}, found {count}: {pattern[:220]!r}")
    write(path, updated)


source = "RootHideSMSQueue/Sources/main.m"
replace_once(
    source,
    'static NSString *const kDaemonVersion = @"2.1.1";',
    'static NSString *const kDaemonVersion = @"2.1.2";',
)

replace_once(
    source,
    '''        @"approvedSenders": @[@"Cb SMS"],
        @"scanRequestID": @0
''',
    '''        @"approvedSenders": @[@"Cb SMS"],
        @"automaticScanIntervalHours": @6,
        @"scanRequestID": @0
''',
)

scan_implementation = r'''static NSInteger ConfiguredAutomaticScanHours(NSDictionary *config) {
    NSInteger hours = [config[@"automaticScanIntervalHours"] integerValue];
    if (hours < 1) hours = 6;
    return MIN(hours, 168);
}

static BOOL AutomaticScanIsDue(NSDictionary *config, NSDate *now) {
    NSTimeInterval last = [gState[@"lastAutomaticScanUnix"] doubleValue];
    if (last <= 0) return YES;
    NSTimeInterval interval = (NSTimeInterval)ConfiguredAutomaticScanHours(config) * 60.0 * 60.0;
    return now.timeIntervalSince1970 - last >= interval;
}

static void ScanMessages(BOOL forceRecent) {
    NSDictionary *config = LoadConfiguration();
    if (config[@"enabled"] && ![config[@"enabled"] boolValue]) {
        WriteConsole(@"Automatic bank SMS detection is disabled in Next Ledger settings.");
        return;
    }

    NSInteger requestID = [config[@"scanRequestID"] integerValue];
    NSInteger savedRequest = [gState[@"lastScanRequestID"] integerValue];
    BOOL manualRequested = forceRecent || requestID != savedRequest;
    NSDate *scanDate = NSDate.date;

    if (!manualRequested && !AutomaticScanIsDue(config, scanDate)) {
        WriteConsole(nil);
        return;
    }

    NSString *databasePath = SMSDatabasePath();
    if (![NSFileManager.defaultManager isReadableFileAtPath:databasePath]) {
        AddLog(@"error", @"Messages database is not readable at %@.", databasePath ?: @"unknown path");
        WriteConsole(@"Messages database is unavailable or unreadable.");
        return;
    }
    if (!AppSupportDirectory()) {
        AddLog(@"warning", @"Next Ledger app container was not found. Open Next Ledger once.");
        WriteConsole(@"Open Next Ledger once so its app container can be located.");
        return;
    }

    sqlite3 *database = NULL;
    int openResult = sqlite3_open_v2(databasePath.fileSystemRepresentation, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, NULL);
    if (openResult != SQLITE_OK) {
        NSString *detail = database ? [NSString stringWithUTF8String:sqlite3_errmsg(database)] : @"unknown SQLite error";
        if (database) sqlite3_close(database);
        AddLog(@"error", @"Could not open sms.db read-only: %@.", detail);
        WriteConsole(@"Could not open Messages database.");
        return;
    }
    sqlite3_busy_timeout(database, 2500);
    sqlite3_int64 maximum = MaximumRowID(database);

    NSInteger approvedMessageLimit = manualRequested ? 250 : 10;
    NSInteger databaseRowLimit = manualRequested ? 2000 : 250;
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
    NSInteger alreadyHandled = 0;
    NSInteger ignoredSender = 0;
    NSInteger ignoredCard = 0;
    NSInteger parseFailures = 0;
    NSInteger blankBodies = 0;
    NSInteger draftFailures = 0;

    while (sqlite3_step(statement) == SQLITE_ROW) {
        databaseRowsRead += 1;
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
        if (!parsed) {
            parseFailures += 1;
            NSString *preview = text.length > 160 ? [[text substringToIndex:160] stringByAppendingString:@"…"] : text;
            AddLog(@"warning", @"Approved-bank SMS row %lld was not classified: %@", rowID, preview);
            continue;
        }
        if (!CardEndingApproved(config, parsed[@"cardEnding"])) {
            ignoredCard += 1;
            AddLog(@"warning", @"SMS row %lld matched a transaction, but card **%@ is not mapped/approved.", rowID, parsed[@"cardEnding"] ?: @"unknown");
            continue;
        }

        matched += 1;
        const unsigned char *guidBytes = sqlite3_column_text(statement, 1);
        NSString *guid = guidBytes ? [NSString stringWithUTF8String:(const char *)guidBytes] : @"";
        NSString *sourceKey = guid.length ? guid : [NSString stringWithFormat:@"%lld|%@", rowID, text];
        DraftResult result = CreateDraft(parsed, sourceKey, sender, rowID);
        if (result == DraftResultCreated) draftsCreated += 1;
        else if (result == DraftResultAlreadyPending || result == DraftResultAlreadyReviewed) alreadyHandled += 1;
        else {
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
    if (parseFailures > 0) {
        gState[@"totalParseFailures"] = @([gState[@"totalParseFailures"] integerValue] + parseFailures);
    }
    SaveState();

    NSString *mode = manualRequested ? @"Manual recovery scan" : @"Automatic latest-10 scan";
    NSString *result = [NSString stringWithFormat:
        @"%@: read %ld database rows; checked %ld approved-bank SMS; matched %ld transactions; created %ld drafts; already handled %ld; ignored sender %ld; ignored card %ld; unreadable bodies %ld; parse failures %ld; draft failures %ld. Next automatic scan in %ld hour%@.",
        mode,
        (long)databaseRowsRead,
        (long)approvedMessagesChecked,
        (long)matched,
        (long)draftsCreated,
        (long)alreadyHandled,
        (long)ignoredSender,
        (long)ignoredCard,
        (long)blankBodies,
        (long)parseFailures,
        (long)draftFailures,
        (long)ConfiguredAutomaticScanHours(config),
        ConfiguredAutomaticScanHours(config) == 1 ? @"" : @"s"];
    AddLog(@"info", @"%@", result);
    WriteConsole(result);
}

static int RunSelfTest'''

regex_replace_once(
    source,
    r'static void ScanMessages\(BOOL forceRecent\) \{.*?\n\}\n\nstatic int RunSelfTest',
    scan_implementation,
)

replace_once(source, '            sleep(3);', '            sleep(30);')

service = "DailyLedger/Services/SMSImportConsoleService.swift"
replace_once(
    service,
    '''    var approvedSenders: [String] = ["Cb SMS"]
    var scanRequestID = 0
''',
    '''    var approvedSenders: [String] = ["Cb SMS"]
    var automaticScanIntervalHours = 6
    var scanRequestID = 0
''',
)
replace_once(
    service,
    '''        case approvedSenders
        case scanRequestID
''',
    '''        case approvedSenders
        case automaticScanIntervalHours
        case scanRequestID
''',
)
replace_once(
    service,
    '''        approvedSenders = try container.decodeIfPresent([String].self, forKey: .approvedSenders) ?? ["Cb SMS"]
        scanRequestID = try container.decodeIfPresent(Int.self, forKey: .scanRequestID) ?? 0
''',
    '''        approvedSenders = try container.decodeIfPresent([String].self, forKey: .approvedSenders) ?? ["Cb SMS"]
        automaticScanIntervalHours = min(max(try container.decodeIfPresent(Int.self, forKey: .automaticScanIntervalHours) ?? 6, 1), 168)
        scanRequestID = try container.decodeIfPresent(Int.self, forKey: .scanRequestID) ?? 0
''',
)

view = "DailyLedger/Views/SMSImportConsoleView.swift"
replace_once(
    view,
    '''                TextField("Approved senders, comma separated", text: $approvedSendersText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                NavigationLink {
''',
    '''                TextField("Approved senders, comma separated", text: $approvedSendersText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Stepper(value: $configuration.automaticScanIntervalHours, in: 1...168) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Automatic Scan Interval")
                        Text("Every \\(configuration.automaticScanIntervalHours) hour\\(configuration.automaticScanIntervalHours == 1 ? \"\" : \"s\")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Automatic scans recheck only the latest 10 approved-bank SMS. Manual recovery scans search up to 250 approved-bank SMS and reset the automatic timer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                NavigationLink {
''',
)
replace_once(
    view,
    '''        if configuration.approvedSenders.isEmpty { configuration.approvedSenders = ["Cb SMS"] }
        if requestScan { configuration.scanRequestID += 1 }
''',
    '''        if configuration.approvedSenders.isEmpty { configuration.approvedSenders = ["Cb SMS"] }
        configuration.automaticScanIntervalHours = min(max(configuration.automaticScanIntervalHours, 1), 168)
        if requestScan { configuration.scanRequestID += 1 }
''',
)

for path in ["RootHideSMSQueue/control"]:
    replace_once(path, "Version: 2.1.1", "Version: 2.1.2")
for path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    replace_once(path, "Next Ledger SMS Daemon 2.1.1 installation started", "Next Ledger SMS Daemon 2.1.2 installation started")

print("Added latest-10 recovery scans, a six-hour default interval, custom interval settings, and cursor-independent missed-SMS recovery.")
