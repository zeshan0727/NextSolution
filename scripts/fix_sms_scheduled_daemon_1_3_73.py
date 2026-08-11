from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")

def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}: {old[:160]!r}; got {count}")
    write(path, text.replace(old, new, 1))

# ---------------------------------------------------------------------------
# Release versions.
# ---------------------------------------------------------------------------
replace_once("project.yml", 'MARKETING_VERSION: "1.3.72"', 'MARKETING_VERSION: "1.3.73"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "80"', 'CURRENT_PROJECT_VERSION: "81"')

settings_path = "DailyLedger/Views/SettingsView.swift"
settings = read(settings_path)
settings, count = re.subn(
    r'LabeledContent\("Version", value: "1\.3\.72"\)',
    'LabeledContent("Version", value: "1.3.73")',
    settings,
    count=1,
)
if count != 1:
    raise RuntimeError("Could not bump visible app version to 1.3.73")
write(settings_path, settings)

source = "RootHideSMSQueue/Sources/main.m"
replace_once(source, 'static NSString *const kDaemonVersion = @"2.2.3";', 'static NSString *const kDaemonVersion = @"2.2.4";')
replace_once("RootHideSMSQueue/control", "Version: 2.2.3", "Version: 2.2.4")
for path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    text = read(path)
    text = text.replace("Next Ledger SMS Daemon 2.2.3 installation started", "Next Ledger SMS Daemon 2.2.4 installation started")
    write(path, text)

# ---------------------------------------------------------------------------
# App configuration: Scheduled mode is the default. Realtime capture is now an
# explicit opt-in switch instead of being silently forced by the daemon.
# ---------------------------------------------------------------------------
service_path = "DailyLedger/Services/SMSImportConsoleService.swift"
service = read(service_path)
service = service.replace(
    "    var autoRecord = false\n",
    "    var autoRecord = false\n    var realtimeCaptureEnabled = false\n",
    1,
)
service = service.replace(
    "        case autoRecord\n",
    "        case autoRecord\n        case realtimeCaptureEnabled\n",
    1,
)
service = service.replace(
    "        autoRecord = try container.decodeIfPresent(Bool.self, forKey: .autoRecord) ?? false\n",
    "        autoRecord = try container.decodeIfPresent(Bool.self, forKey: .autoRecord) ?? false\n        realtimeCaptureEnabled = try container.decodeIfPresent(Bool.self, forKey: .realtimeCaptureEnabled) ?? false\n",
    1,
)

save_anchor = """        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: configurationURL.path
        )
"""
if service.count(save_anchor) != 1:
    raise RuntimeError("SMS configuration save anchor not found")
service = service.replace(
    save_anchor,
    save_anchor + """        // Wake the root daemon only when configuration/manual-scan state changes.
        // The daemon otherwise blocks until the next scheduled scan instead of polling sms.db.
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.nextsolution.dailyledger.sms-daemon-wake" as CFString),
            nil,
            nil,
            true
        )
""",
    1,
)
write(service_path, service)

# ---------------------------------------------------------------------------
# SMS Console UI: make the difference between scheduled and realtime explicit.
# ---------------------------------------------------------------------------
view_path = "DailyLedger/Views/SMSImportConsoleView.swift"
view = read(view_path)
view = view.replace(
    '                Toggle("Auto Record", isOn: $configuration.autoRecord)\n',
    '                Toggle("Auto Record", isOn: $configuration.autoRecord)\n                Toggle("Realtime SMS Capture", isOn: $configuration.realtimeCaptureEnabled)\n',
    1,
)
view = view.replace('Text("Recovery Scan Interval")', 'Text("Scheduled SMS Scan Interval")', 1)
old_help = '                Text("New approved-bank SMS are captured into Review immediately before any parser or AI decision. Collect Latest 15 remains an unfiltered manual history check. Capture cannot be skipped just because classification fails.")\n                    .font(.caption)\n                    .foregroundStyle(.secondary)\n'
new_help = '''                if configuration.realtimeCaptureEnabled {
                    Text("Realtime mode is ON: the daemon may inspect approved-bank SMS every few seconds and Auto Record may post immediately. Turn this OFF to obey the scheduled interval.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Scheduled mode: Messages are not scanned continuously. Automatic detection and Auto Record run only at the selected interval. Collect Latest 15 wakes the daemon immediately for a manual review scan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
'''
if old_help not in view:
    raise RuntimeError("Realtime capture help text anchor not found")
view = view.replace(old_help, new_help, 1)
old_footer = '                Text("Only new or never-reviewed SMS from approved senders and mapped card endings become drafts. Nothing is written to the ledger until you approve it. Rejected and approved SMS cannot return.")\n'
new_footer = '''                Text(configuration.autoRecord
                    ? (configuration.realtimeCaptureEnabled
                        ? "Auto Record is enabled with Realtime Capture, so recognized SMS can post immediately."
                        : "Auto Record is enabled, but recognized SMS can post only when the scheduled scan runs. Manual Latest 15 review never auto-posts.")
                    : "Auto Record is off. New recognized SMS become drafts/review items and are not written to the ledger until you approve them.")
'''
if old_footer in view:
    view = view.replace(old_footer, new_footer, 1)
write(view_path, view)

# ---------------------------------------------------------------------------
# Daemon 2.2.4: restore the configured interval gate, and replace the 5-second
# polling loop with a blocking semaphore. The app posts a Darwin notification
# when settings/manual-scan request changes, so manual scans remain immediate.
# ---------------------------------------------------------------------------
daemon = read(source)
if '#import <dispatch/dispatch.h>' not in daemon:
    daemon = daemon.replace('#import <unistd.h>\n', '#import <unistd.h>\n#import <dispatch/dispatch.h>\n', 1)

daemon = daemon.replace(
    'static NSMutableDictionary *gState;\n',
    'static NSMutableDictionary *gState;\nstatic dispatch_semaphore_t gDaemonWakeSemaphore;\nstatic NSString *const kDaemonWakeNotification = @"com.nextsolution.dailyledger.sms-daemon-wake";\n',
    1,
)

daemon = daemon.replace(
    '        @"autoRecord": @NO,\n',
    '        @"autoRecord": @NO,\n        @"realtimeCaptureEnabled": @NO,\n',
    1,
)

daemon = daemon.replace(
    '__attribute__((unused)) static BOOL AutomaticScanIsDue(NSDictionary *config, NSDate *now) {',
    'static BOOL AutomaticScanIsDue(NSDictionary *config, NSDate *now) {',
    1,
)

old_gate = '    // Capture-first mode: discovery is realtime; interval no longer gates sms.db reads.\n'
new_gate = '''    BOOL realtimeCaptureEnabled = [config[@"realtimeCaptureEnabled"] boolValue];
    if (!manualRequested && !realtimeCaptureEnabled && !AutomaticScanIsDue(config, scanDate)) {
        // Scheduled mode: do not touch sms.db, drafts, AI queues or ledger before the due time.
        return;
    }
'''
if daemon.count(old_gate) != 1:
    raise RuntimeError("1.3.62 realtime gate-removal marker not found")
daemon = daemon.replace(old_gate, new_gate, 1)

daemon = daemon.replace(
    '    NSString *mode = manualRequested ? @"Manual recovery scan" : @"Realtime capture/parser scan";\n',
    '    NSString *mode = manualRequested ? @"Manual recovery scan" : (realtimeCaptureEnabled ? @"Realtime capture/parser scan" : @"Scheduled SMS scan");\n',
    1,
)

main_anchor = 'int main(int argc, char *argv[]) {'
if main_anchor not in daemon:
    raise RuntimeError("daemon main anchor not found")
helpers = r'''static void DaemonWakeNotificationCallback(
    CFNotificationCenterRef center,
    void *observer,
    CFNotificationName name,
    const void *object,
    CFDictionaryRef userInfo
) {
    if (gDaemonWakeSemaphore) dispatch_semaphore_signal(gDaemonWakeSemaphore);
}

static NSTimeInterval DaemonWaitSeconds(NSDictionary *config) {
    if ([config[@"realtimeCaptureEnabled"] boolValue]) return 5.0;
    NSTimeInterval last = [gState[@"lastAutomaticScanUnix"] doubleValue];
    if (last <= 0) return 1.0;
    NSTimeInterval interval = (NSTimeInterval)ConfiguredAutomaticScanHours(config) * 60.0 * 60.0;
    NSTimeInterval elapsed = NSDate.date.timeIntervalSince1970 - last;
    NSTimeInterval remaining = interval - elapsed;
    return remaining > 1.0 ? remaining : 1.0;
}

'''
daemon = daemon.replace(main_anchor, helpers + main_anchor, 1)

old_main_loop = '''        while (true) {
            @autoreleasepool {
                ScanMessages(NO);
                WriteConsole(nil);
            }
            sleep(5);
        }
'''
new_main_loop = '''        gDaemonWakeSemaphore = dispatch_semaphore_create(0);
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            DaemonWakeNotificationCallback,
            (__bridge CFStringRef)kDaemonWakeNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );

        while (true) {
            @autoreleasepool {
                ScanMessages(NO);
            }
            NSDictionary *config = LoadConfiguration();
            NSTimeInterval waitSeconds = DaemonWaitSeconds(config);
            dispatch_time_t deadline = dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(waitSeconds * (NSTimeInterval)NSEC_PER_SEC)
            );
            // Blocks in the kernel: no 5-second sms.db polling and no heartbeat file writes.
            // A settings/manual-scan Darwin notification wakes this immediately.
            dispatch_semaphore_wait(gDaemonWakeSemaphore, deadline);
        }
'''
if daemon.count(old_main_loop) != 1:
    raise RuntimeError("daemon 5-second main loop anchor not found")
daemon = daemon.replace(old_main_loop, new_main_loop, 1)
write(source, daemon)

print("Prepared Next Ledger 1.3.73 / daemon 2.2.4: scheduled SMS scanning obeys the user interval, realtime is explicit opt-in, manual scan wakes immediately, and continuous 5-second sms.db polling is removed.")
