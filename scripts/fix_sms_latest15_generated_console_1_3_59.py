from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

def write(path, text):
    (ROOT / path).write_text(text, encoding="utf-8")

# ---------------------------------------------------------------------------
# Repair the exact generated 1.3.59 SMS Console. The first patch used a broad
# regex and left part of the superseded AI block/braces behind. Replace the whole
# generated region by stable markers instead.
# ---------------------------------------------------------------------------
view = "DailyLedger/Views/SMSImportConsoleView.swift"
text = read(view)
start_marker = '''                NavigationLink {
                    SMSLatest15ReviewView()
'''
end_marker = '''                Button {
                    restoreRejectedForReview()
'''
start = text.find(start_marker)
end = text.find(end_marker, start)
if start < 0 or end < 0:
    raise RuntimeError(f"Latest-15/restore generated markers not found (start={start}, end={end})")
clean = '''                NavigationLink {
                    SMSLatest15ReviewView()
                } label: {
                    Label("Review Latest 15 Messages (\\(SMSLatest15ReviewService.load().count))", systemImage: "text.bubble.fill")
                }

                LabeledContent(
                    "AI Helper",
                    value: OpenAIService.shared.hasAPIKey ? "Ready · Test inside Latest 15 Review" : "OpenAI API required"
                )
                Text("Manual collection always shows the latest 15 incoming messages with their recovered full text. OpenAI is optional assistance inside Latest 15 Review; it never approves or records a message by itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

'''
text = text[:start] + clean + text[end:]
text = text.replace(
    'Text("Automatic scans recheck the latest 10 approved-bank SMS. Manual Scan checks only the latest 30 incoming SMS rows, ignores already approved, rejected or pending IDs, and creates drafts only for unreported transactions.")',
    'Text("Automatic bank detection remains separate. Collect Latest 15 reads the newest 15 incoming Messages database rows without sender filtering and places their recovered full text in a user-review list. Nothing from this manual history scan is recorded automatically.")',
    1,
)
text = text.replace(
    'notice = "Restored \\(restored) rejected SMS item\\(restored == 1 ? "" : "s") for review. A latest-30 manual scan was requested."',
    'notice = "Restored \\(restored) rejected SMS item\\(restored == 1 ? "" : "s") for review. Collect Latest 15 again if you also want a fresh database review list."',
    1,
)
write(view, text)

# ---------------------------------------------------------------------------
# Manual database collection must clear status on every early failure and must
# work even when automatic SMS Detection is disabled. Automatic detection stays
# disabled; only an explicit manual request bypasses that toggle.
# ---------------------------------------------------------------------------
source = "RootHideSMSQueue/Sources/main.m"
text = read(source)
old_prefix = '''static void ScanMessages(BOOL forceRecent) {
    NSDictionary *config = LoadConfiguration();
    ApplyMaintenanceRequests(config);
    if (config[@"enabled"] && ![config[@"enabled"] boolValue]) {
        WriteConsole(@"Automatic bank SMS detection is disabled in Next Ledger settings.");
        return;
    }

    NSInteger requestID = [config[@"scanRequestID"] integerValue];
    NSInteger savedRequest = [gState[@"lastScanRequestID"] integerValue];
    BOOL manualRequested = forceRecent || requestID != savedRequest;
    NSDate *scanDate = NSDate.date;
'''
new_prefix = '''static void ScanMessages(BOOL forceRecent) {
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
'''
if text.count(old_prefix) != 1:
    raise RuntimeError(f"Expected one generated ScanMessages prefix, found {text.count(old_prefix)}")
text = text.replace(old_prefix, new_prefix, 1)

old_unreadable = '''    if (![NSFileManager.defaultManager isReadableFileAtPath:databasePath]) {
        AddLog(@"error", @"Messages database is not readable at %@.", databasePath ?: @"unknown path");
        WriteConsole(@"Messages database is unavailable or unreadable.");
        return;
    }
'''
new_unreadable = '''    if (![NSFileManager.defaultManager isReadableFileAtPath:databasePath]) {
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
'''
if text.count(old_unreadable) != 1:
    raise RuntimeError(f"Expected one unreadable-db block, found {text.count(old_unreadable)}")
text = text.replace(old_unreadable, new_unreadable, 1)

# Make the two already-protected early failures write an updated console after
# clearing state, so the app immediately sees that scanning stopped.
text = text.replace(
    'if (manualRequested) { gState[@"scanInProgress"] = @NO; gState[@"scanPhase"] = @"Manual scan failed"; SaveState(); }\n        return;',
    'if (manualRequested) { gState[@"scanInProgress"] = @NO; gState[@"scanProgressCurrent"] = @0; gState[@"scanProgressTotal"] = @15; gState[@"scanPhase"] = @"Manual scan failed"; SaveState(); WriteConsole(@"Manual scan failed and stopped."); }\n        return;',
    2,
)
write(source, text)

print("Repaired generated 1.3.59 SMS Console braces and made Latest-15 manual scan fail-safe on every database/container error.")
