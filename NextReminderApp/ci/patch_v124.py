#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:160]!r}")
    path.write_text(text.replace(old, new, 1))


def regex_once(path: Path, pattern: str, replacement: str) -> None:
    text = path.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"Expected one regex match in {path}, found {count}: {pattern}")
    path.write_text(updated)


# MARK: - Global stale Gmail connector invalidation.
gmail = SOURCES / "GmailConnection.swift"
replace_once(
    gmail,
    '''    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}''',
    '''    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    func invalidate(connectorID: String? = nil) {
        if let connectorID,
           let current = load(),
           current.connectorID != connectorID {
            return
        }

        clear()
        var settings = EmailAutomationSettings.load()
        settings.remoteConnectorID = ""
        settings.senderLabel = ""
        settings.persist()
        NotificationCenter.default.post(name: .nextGmailConnectionInvalidated, object: nil)
    }
}

extension Notification.Name {
    static let nextGmailConnectionInvalidated = Notification.Name("NextReminder.GmailConnectionInvalidated")
}'''
)
replace_once(
    gmail,
    '''        .onAppear {
            record = GmailConnectionStore.shared.load()
            if let record {
                draft.remoteConnectorID = record.connectorID
                if draft.senderLabel.isEmpty { draft.senderLabel = record.emailAddress }
            }
        }
        .alert("Gmail Connection", isPresented: Binding(''',
    '''        .onAppear {
            record = GmailConnectionStore.shared.load()
            if let record {
                draft.remoteConnectorID = record.connectorID
                if draft.senderLabel.isEmpty { draft.senderLabel = record.emailAddress }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextGmailConnectionInvalidated)) { _ in
            record = nil
            draft.remoteConnectorID = ""
            draft.senderLabel = ""
            errorMessage = "The saved Gmail connector no longer exists on the scheduler. Connect Gmail again."
        }
        .alert("Gmail Connection", isPresented: Binding('''
)

# MARK: - Invalidate stale Gmail after any reminder-email server rejection.
email_core = SOURCES / "EmailAutomationCore.swift"
replace_once(
    email_core,
    '''            let message = (try? JSONDecoder().decode(EmailSchedulerResponse.self, from: data).message)
                ?? "Email scheduler request failed (\(http.statusCode))."
            throw EmailAutomationError.server(message)''',
    '''            let message = (try? JSONDecoder().decode(EmailSchedulerResponse.self, from: data).message)
                ?? "Email scheduler request failed (\(http.statusCode))."
            let lowered = message.lowercased()
            if lowered.contains("gmail connector not found")
                || lowered.contains("reconnect gmail")
                || lowered.contains("reconnect the gmail account") {
                GmailConnectionStore.shared.invalidate()
            }
            throw EmailAutomationError.server(message)'''
)

# MARK: - File Sharing direct reconnect and stale connector handling.
files = SOURCES / "FileSharing.swift"
replace_once(
    files,
    '''    case schedulerNotConfigured
    case gmailNotConnected
    case invalidRecipient''',
    '''    case schedulerNotConfigured
    case gmailNotConnected
    case connectorExpired
    case invalidRecipient'''
)
replace_once(
    files,
    '''        case .gmailNotConnected:
            return "Connect Gmail in Email Automations before sharing files."
        case .invalidRecipient:''',
    '''        case .gmailNotConnected:
            return "Connect Gmail before sharing files."
        case .connectorExpired:
            return "The saved Gmail connector no longer exists on the scheduler. Reconnect Gmail and try again."
        case .invalidRecipient:'''
)
replace_once(
    files,
    '''        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(FileShareServerResponse.self, from: data).message)
                ?? "File sharing failed (\(http.statusCode))."
            throw FileShareError.server(message)
        }''',
    '''        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(FileShareServerResponse.self, from: data).message)
                ?? "File sharing failed (\(http.statusCode))."
            let lowered = message.lowercased()
            if lowered.contains("gmail connector not found")
                || lowered.contains("reconnect gmail")
                || lowered.contains("reconnect the gmail account") {
                throw FileShareError.connectorExpired
            }
            throw FileShareError.server(message)
        }'''
)
replace_once(
    files,
    '''struct FileSharingView: View {
    @EnvironmentObject private var automationStore: AutomationStore
    @StateObject private var shortcutStore = FileShareShortcutStore()''',
    '''struct FileSharingView: View {
    @EnvironmentObject private var automationStore: AutomationStore
    @EnvironmentObject private var emailStore: EmailAutomationStore
    @StateObject private var shortcutStore = FileShareShortcutStore()'''
)
replace_once(
    files,
    '''    @State private var showSentConfirmation = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private var gmailRecord: GmailConnectionRecord? {
        GmailConnectionStore.shared.load()
    }''',
    '''    @State private var showSentConfirmation = false
    @State private var isConnectingGmail = false
    @State private var gmailRecord: GmailConnectionRecord? = GmailConnectionStore.shared.load()

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]'''
)
replace_once(
    files,
    '''        .onChange(of: selectedPhotos) { items in
            importPhotos(items)
        }
        .alert("Email Sent", isPresented: $showSentConfirmation) {''',
    '''        .onChange(of: selectedPhotos) { items in
            importPhotos(items)
        }
        .onAppear {
            gmailRecord = GmailConnectionStore.shared.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextGmailConnectionInvalidated)) { _ in
            gmailRecord = nil
        }
        .alert("Email Sent", isPresented: $showSentConfirmation) {'''
)
regex_once(
    files,
    r'''    private var connectionCard: some View \{.*?\n    \}\n\n    private var recipientShortcuts:''',
    '''    private var connectionCard: some View {
        let connected = gmailRecord != nil && automationStore.cloudConfiguration.isConfigured
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 13) {
                Image(systemName: connected ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(connected ? Color.green : Color.orange)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(connected ? "Gmail file sharing ready" : "Gmail connection required")
                        .font(.headline)
                    Text(gmailRecord?.emailAddress ?? "Connect Gmail to send attachments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if gmailRecord == nil {
                Button {
                    connectGmail()
                } label: {
                    HStack(spacing: 10) {
                        if isConnectingGmail { ProgressView().tint(.white) }
                        Image(systemName: "envelope.badge.fill")
                        Text(isConnectingGmail ? "Connecting Gmail…" : "Connect Gmail Account")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .foregroundStyle(.white)
                    .padding(13)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isConnectingGmail || !automationStore.cloudConfiguration.isConfigured)
            }
        }
        .padding(14)
        .nextCard()
    }

    private var recipientShortcuts:'''
)
replace_once(
    files,
    '''            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resetDraft() {''',
    '''            } catch FileShareError.connectorExpired {
                GmailConnectionStore.shared.invalidate(connectorID: gmail.connectorID)
                gmailRecord = nil
                errorMessage = FileShareError.connectorExpired.localizedDescription
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func connectGmail() {
        guard automationStore.cloudConfiguration.isConfigured else {
            errorMessage = FileShareError.schedulerNotConfigured.localizedDescription
            return
        }

        isConnectingGmail = true
        Task {
            defer { isConnectingGmail = false }
            do {
                let connected = try await GmailOAuthClient.shared.connect()
                gmailRecord = connected
                var settings = emailStore.settings
                settings.enabled = true
                settings.deliveryMethod = .gmailAutomatic
                settings.remoteConnectorID = connected.connectorID
                settings.senderLabel = connected.emailAddress
                emailStore.save(settings)
                statusMessage = "Gmail connected successfully."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resetDraft() {'''
)

# MARK: - Quick extensions from the first/original due date and time.
actions = SOURCES / "CompletedFilterActions.swift"
replace_once(
    actions,
    '''        let base = max(reminder.dueDate, Date())
        _newDate = State(initialValue: base.addingTimeInterval(3600))''',
    '''        let base = Self.originalDueDate(for: reminder)
        _newDate = State(initialValue: base.addingTimeInterval(3600))'''
)
replace_once(
    actions,
    '''                    Text("Extend from the reminder time using a quick option or choose a custom date and time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)''',
    '''                    Text("Quick options always use the reminder's first/original due date and time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Original due: \(originalDueDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption.bold())
                        .foregroundStyle(.nextOrange)'''
)
replace_once(
    actions,
    '''                        Text("Quick options are added to the existing reminder time. If the reminder is already overdue, they are added from the current time.")''',
    '''                        Text("+1 Hour, +2 Hours, and +1 Day are calculated from the first due time, even after the reminder has already been extended.")'''
)
replace_once(
    actions,
    '''    private func quickButton(title: String, seconds: TimeInterval) -> some View {
        Button {
            let base = max(reminder.dueDate, Date())
            newDate = base.addingTimeInterval(seconds)''',
    '''    private static func originalDueDate(for reminder: ReminderItem) -> Date {
        reminder.history
            .filter { $0.action == .extended && $0.previousDueDate != nil }
            .sorted { $0.date < $1.date }
            .first?.previousDueDate ?? reminder.dueDate
    }

    private var originalDueDate: Date {
        Self.originalDueDate(for: reminder)
    }

    private func quickButton(title: String, seconds: TimeInterval) -> some View {
        Button {
            newDate = originalDueDate.addingTimeInterval(seconds)'''
)

# MARK: - Version metadata and clients.
project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.2.3"', 'CFBundleShortVersionString: "1.2.4"')
project_text = project_text.replace('CFBundleVersion: "7"', 'CFBundleVersion: "8"')
project_text = project_text.replace('MARKETING_VERSION: "1.2.3"', 'MARKETING_VERSION: "1.2.4"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "7"', 'CURRENT_PROJECT_VERSION: "8"')
project.write_text(project_text)

settings = SOURCES / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.2.3 • iOS 16.0+", "Version 1.2.4 • iOS 16.0+"))

for name in ["EmailAutomationCore.swift", "GmailConnection.swift", "FileSharing.swift"]:
    path = SOURCES / name
    text = path.read_text().replace("NextReminder-iOS/1.2.3", "NextReminder-iOS/1.2.4")
    text = text.replace("NextReminder-iOS/1.2", "NextReminder-iOS/1.2.4")
    path.write_text(text)

print("Next Reminder v1.2.4 patches applied successfully.")
