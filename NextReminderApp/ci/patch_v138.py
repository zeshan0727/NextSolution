#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:280]!r}")
    path.write_text(text.replace(old, new, 1))


gmail = SOURCES / "GmailConnection.swift"
replace_once(gmail, "import UIKit\n", "import UIKit\nimport UserNotifications\n")

replace_once(
    gmail,
    '''final class GmailConnectionStore {''',
    '''struct GmailConnectionIssue: Codable, Equatable {
    var emailAddress: String
    var message: String
    var detectedAt: Date
}

final class GmailConnectionIssueStore {
    static let shared = GmailConnectionIssueStore()
    private let key = "NextReminder.GmailConnectionIssue.v1"
    private init() {}

    func load() -> GmailConnectionIssue? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GmailConnectionIssue.self, from: data)
    }

    func save(_ issue: GmailConnectionIssue) {
        guard let data = try? JSONEncoder().encode(issue) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

final class GmailConnectionAlertManager {
    static let shared = GmailConnectionAlertManager()
    static let categoryIdentifier = "NEXT_GMAIL_CONNECTION_ALERT"
    static let reconnectActionIdentifier = "NEXT_GMAIL_RECONNECT"
    private let notificationIdentifier = "gmail-connection-disconnected"
    private let center = UNUserNotificationCenter.current()
    private init() {}

    func installCategory() {
        let reconnect = UNNotificationAction(
            identifier: Self.reconnectActionIdentifier,
            title: "Reconnect Gmail",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [reconnect],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        Task {
            var categories = await center.notificationCategories()
            categories.update(with: category)
            center.setNotificationCategories(categories)
        }
    }

    func notifyDisconnected(issue: GmailConnectionIssue) async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        let content = UNMutableNotificationContent()
        content.title = "Gmail disconnected"
        content.subtitle = issue.emailAddress.isEmpty ? "Next Reminder email automation" : issue.emailAddress
        content.body = "Automatic Gmail sending has stopped. Open Next Reminder and reconnect Gmail. \(issue.message)"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = Self.categoryIdentifier
        content.threadIdentifier = "gmail-connection-health"
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["gmailConnectionAlert": true]

        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await center.add(request)
    }

    func clearAlert() async {
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
        await MainActor.run {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }
}

enum GmailConnectionHealthResult {
    case connected
    case disconnected(String)
}

final class GmailConnectionStore {'''
)

replace_once(
    gmail,
    '''    func save(_ record: GmailConnectionRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func clear() {
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
    }''',
    '''    func save(_ record: GmailConnectionRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: key)
        GmailConnectionIssueStore.shared.clear()
        Task { await GmailConnectionAlertManager.shared.clearAlert() }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        GmailConnectionIssueStore.shared.clear()
        Task { await GmailConnectionAlertManager.shared.clearAlert() }
    }

    static func isDisconnectionMessage(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("gmail connector not found")
            || lowered.contains("reconnect gmail")
            || lowered.contains("reconnect the gmail account")
            || lowered.contains("invalid_grant")
            || lowered.contains("token has been expired or revoked")
            || lowered.contains("gmail authorization is no longer valid")
            || lowered.contains("gmail credentials are no longer valid")
            || lowered.contains("unauthorized_client")
    }

    func invalidate(
        connectorID: String? = nil,
        reason: String = "The saved Gmail connection is no longer valid."
    ) {
        let current = load()
        var settings = EmailAutomationSettings.load()
        let savedConnectorID = current?.connectorID
            ?? settings.remoteConnectorID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !savedConnectorID.isEmpty else { return }
        if let connectorID, connectorID != savedConnectorID { return }

        UserDefaults.standard.removeObject(forKey: key)
        let emailAddress = current?.emailAddress ?? settings.senderLabel
        settings.remoteConnectorID = ""
        settings.senderLabel = ""
        settings.persist()

        let issue = GmailConnectionIssue(
            emailAddress: emailAddress,
            message: reason,
            detectedAt: Date()
        )
        GmailConnectionIssueStore.shared.save(issue)
        NotificationCenter.default.post(
            name: .nextGmailConnectionInvalidated,
            object: reason
        )
        Task { await GmailConnectionAlertManager.shared.notifyDisconnected(issue: issue) }
    }'''
)

replace_once(
    gmail,
    '''extension Notification.Name {
    static let nextGmailConnectionInvalidated = Notification.Name("NextReminder.GmailConnectionInvalidated")
}''',
    '''extension Notification.Name {
    static let nextGmailConnectionInvalidated = Notification.Name("NextReminder.GmailConnectionInvalidated")
    static let nextGmailReconnectRequested = Notification.Name("NextReminder.GmailReconnectRequested")
}'''
)

replace_once(
    gmail,
    '''private struct GmailStatusResponse: Decodable {
    var connected: Bool?
    var connectorID: String?
    var emailAddress: String?
    var message: String?
}''',
    '''private struct GmailStatusResponse: Decodable {
    var connected: Bool?
    var connectorID: String?
    var emailAddress: String?
    var message: String?
}

private struct GmailConnectionHealthResponse: Decodable {
    var connected: Bool?
    var connectorID: String?
    var emailAddress: String?
    var message: String?
}'''
)

replace_once(
    gmail,
    '''    func disconnect(connectorID: String) async throws {
        var request = try makeRequest(
            path: "v1/connectors/gmail/\(connectorID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? connectorID)",
            method: "DELETE"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        GmailConnectionStore.shared.clear()
    }''',
    '''    func disconnect(connectorID: String) async throws {
        var request = try makeRequest(
            path: "v1/connectors/gmail/\(connectorID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? connectorID)",
            method: "DELETE"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        GmailConnectionStore.shared.clear()
    }

    func connectionHealth(connectorID: String) async throws -> GmailConnectionHealthResult {
        let encoded = connectorID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? connectorID
        let request = try makeRequest(
            path: "v1/connectors/gmail/\(encoded)/status",
            method: "GET"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GmailConnectionError.invalidResponse
        }

        let decoded = try? JSONDecoder().decode(GmailConnectionHealthResponse.self, from: data)
        if (200...299).contains(http.statusCode) {
            if decoded?.connected == true { return .connected }
            return .disconnected(decoded?.message ?? "Gmail is not connected on the scheduler.")
        }

        let message = decoded?.message ?? "Gmail health check failed (\(http.statusCode))."
        if (http.statusCode == 404 || http.statusCode == 409),
           decoded?.connected == false || GmailConnectionStore.isDisconnectionMessage(message) {
            return .disconnected(message)
        }

        throw GmailConnectionError.server(message)
    }'''
)

replace_once(
    gmail,
    '''struct GmailConnectionCard: View {''',
    '''@MainActor
final class GmailConnectionHealthMonitor {
    static let shared = GmailConnectionHealthMonitor()
    private var lastCheckedAt: Date?
    private var isChecking = false
    private init() {}

    func checkNow(force: Bool = false) async {
        guard !isChecking, let record = GmailConnectionStore.shared.load() else { return }
        if !force,
           let lastCheckedAt,
           Date().timeIntervalSince(lastCheckedAt) < 300 {
            return
        }

        isChecking = true
        lastCheckedAt = Date()
        defer { isChecking = false }

        do {
            switch try await GmailOAuthClient.shared.connectionHealth(connectorID: record.connectorID) {
            case .connected:
                break
            case .disconnected(let reason):
                GmailConnectionStore.shared.invalidate(
                    connectorID: record.connectorID,
                    reason: reason
                )
            }
        } catch {
            // Network outages and scheduler availability problems are not treated
            // as Gmail disconnections. The next foreground check will retry.
        }
    }
}

struct GmailConnectionCard: View {'''
)

replace_once(
    gmail,
    '''        .onReceive(NotificationCenter.default.publisher(for: .nextGmailConnectionInvalidated)) { _ in
            record = nil
            draft.remoteConnectorID = ""
            draft.senderLabel = ""
            errorMessage = "The saved Gmail connector no longer exists on the scheduler. Connect Gmail again."
        }''',
    '''        .onReceive(NotificationCenter.default.publisher(for: .nextGmailConnectionInvalidated)) { notification in
            record = nil
            draft.remoteConnectorID = ""
            draft.senderLabel = ""
            errorMessage = (notification.object as? String)
                ?? "The saved Gmail connection is no longer valid. Connect Gmail again."
        }'''
)

email_core = SOURCES / "EmailAutomationCore.swift"
replace_once(
    email_core,
    '''        NotificationCenter.default.publisher(for: .nextEmailAutomationStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.statusMessage = notification.object as? String
            }
            .store(in: &cancellables)

        consumePendingAction()''',
    '''        NotificationCenter.default.publisher(for: .nextEmailAutomationStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.statusMessage = notification.object as? String
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .nextGmailConnectionInvalidated)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.settings = EmailAutomationSettings.load()
                self?.statusMessage = (notification.object as? String)
                    ?? "Gmail disconnected. Reconnect Gmail to resume automatic sending."
            }
            .store(in: &cancellables)

        consumePendingAction()'''
)
replace_once(
    email_core,
    '''            let lowered = message.lowercased()
            if lowered.contains("gmail connector not found")
                || lowered.contains("reconnect gmail")
                || lowered.contains("reconnect the gmail account") {
                GmailConnectionStore.shared.invalidate()
            }''',
    '''            if GmailConnectionStore.isDisconnectionMessage(message) {
                GmailConnectionStore.shared.invalidate(reason: message)
            }'''
)

files = SOURCES / "FileSharing.swift"
replace_once(
    files,
    '''                GmailConnectionStore.shared.invalidate(connectorID: gmail.connectorID)
                gmailRecord = nil''',
    '''                GmailConnectionStore.shared.invalidate(
                    connectorID: gmail.connectorID,
                    reason: FileShareError.connectorExpired.localizedDescription
                )
                gmailRecord = nil'''
)

app = SOURCES / "App.swift"
replace_once(
    app,
    '''        EmailAutomationManager.shared.installCategory()
        return true''',
    '''        EmailAutomationManager.shared.installCategory()
        GmailConnectionAlertManager.shared.installCategory()
        return true'''
)
replace_once(
    app,
    '''        defer { completionHandler() }

        if let raw = response.notification.request.content.userInfo["emailReminderID"] as? String,''',
    '''        defer { completionHandler() }

        if response.notification.request.content.userInfo["gmailConnectionAlert"] as? Bool == true {
            NotificationCenter.default.post(name: .nextGmailReconnectRequested, object: nil)
            return
        }

        if let raw = response.notification.request.content.userInfo["emailReminderID"] as? String,'''
)
replace_once(
    app,
    '''                .tint(.nextOrange)
                .onChange(of: scenePhase) { phase in''',
    '''                .tint(.nextOrange)
                .task {
                    await GmailConnectionHealthMonitor.shared.checkNow(force: true)
                }
                .onChange(of: scenePhase) { phase in'''
)
replace_once(
    app,
    '''                    automationStore.refreshDueStatuses()
                    store.refreshUnattendedBadge()''',
    '''                    automationStore.refreshDueStatuses()
                    store.refreshUnattendedBadge()
                    Task { await GmailConnectionHealthMonitor.shared.checkNow() }'''
)

root = SOURCES / "RootReminders.swift"
replace_once(
    root,
    '''    @State private var openedEmailReminder: IdentifiedReminderID?''',
    '''    @State private var openedEmailReminder: IdentifiedReminderID?
    @State private var gmailDisconnectAlert: String? = GmailConnectionIssueStore.shared.load()?.message'''
)
replace_once(
    root,
    '''        .confirmationDialog(
            "What would you like to create?",''',
    '''        .onReceive(NotificationCenter.default.publisher(for: .nextGmailConnectionInvalidated)) { notification in
            gmailDisconnectAlert = (notification.object as? String)
                ?? GmailConnectionIssueStore.shared.load()?.message
                ?? "Gmail disconnected. Reconnect Gmail to resume automatic sending."
            selectedTab = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextGmailReconnectRequested)) { _ in
            gmailDisconnectAlert = GmailConnectionIssueStore.shared.load()?.message
                ?? "Gmail disconnected. Reconnect Gmail to resume automatic sending."
            selectedTab = .settings
        }
        .alert("Gmail Disconnected", isPresented: Binding(
            get: { gmailDisconnectAlert != nil },
            set: { if !$0 { gmailDisconnectAlert = nil } }
        )) {
            Button("Open Settings") { selectedTab = .settings }
            Button("Dismiss", role: .cancel) { gmailDisconnectAlert = nil }
        } message: {
            Text("\(gmailDisconnectAlert ?? "Gmail connection is unavailable")\n\nOpen Settings → Email Reminder Automations and reconnect Gmail.")
        }
        .confirmationDialog(
            "What would you like to create?",'''
)

project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.3.7"', 'CFBundleShortVersionString: "1.3.8"')
project_text = project_text.replace('CFBundleVersion: "17"', 'CFBundleVersion: "18"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.7"', 'MARKETING_VERSION: "1.3.8"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "17"', 'CURRENT_PROJECT_VERSION: "18"')
project.write_text(project_text)

settings = SOURCES / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.3.7 • iOS 16.0+", "Version 1.3.8 • iOS 16.0+"))

for path in SOURCES.glob("*.swift"):
    path.write_text(path.read_text().replace("NextReminder-iOS/1.3.7", "NextReminder-iOS/1.3.8"))

print("Next Reminder v1.3.8 Gmail disconnect alert patch applied successfully.")
