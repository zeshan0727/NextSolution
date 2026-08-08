#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:300]!r}")
    path.write_text(text.replace(old, new, 1))


# MARK: - Always deliver an exact-time banner and sound.
services = SOURCES / "Services.swift"
replace_once(
    services,
    '''        var effectiveOffsets = reminder.alertOffsets
        if reminder.isHourlyRoutine {
            effectiveOffsets.insert(.atTime)
        }

        for offset in effectiveOffsets {''',
    '''        var effectiveOffsets = reminder.alertOffsets
        // An exact-time alert is mandatory whenever notifications are enabled.
        // Advance alerts remain optional, but can never be the only alert.
        effectiveOffsets.insert(.atTime)

        for offset in effectiveOffsets {'''
)
replace_once(
    services,
    '''            content.interruptionLevel = reminder.priority == .urgent ? .timeSensitive : .active
            content.userInfo = ["reminderID": reminder.id.uuidString]''',
    '''            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
            content.userInfo = ["reminderID": reminder.id.uuidString]'''
)
replace_once(
    services,
    '''extension Notification.Name {
    static let nextReminderActionReceived = Notification.Name("nextReminderActionReceived")
}''',
    '''extension Notification.Name {
    static let nextReminderActionReceived = Notification.Name("nextReminderActionReceived")
    static let nextNotificationDeliveryIssue = Notification.Name("NextReminder.NotificationDeliveryIssue")
}'''
)
replace_once(
    services,
    '''    func openSystemSettings() {''',
    '''    func checkDeliverySettings() async {
        let settings = await center.notificationSettings()
        let message: String?

        switch settings.authorizationStatus {
        case .denied:
            message = "Notifications are denied for Next Reminder. Enable Allow Notifications, Banners and Sounds in iPhone Settings."
        case .authorized, .provisional, .ephemeral:
            if settings.alertSetting != .enabled {
                message = "Notification banners are disabled. Enable Lock Screen, Notification Centre and Banners for Next Reminder."
            } else if settings.soundSetting != .enabled {
                message = "Notification sounds are disabled. Enable Sounds for Next Reminder in iPhone Settings."
            } else {
                message = nil
            }
        case .notDetermined:
            message = nil
        @unknown default:
            message = nil
        }

        if let message {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .nextNotificationDeliveryIssue,
                    object: message
                )
            }
        }
    }

    func openSystemSettings() {'''
)

# Check iOS delivery settings whenever the app becomes active.
app = SOURCES / "App.swift"
app_text = app.read_text()
needle = '''                    automationStore.refreshDueStatuses()
'''
if needle not in app_text:
    raise SystemExit("Could not find scene activation refresh in App.swift")
if "NotificationManager.shared.checkDeliverySettings()" not in app_text:
    app_text = app_text.replace(
        needle,
        needle + '''                    Task { await NotificationManager.shared.checkDeliverySettings() }
''',
        1
    )
app.write_text(app_text)

# Show an in-app warning when iOS itself allows badges but blocks banners/sounds.
root = SOURCES / "RootReminders.swift"
replace_once(
    root,
    '''    @State private var gmailDisconnectAlert: String? = GmailConnectionIssueStore.shared.load()?.message''',
    '''    @State private var gmailDisconnectAlert: String? = GmailConnectionIssueStore.shared.load()?.message
    @State private var notificationDeliveryAlert: String?'''
)
replace_once(
    root,
    '''        .onReceive(NotificationCenter.default.publisher(for: .nextGmailConnectionInvalidated)) { notification in''',
    '''        .onReceive(NotificationCenter.default.publisher(for: .nextNotificationDeliveryIssue)) { notification in
            notificationDeliveryAlert = notification.object as? String
        }
        .alert("Notification Delivery Needs Attention", isPresented: Binding(
            get: { notificationDeliveryAlert != nil },
            set: { if !$0 { notificationDeliveryAlert = nil } }
        )) {
            Button("Open Notification Settings") {
                NotificationManager.shared.openSystemSettings()
            }
            Button("Later", role: .cancel) { notificationDeliveryAlert = nil }
        } message: {
            Text(notificationDeliveryAlert ?? "Enable notification banners and sounds for Next Reminder.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextGmailConnectionInvalidated)) { notification in'''
)

# MARK: - Preserve Gmail connection records on health failures.
gmail = SOURCES / "GmailConnection.swift"
replace_once(
    gmail,
    '''    private let key = "NextReminder.GmailConnection.v1"
    private init() {}''',
    '''    private let key = "NextReminder.GmailConnection.v1"
    private let manualDisconnectKey = "NextReminder.GmailManualDisconnect.v1"
    private init() {}'''
)
replace_once(
    gmail,
    '''        UserDefaults.standard.set(data, forKey: key)
        GmailConnectionIssueStore.shared.clear()''',
    '''        UserDefaults.standard.set(data, forKey: key)
        UserDefaults.standard.removeObject(forKey: manualDisconnectKey)
        GmailConnectionIssueStore.shared.clear()'''
)
replace_once(
    gmail,
    '''    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        GmailConnectionIssueStore.shared.clear()
        Task { await GmailConnectionAlertManager.shared.clearAlert() }
    }''',
    '''    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.set(true, forKey: manualDisconnectKey)
        GmailConnectionIssueStore.shared.clear()
        Task { await GmailConnectionAlertManager.shared.clearAlert() }
    }

    var wasManuallyDisconnected: Bool {
        UserDefaults.standard.bool(forKey: manualDisconnectKey)
    }'''
)
replace_once(
    gmail,
    '''        UserDefaults.standard.removeObject(forKey: key)
        let emailAddress = current?.emailAddress ?? settings.senderLabel
        settings.remoteConnectorID = ""
        settings.senderLabel = ""
        settings.persist()

        let issue = GmailConnectionIssue(''',
    '''        // Keep the local connector ID and email address. A temporary server
        // restart or failed health check must never silently log the user out.
        let emailAddress = current?.emailAddress ?? settings.senderLabel

        let issue = GmailConnectionIssue('''
)
replace_once(
    gmail,
    '''        guard !isChecking, let record = GmailConnectionStore.shared.load() else { return }
        if !force,''',
    '''        guard !isChecking else { return }

        guard let record = GmailConnectionStore.shared.load() else {
            let settings = EmailAutomationSettings.load()
            guard !GmailConnectionStore.shared.wasManuallyDisconnected,
                  settings.enabled,
                  settings.deliveryMethod == .gmailAutomatic else { return }

            let reason = "Gmail is not connected on this installation. Connect Gmail again to resume automatic sending."
            let issue = GmailConnectionIssue(
                emailAddress: settings.senderLabel,
                message: reason,
                detectedAt: Date()
            )
            GmailConnectionIssueStore.shared.save(issue)
            NotificationCenter.default.post(name: .nextGmailConnectionInvalidated, object: reason)
            await GmailConnectionAlertManager.shared.notifyDisconnected(issue: issue)
            return
        }

        if !force,'''
)
replace_once(
    gmail,
    '''            case .connected:
                break
            case .disconnected(let reason):''',
    '''            case .connected:
                GmailConnectionIssueStore.shared.clear()
                await GmailConnectionAlertManager.shared.clearAlert()
            case .disconnected(let reason):'''
)
replace_once(
    gmail,
    '''    @State private var errorMessage: String?''',
    '''    @State private var errorMessage: String?
    @State private var connectionIssue: GmailConnectionIssue?'''
)
replace_once(
    gmail,
    '''            if let record {
                HStack(spacing: 12) {''',
    '''            if let record {
                HStack(spacing: 12) {'''
)
replace_once(
    gmail,
    '''                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(.green)''',
    '''                    Image(systemName: connectionIssue == nil ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(connectionIssue == nil ? Color.green : Color.orange)'''
)
replace_once(
    gmail,
    '''                        Text("Gmail connected")
                            .font(.headline)''',
    '''                        Text(connectionIssue == nil ? "Gmail connected" : "Gmail needs reconnection")
                            .font(.headline)'''
)
replace_once(
    gmail,
    '''                        Text("Secure OAuth connection")
                            .font(.caption)
                            .foregroundStyle(.secondary)''',
    '''                        Text(connectionIssue?.message ?? "Secure OAuth connection")
                            .font(.caption)
                            .foregroundStyle(connectionIssue == nil ? Color.secondary : Color.orange)'''
)
replace_once(
    gmail,
    '''                Button(role: .destructive) {
                    disconnect(record)''',
    '''                if connectionIssue != nil {
                    Button {
                        connect()
                    } label: {
                        Label(isConnecting ? "Reconnecting Gmail…" : "Reconnect Gmail", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConnecting)
                }

                Button(role: .destructive) {
                    disconnect(record)'''
)
replace_once(
    gmail,
    '''        .onAppear {
            record = GmailConnectionStore.shared.load()
            if let record {''',
    '''        .onAppear {
            record = GmailConnectionStore.shared.load()
            connectionIssue = GmailConnectionIssueStore.shared.load()
            if let record {'''
)
replace_once(
    gmail,
    '''        .onReceive(NotificationCenter.default.publisher(for: .nextGmailConnectionInvalidated)) { notification in
            record = nil
            draft.remoteConnectorID = ""
            draft.senderLabel = ""
            errorMessage = (notification.object as? String)
                ?? "The saved Gmail connection is no longer valid. Connect Gmail again."
        }''',
    '''        .onReceive(NotificationCenter.default.publisher(for: .nextGmailConnectionInvalidated)) { notification in
            record = GmailConnectionStore.shared.load()
            connectionIssue = GmailConnectionIssueStore.shared.load()
            if let record {
                draft.remoteConnectorID = record.connectorID
                draft.senderLabel = record.emailAddress
            }
            errorMessage = (notification.object as? String)
                ?? "Gmail needs reconnection. Your saved connector details were preserved."
        }'''
)
replace_once(
    gmail,
    '''                record = connected
                draft.remoteConnectorID = connected.connectorID''',
    '''                record = connected
                connectionIssue = nil
                draft.remoteConnectorID = connected.connectorID'''
)
replace_once(
    gmail,
    '''                self.record = nil
                draft.remoteConnectorID = ""''',
    '''                self.record = nil
                connectionIssue = nil
                draft.remoteConnectorID = ""'''
)

# Version metadata.
project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.3.9"', 'CFBundleShortVersionString: "1.3.10"')
project_text = project_text.replace('CFBundleVersion: "19"', 'CFBundleVersion: "20"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.9"', 'MARKETING_VERSION: "1.3.10"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "19"', 'CURRENT_PROJECT_VERSION: "20"')
project.write_text(project_text)

settings = SOURCES / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.3.9 • iOS 16.0+", "Version 1.3.10 • iOS 16.0+"))

for path in SOURCES.glob("*.swift"):
    path.write_text(path.read_text().replace("NextReminder-iOS/1.3.9", "NextReminder-iOS/1.3.10"))

print("Next Reminder v1.3.10 notification and Gmail persistence fixes applied successfully.")
