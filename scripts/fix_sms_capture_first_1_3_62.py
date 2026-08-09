from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")

def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    if text.count(old) != 1:
        raise RuntimeError(f"Expected one match in {path}: {old[:180]!r}; got {text.count(old)}")
    write(path, text.replace(old, new, 1))

# Release versions.
replace_once("project.yml", 'MARKETING_VERSION: "1.3.61"', 'MARKETING_VERSION: "1.3.62"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "69"', 'CURRENT_PROJECT_VERSION: "70"')

source = "RootHideSMSQueue/Sources/main.m"
replace_once(source, 'static NSString *const kDaemonVersion = @"2.2.2";', 'static NSString *const kDaemonVersion = @"2.2.3";')
replace_once("RootHideSMSQueue/control", "Version: 2.2.2", "Version: 2.2.3")
for path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    text = read(path)
    text = text.replace("Next Ledger SMS Daemon 2.2.2 installation started", "Next Ledger SMS Daemon 2.2.3 installation started")
    write(path, text)

# ---------------------------------------------------------------------------
# Capture-first inbox. Every recent SMS from an approved bank sender is merged
# into the persistent review JSON before the local parser decides what it is.
# This is deliberately independent of parse success and ledger auto-recording.
# ---------------------------------------------------------------------------
text = read(source)
anchor = 'static sqlite3_int64 MaximumRowID(sqlite3 *database) {'
if anchor not in text:
    raise RuntimeError("MaximumRowID anchor not found")
helper = r'''static BOOL SenderMatchesCaptureList(NSDictionary *config, NSString *sender) {
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

'''
text = text.replace(anchor, helper + anchor, 1)
write(source, text)

# Do not let the 1-168 hour recovery interval gate discovery of new bank SMS.
text = read(source)
gate = '''    if (!manualRequested && !AutomaticScanIsDue(config, scanDate)) {
        WriteConsole(nil);
        return;
    }
'''
if text.count(gate) != 1:
    raise RuntimeError(f"AutomaticScanIsDue gate count {text.count(gate)}")
text = text.replace(gate, '''    // Capture-first mode: discovery is realtime; interval no longer gates sms.db reads.
''', 1)

# Capture into review inbox immediately after opening sms.db, before manual/local parsing.
open_anchor = '    sqlite3_busy_timeout(database, 2500);\n'
if text.count(open_anchor) != 1:
    raise RuntimeError(f"busy timeout anchor count {text.count(open_anchor)}")
text = text.replace(open_anchor, open_anchor + '''
    NSInteger newlyCapturedForReview = CaptureLatestApprovedMessagesForReview(database, config, 100);
    if (newlyCapturedForReview > 0) {
        WriteConsole([NSString stringWithFormat:@"Captured %ld new bank SMS for review before classification.", (long)newlyCapturedForReview]);
    }
''', 1)

# Recheck a wider recent approved-bank window each pass; dedupe prevents repeats.
text = text.replace('NSInteger approvedMessageLimit = manualRequested ? 15 : 10;', 'NSInteger approvedMessageLimit = manualRequested ? 15 : 50;', 1)
text = text.replace('NSInteger databaseRowLimit = manualRequested ? 15 : 250;', 'NSInteger databaseRowLimit = manualRequested ? 15 : 500;', 1)
text = text.replace('@"Automatic latest-10 scan"', '@"Realtime capture/parser scan"', 1)

# Manual requests must be observed before the app-side 25 second stale timeout.
if 'sleep(30);' not in text:
    raise RuntimeError("daemon sleep(30) anchor not found")
text = text.replace('sleep(30);', 'sleep(5);', 1)
write(source, text)

# Any approved-bank SMS carrying a currency/amount is reviewable even when its
# wording is unknown. Known OTP/security filtering remains an AI/user decision.
text = read(source)
pattern = re.compile(r'''static BOOL LooksLikeTransactionForReview\(NSString \*text\) \{(.*?)\n\}\n\nstatic NSDictionary \*ReviewDraftForUnrecognizedBankSMS''', re.S)
m = pattern.search(text)
if not m:
    raise RuntimeError("LooksLikeTransactionForReview function not found")
body = m.group(1)
if 'return NO;' not in body:
    raise RuntimeError("LooksLikeTransactionForReview final return NO not found")
body = body.rsplit('return NO;', 1)[0] + 'return YES; // approved-bank currency movement: never silently drop; user/AI reviews it.' + body.rsplit('return NO;', 1)[1]
text = text[:m.start(1)] + body + text[m.end(1):]
write(source, text)

# Make the UI tell the truth about realtime capture and keep the local waiting
# window safely above the daemon response time.
view = "DailyLedger/Views/SMSImportConsoleView.swift"
text = read(view)
text = text.replace('Automatic Scan Interval', 'Recovery Scan Interval', 1)
text = text.replace('Automatic bank detection remains separate. Collect Latest 15 reads the newest 15 incoming Messages database rows without sender filtering and places their recovered full text in a user-review list. Nothing from this manual history scan is recorded automatically.',
                    'New approved-bank SMS are captured into Review immediately before any parser or AI decision. Collect Latest 15 remains an unfiltered manual history check. Capture cannot be skipped just because classification fails.', 1)
text = text.replace('Date().timeIntervalSince(requested) <= 25', 'Date().timeIntervalSince(requested) <= 45', 1)
text = text.replace('Date().timeIntervalSince(requested) > 25', 'Date().timeIntervalSince(requested) > 45', 1)
write(view, text)

# Keep visible app version accurate.
settings = "DailyLedger/Views/SettingsView.swift"
text = read(settings)
text = re.sub(r'LabeledContent\("Version", value: "[^"]+"\)', 'LabeledContent("Version", value: "1.3.62")', text, count=1)
write(settings, text)

print("Prepared Next Ledger 1.3.62 + daemon 2.2.3: capture-first realtime bank SMS inbox, 5-second manual response, wider deduped parser window, and no interval-gated discovery.")
