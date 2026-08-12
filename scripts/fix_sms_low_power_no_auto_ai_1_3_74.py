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
        raise RuntimeError(f"Expected one match in {path}: {old[:180]!r}; got {count}")
    write(path, text.replace(old, new, 1))


# ---------------------------------------------------------------------------
# Release versions.
# ---------------------------------------------------------------------------
replace_once("project.yml", 'MARKETING_VERSION: "1.3.73"', 'MARKETING_VERSION: "1.3.74"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "81"', 'CURRENT_PROJECT_VERSION: "82"')

settings_path = "DailyLedger/Views/SettingsView.swift"
settings = read(settings_path)
settings, count = re.subn(
    r'LabeledContent\("Version", value: "1\.3\.73"\)',
    'LabeledContent("Version", value: "1.3.74")',
    settings,
    count=1,
)
if count != 1:
    raise RuntimeError("Could not bump visible app version to 1.3.74")
write(settings_path, settings)

source = "RootHideSMSQueue/Sources/main.m"
replace_once(source, 'static NSString *const kDaemonVersion = @"2.2.4";', 'static NSString *const kDaemonVersion = @"2.2.5";')
replace_once("RootHideSMSQueue/control", "Version: 2.2.4", "Version: 2.2.5")
for path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    text = read(path)
    text = text.replace("Next Ledger SMS Daemon 2.2.4 installation started", "Next Ledger SMS Daemon 2.2.5 installation started")
    write(path, text)

# ---------------------------------------------------------------------------
# App-side configuration: remove realtime mode. Scheduled mode is now the only
# automatic mode. Manual review remains immediate via a launchd WatchPaths file.
# ---------------------------------------------------------------------------
service_path = "DailyLedger/Services/SMSImportConsoleService.swift"
service = read(service_path)
for old in [
    "    var realtimeCaptureEnabled = false\n",
    "        case realtimeCaptureEnabled\n",
    "        realtimeCaptureEnabled = try container.decodeIfPresent(Bool.self, forKey: .realtimeCaptureEnabled) ?? false\n",
]:
    service = service.replace(old, "", 1)

# Replace the Darwin-notification wake with a file touch that launchd can watch
# even while the scanner process is completely stopped.
old_wake = '''        // Wake the root daemon only when configuration/manual-scan state changes.
        // The daemon otherwise blocks until the next scheduled scan instead of polling sms.db.
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.nextsolution.dailyledger.sms-daemon-wake" as CFString),
            nil,
            nil,
            true
        )
'''
new_wake = '''        // One-shot daemon architecture: changing settings or requesting a manual
        // scan touches a file watched by launchd. The scanner is not resident.
        let wakeURL = directoryURL.appendingPathComponent("sms-daemon-wake.trigger")
        let stamp = Data(String(Date().timeIntervalSince1970).utf8)
        try? stamp.write(to: wakeURL, options: .atomic)
'''
if old_wake not in service:
    raise RuntimeError("1.3.73 Darwin wake block not found")
service = service.replace(old_wake, new_wake, 1)
write(service_path, service)

# ---------------------------------------------------------------------------
# Console UI: no realtime switch, no automatic AI machinery, slower foreground
# status refresh, and truthful one-shot scheduler wording.
# ---------------------------------------------------------------------------
view_path = "DailyLedger/Views/SMSImportConsoleView.swift"
view = read(view_path)
view = view.replace('    @AppStorage("SMSAIRecognitionEnabledV1") private var aiRecognitionEnabled = false\n', '', 1)
view = view.replace('    @State private var aiProcessing = false\n', '', 1)
view = view.replace('    @State private var aiProcessedCount = 0\n', '', 1)
view = view.replace('    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()\n',
                    '    private let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()\n', 1)
view = view.replace('                Toggle("Realtime SMS Capture", isOn: $configuration.realtimeCaptureEnabled)\n', '', 1)

scheduled_help_pattern = re.compile(r'''                if configuration\.realtimeCaptureEnabled \{\n                    Text\("Realtime mode is ON:.*?\n                \}\n''', re.S)
m = scheduled_help_pattern.search(view)
if not m:
    raise RuntimeError("1.3.73 realtime/scheduled help block not found")
view = view[:m.start()] + '''                Text("Low-power scheduled mode: the SMS scanner is not kept running in the background. launchd starts it only for the hourly due-check, your selected scan interval, or a manual Latest 15 request. Auto Record can post only during a scheduled scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
''' + view[m.end():]

old_footer = '''                Text(configuration.autoRecord
                    ? (configuration.realtimeCaptureEnabled
                        ? "Auto Record is enabled with Realtime Capture, so recognized SMS can post immediately."
                        : "Auto Record is enabled, but recognized SMS can post only when the scheduled scan runs. Manual Latest 15 review never auto-posts.")
                    : "Auto Record is off. New recognized SMS become drafts/review items and are not written to the ledger until you approve them.")
'''
new_footer = '''                Text(configuration.autoRecord
                    ? "Auto Record is enabled. Recognized SMS can post only when the scheduled scan runs; manual Latest 15 review never auto-posts."
                    : "Auto Record is off. Recognized SMS become drafts/review items and are not written to the ledger until you approve them.")
'''
if old_footer not in view:
    raise RuntimeError("1.3.73 SMS footer not found")
view = view.replace(old_footer, new_footer, 1)

# Automatic AI function is not useful in the scheduled recorder and could keep
# retrying network/API work. Remove it; manual Ask AI remains in Latest 15 Review.
start = view.find('    private func startAIRecognitionIfNeeded() {')
if start >= 0:
    end = view.find('    private var daemonStatus: String {', start)
    if end < 0:
        raise RuntimeError("Could not find end of automatic AI function")
    view = view[:start] + view[end:]

view = view.replace('statusRow(title: "Last Heartbeat", value: formatted(snapshot.lastHeartbeat), icon: "waveform.path.ecg")',
                    'statusRow(title: "Last Service Wake", value: formatted(snapshot.lastHeartbeat), icon: "clock.badge.checkmark")', 1)
old_daemon_status = '''    private var daemonStatus: String {
        guard snapshot.daemonRunning, let heartbeat = snapshot.lastHeartbeat else {
            return "Not detected"
        }
        return Date().timeIntervalSince(heartbeat) < 15 ? "Running" : "Heartbeat stale"
    }
'''
new_daemon_status = '''    private var daemonStatus: String {
        guard let heartbeat = snapshot.lastHeartbeat else { return "Not detected" }
        return Date().timeIntervalSince(heartbeat) < 15 ? "Running scan" : "Idle · launchd scheduled"
    }
'''
if old_daemon_status not in view:
    raise RuntimeError("daemonStatus block not found")
view = view.replace(old_daemon_status, new_daemon_status, 1)
write(view_path, view)

# ---------------------------------------------------------------------------
# Daemon 2.2.5: no resident process, no realtime mode, no automatic AI queue.
# launchd starts the process hourly and when the app's wake file changes. The
# configured interval gate decides whether sms.db is touched; manual scanRequest
# bypasses that gate. Process exits after each invocation.
# ---------------------------------------------------------------------------
daemon = read(source)
daemon = daemon.replace('#import <dispatch/dispatch.h>\n', '', 1)
daemon = daemon.replace('static dispatch_semaphore_t gDaemonWakeSemaphore;\n', '', 1)
daemon = daemon.replace('static NSString *const kDaemonWakeNotification = @"com.nextsolution.dailyledger.sms-daemon-wake";\n', '', 1)
daemon = daemon.replace('        @"realtimeCaptureEnabled": @NO,\n', '', 1)

old_gate = '''    BOOL realtimeCaptureEnabled = [config[@"realtimeCaptureEnabled"] boolValue];
    if (!manualRequested && !realtimeCaptureEnabled && !AutomaticScanIsDue(config, scanDate)) {
        // Scheduled mode: do not touch sms.db, drafts, AI queues or ledger before the due time.
        return;
    }
'''
new_gate = '''    if (!manualRequested && !AutomaticScanIsDue(config, scanDate)) {
        // Low-power scheduled mode: hourly launchd due-check exits here without
        // opening sms.db, creating drafts, touching AI queues or changing ledger.
        return;
    }
'''
if old_gate not in daemon:
    raise RuntimeError("1.3.73 scheduled gate not found")
daemon = daemon.replace(old_gate, new_gate, 1)

daemon = daemon.replace(
    '    NSString *mode = manualRequested ? @"Manual recovery scan" : (realtimeCaptureEnabled ? @"Realtime capture/parser scan" : @"Scheduled SMS scan");\n',
    '    NSString *mode = manualRequested ? @"Manual recovery scan" : @"Scheduled SMS scan";\n',
    1,
)

# Remove every automatic OpenAI candidate enqueue from the daemon. Unknown
# messages remain reviewable through the existing manual-review draft/inbox.
daemon = re.sub(r'\n\s*QueueAICandidate\([^;]+\);', '', daemon)
daemon = daemon.replace('queued for OpenAI database recovery', 'left for manual review', 1)
daemon = daemon.replace('queued for OpenAI recovery', 'left for manual review')
daemon = daemon.replace('and queued OpenAI enrichment', 'and left it for manual review')

helper_start = daemon.find('static void DaemonWakeNotificationCallback(')
if helper_start >= 0:
    helper_end = daemon.find('int main(int argc, char *argv[]) {', helper_start)
    if helper_end < 0:
        raise RuntimeError("Could not locate daemon main after wake helpers")
    daemon = daemon[:helper_start] + daemon[helper_end:]

old_resident = '''        gDaemonWakeSemaphore = dispatch_semaphore_create(0);
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
new_one_shot = '''        // One-shot service: scan if due/requested, publish status, then terminate.
        // launchd will start a fresh process at the next hourly check or wake-file change.
        ScanMessages(NO);
        WriteConsole(nil);
        return 0;
'''
if old_resident not in daemon:
    raise RuntimeError("1.3.73 resident daemon loop not found")
daemon = daemon.replace(old_resident, new_one_shot, 1)
write(source, daemon)

# ---------------------------------------------------------------------------
# launchd: remove KeepAlive. One hourly launch is used only as a cheap due-check
# for the user-selected 1...168 hour interval. WatchPaths gives immediate manual
# scans/settings wake without a permanently resident process.
# ---------------------------------------------------------------------------
plist_path = "RootHideSMSQueue/layout/Library/LaunchDaemons/com.nextsolution.nextledgersmsd.plist"
plist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nextsolution.nextledgersmsd</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/libexec/nextledgersmsd</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>WatchPaths</key>
    <array>
        <string>__NEXTLEDGER_WAKE_PATH__</string>
    </array>
    <key>ProcessType</key>
    <string>Background</string>
    <key>Nice</key>
    <integer>10</integer>
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
'''
write(plist_path, plist)

# Patch both package postinst copies to replace the dynamic WatchPaths placeholder
# with the currently installed Next Ledger app-container wake file BEFORE launchd
# bootstrap. This preserves immediate manual scan while the daemon itself is dead.
for postinst_path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    post = read(postinst_path)
    anchor = 'launchctl bootout "user/501/$LABEL" >/dev/null 2>&1 || true\n'
    if anchor not in post:
        raise RuntimeError(f"launchctl anchor missing in {postinst_path}")
    inject = r'''APP_SUPPORT=""
for META in /rootfs/var/mobile/Containers/Data/Application/*/.com.apple.mobile_container_manager.metadata.plist /var/mobile/Containers/Data/Application/*/.com.apple.mobile_container_manager.metadata.plist; do
    [ -f "$META" ] || continue
    if grep -a -q "com.nextsolution.dailyledger" "$META" 2>/dev/null; then
        CONTAINER="${META%/.com.apple.mobile_container_manager.metadata.plist}"
        APP_SUPPORT="$CONTAINER/Library/Application Support/DailyLedger"
        break
    fi
done
if [ -n "$APP_SUPPORT" ]; then
    mkdir -p "$APP_SUPPORT" 2>/dev/null || true
    WAKE_PATH="$APP_SUPPORT/sms-daemon-wake.trigger"
    : > "$WAKE_PATH" 2>/dev/null || true
    chown mobile:mobile "$WAKE_PATH" 2>/dev/null || true
    chmod 644 "$WAKE_PATH" 2>/dev/null || true
else
    WAKE_PATH="/var/mobile/Library/NextLedgerSMSImport/sms-daemon-wake.trigger"
    : > "$WAKE_PATH" 2>/dev/null || true
fi
if [ -f "$PLIST_ROOTFS" ]; then
    TMP_PLIST="${PLIST_ROOTFS}.nextledger.tmp"
    sed "s|__NEXTLEDGER_WAKE_PATH__|$WAKE_PATH|g" "$PLIST_ROOTFS" > "$TMP_PLIST" 2>/dev/null && mv -f "$TMP_PLIST" "$PLIST_ROOTFS"
fi

echo "Low-power wake path: $WAKE_PATH"
'''
    post = post.replace(anchor, inject + anchor, 1)
    write(postinst_path, post)

print("Prepared Next Ledger 1.3.74 / daemon 2.2.5: one-shot launchd SMS scanner, no KeepAlive, no realtime polling, no automatic AI queue/retry, scheduled Auto Record only, manual Ask AI retained in review.")
