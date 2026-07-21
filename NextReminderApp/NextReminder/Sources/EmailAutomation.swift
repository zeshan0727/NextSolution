import Combine
import Foundation
import MessageUI
import SwiftUI
import UIKit
import UserNotifications

enum EmailDeliveryMethod: String, Codable, CaseIterable, Identifiable {
    case gmailAutomatic
    case iCloudAutomatic
    case smtpAutomatic
    case appleMailAssisted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gmailAutomatic: return "Gmail — Automatic"
        case .iCloudAutomatic: return "iCloud Mail — Automatic"
        case .smtpAutomatic: return "Other SMTP — Automatic"
        case .appleMailAssisted: return "Apple Mail — Assisted"
        }
    }

    var shortTitle: String {
        switch self {
        case .gmailAutomatic: return "Gmail"
        case .iCloudAutomatic: return "iCloud Mail"
        case .smtpAutomatic: return "SMTP"
        case .appleMailAssisted: return "Apple Mail"
        }
    }

    var symbol: String {
        switch self {
        case .gmailAutomatic: return "envelope.badge.fill"
        case .iCloudAutomatic: return "icloud.fill"
        case .smtpAutomatic: return "server.rack"
        case .appleMailAssisted: return "envelope.open.fill"
        }
    }

    var explanation: String {
        switch self {
        case .gmailAutomatic:
            return "Uses a Gmail OAuth connection on your secure scheduler."
        case .iCloudAutomatic:
            return "Uses an iCloud Mail SMTP connection on your secure scheduler."
        case .smtpAutomatic:
            return "Uses another SMTP provider connected to your secure scheduler."
        case .appleMailAssisted:
            return "Opens a prepared message in Apple Mail at reminder time; you approve Send."
        }
    }

    var isAutomatic: Bool { self != .appleMailAssisted }

    var providerKey: String {
        switch self {
        case .gmailAutomatic: return "gmail"
        case .iCloudAutomatic: return "icloud"
        case .smtpAutomatic: return "smtp"
        case .appleMailAssisted: return "apple_mail"
        }
    }
}

struct EmailAutomationSettings: Codable, Equatable {
    static let defaultsKey = "NextReminder.EmailAutomationSettings.v1"

    var enabled: Bool = false
    var recipient: String = ""
    var deliveryMethod: EmailDeliveryMethod = .appleMailAssisted
    var senderLabel: String = ""
    var remoteConnectorID: String = ""
    var subjectTemplate: String = "Reminder: {title}"
    var bodyTemplate: String = "Hello,\n\nThis is a reminder for: {title}\nReminder time: {date} {time}\nDeadline: {deadline}\n\n{notes}\n\nThank you."

    var hasValidRecipient: Bool {
        let value = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = value.firstIndex(of: "@") else { return false }
        return value[value.index(after: at)...].contains(".")
    }

    var automaticConnectorReady: Bool {
        !deliveryMethod.isAutomatic || !remoteConnectorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func load() -> EmailAutomationSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(EmailAutomationSettings.self, from: data) else {
            return EmailAutomationSettings()
        }
        return value
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

struct PendingEmailAutomationAction: Codable {
    var reminderID: UUID
}

extension Notification.Name {
    static let nextEmailAutomationAction = Notification.Name("nextEmailAutomationAction")
    static let nextEmailAutomationStatus = Notification.Name("nextEmailAutomationStatus")
}

final class EmailAutomationActionCoordinator {
    static let shared = EmailAutomationActionCoordinator()
    private let defaultsKey = "NextReminder.PendingEmailAutomationAction"
    private init() {}

    func store(reminderID: UUID) {
        let action = PendingEmailAutomationAction(reminderID: reminderID)
        if let data = try? JSONEncoder().encode(action) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        NotificationCenter.default.post(name: .nextEmailAutomationAction, object: nil)
    }

    func consume() -> PendingEmailAutomationAction? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let action = try? JSONDecoder().decode(PendingEmailAutomationAction.self, from: data) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        return action
    }
}

@MainActor
final class EmailAutomationStore: ObservableObject {
    @Published var settings: EmailAutomationSettings
    @Published var requestedReminderID: UUID?
    @Published var statusMessage: String?
    @Published var isTesting = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        settings = EmailAutomationSettings.load()
        NotificationCenter.default.publisher(for: .nextEmailAutomationAction)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.consumePendingAction() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .nextEmailAutomationStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.statusMessage = notification.object as? String
            }
            .store(in: &cancellables)
        consumePendingAction()
    }

    func save(_ value: EmailAutomationSettings) {
        settings = value
        settings.recipient = settings.recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.senderLabel = settings.senderLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.remoteConnectorID = settings.remoteConnectorID.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.persist()
        statusMessage = "Email automation settings saved."
    }

    func test(_ value: EmailAutomationSettings) async {
        isTesting = true
        defer { isTesting = false }
        do {
            statusMessage = try await EmailAutomationManager.shared.sendTest(using: value)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clearRequestedReminder() {
        requestedReminderID = nil
    }

    private func consumePendingAction() {
        guard let action = EmailAutomationActionCoordinator.shared.consume() else { return }
        requestedReminderID = action.reminderID
    }
}

enum EmailAutomationError: LocalizedError {
    case invalidRecipient
    case missingConnector
    case schedulerNotConfigured
    case invalidEndpoint
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidRecipient: return "Enter a valid fixed recipient email address."
        case .missingConnector: return "Enter the remote Gmail, iCloud, or SMTP connector ID."
        case .schedulerNotConfigured: return "Configure the HTTPS automation scheduler first."
        case .invalidEndpoint: return "The scheduler URL must be a valid HTTPS address."
        case .invalidResponse: return "The email scheduler returned an invalid response."
        case .server(let message): return message
        }
    }
}

final class EmailAutomationManager {
    static let shared = EmailAutomationManager()
    static let categoryIdentifier = "NEXT_EMAIL_REMINDER_CATEGORY"
    static let composeActionIdentifier = "NEXT_EMAIL_REMINDER_COMPOSE"

    private let center = UNUserNotificationCenter.current()
    private let schedulerEndpointKey = "NextReminder.AutomationCloudEndpoint"
    private init() {}

    func installCategory() {
        let compose = UNNotificationAction(
            identifier: Self.composeActionIdentifier,
            title: "Compose Email",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [compose],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        Task {
            var categories = await center.notificationCategories()
            categories.update(with: category)
            center.setNotificationCategories(categories)
        }
    }

    func sync(_ reminder: ReminderItem) async {
        let settings = EmailAutomationSettings.load()
        await cancelLocal(reminderID: reminder.id)

        guard reminder.emailWhenDue,
              !reminder.isCompleted,
              settings.enabled,
              settings.hasValidRecipient else {
            await cancelRemote(reminderID: reminder.id)
            return
        }

        if settings.deliveryMethod.isAutomatic {
            do {
                try await submit(reminder: reminder, settings: settings, testOnly: false)
                postStatus("Email automation scheduled for \(reminder.title).")
            } catch {
                postStatus(error.localizedDescription)
            }
        } else {
            await scheduleAssisted(reminder: reminder, settings: settings)
        }
    }

    func cancel(reminderID: UUID) async {
        await cancelLocal(reminderID: reminderID)
        await cancelRemote(reminderID: reminderID)
    }

    func sendTest(using settings: EmailAutomationSettings) async throws -> String {
        guard settings.hasValidRecipient else { throw EmailAutomationError.invalidRecipient }

        if settings.deliveryMethod.isAutomatic {
            let reminder = ReminderItem(
                title: "Next Reminder test email",
                notes: "This is a test of your configured email automation.",
                dueDate: Date().addingTimeInterval(30),
                deadlineDate: Date().addingTimeInterval(3600),
                notificationsEnabled: false,
                emailWhenDue: true
            )
            try await submit(reminder: reminder, settings: settings, testOnly: true)
            return "Test email request accepted by the scheduler."
        }

        return "Apple Mail assisted mode is ready. Enable email on a reminder to test composing."
    }

    private func scheduleAssisted(reminder: ReminderItem, settings: EmailAutomationSettings) async {
        guard reminder.dueDate > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Email reminder: \(reminder.title)"
        content.subtitle = "Prepared for \(settings.recipient)"
        content.body = "Open Next Reminder to review and send the prepared email."
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.threadIdentifier = "email-automations"
        content.interruptionLevel = reminder.priority == .urgent ? .timeSensitive : .active
        content.userInfo = ["emailReminderID": reminder.id.uuidString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reminder.dueDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: localIdentifier(reminder.id),
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
        postStatus("Apple Mail compose alert scheduled for \(reminder.title).")
    }

    private func submit(
        reminder: ReminderItem,
        settings: EmailAutomationSettings,
        testOnly: Bool
    ) async throws {
        guard settings.hasValidRecipient else { throw EmailAutomationError.invalidRecipient }
        guard settings.automaticConnectorReady else { throw EmailAutomationError.missingConnector }
        guard let request = try makeRequest(
            path: testOnly ? "v1/email-reminders/test" : "v1/email-reminders",
            method: "POST"
        ) else {
            throw EmailAutomationError.schedulerNotConfigured
        }

        var mutableRequest = request
        mutableRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        mutableRequest.httpBody = try JSONEncoder().encode(
            EmailSchedulerPayload(
                localID: reminder.id.uuidString,
                recipient: settings.recipient,
                provider: settings.deliveryMethod.providerKey,
                remoteConnectorID: settings.remoteConnectorID,
                senderLabel: settings.senderLabel,
                subject: EmailTemplateRenderer.subject(for: reminder, settings: settings),
                body: EmailTemplateRenderer.body(for: reminder, settings: settings),
                scheduledAt: ISO8601DateFormatter().string(from: testOnly ? Date() : reminder.dueDate),
                timeZone: TimeZone.current.identifier,
                reminderTitle: reminder.title,
                reminderTime: ISO8601DateFormatter().string(from: reminder.dueDate),
                deadline: reminder.deadlineDate.map { ISO8601DateFormatter().string(from: $0) },
                testOnly: testOnly
            )
        )

        let (data, response) = try await URLSession.shared.data(for: mutableRequest)
        try validate(response: response, data: data)
    }

    private func cancelRemote(reminderID: UUID) async {
        guard var request = try? makeRequest(path: "v1/email-reminders/cancel", method: "POST"),
              request != nil else { return }
        request?.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request?.httpBody = try? JSONEncoder().encode(["localID": reminderID.uuidString])
        if let request { _ = try? await URLSession.shared.data(for: request) }
    }

    private func cancelLocal(reminderID: UUID) async {
        let identifier = localIdentifier(reminderID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest? {
        let endpoint = UserDefaults.standard.string(forKey: schedulerEndpointKey) ?? ""
        let apiKey = AutomationKeychain.load()
        guard !endpoint.isEmpty, !apiKey.isEmpty else { return nil }
        guard let baseURL = URL(string: endpoint), baseURL.scheme?.lowercased() == "https" else {
            throw EmailAutomationError.invalidEndpoint
        }
        let normalized = baseURL.absoluteString.hasSuffix("/") ? baseURL : baseURL.appendingPathComponent("")
        guard let url = URL(string: path, relativeTo: normalized)?.absoluteURL else {
            throw EmailAutomationError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("NextReminder-iOS/1.2", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw EmailAutomationError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(EmailSchedulerResponse.self, from: data).message)
                ?? "Email scheduler request failed (\(http.statusCode))."
            throw EmailAutomationError.server(message)
        }
    }

    private func localIdentifier(_ reminderID: UUID) -> String {
        "email-reminder-\(reminderID.uuidString)"
    }

    private func postStatus(_ message: String) {
        NotificationCenter.default.post(name: .nextEmailAutomationStatus, object: message)
    }
}

private struct EmailSchedulerPayload: Encodable {
    var localID: String
    var recipient: String
    var provider: String
    var remoteConnectorID: String
    var senderLabel: String
    var subject: String
    var body: String
    var scheduledAt: String
    var timeZone: String
    var reminderTitle: String
    var reminderTime: String
    var deadline: String?
    var testOnly: Bool
}

private struct EmailSchedulerResponse: Decodable {
    var id: String?
    var message: String?
}

enum EmailTemplateRenderer {
    static func subject(for reminder: ReminderItem, settings: EmailAutomationSettings) -> String {
        render(settings.subjectTemplate, reminder: reminder)
    }

    static func body(for reminder: ReminderItem, settings: EmailAutomationSettings) -> String {
        render(settings.bodyTemplate, reminder: reminder)
    }

    private static func render(_ template: String, reminder: ReminderItem) -> String {
        let deadlineText = reminder.deadlineDate?.formatted(date: .long, time: .shortened) ?? "Not set"
        return template
            .replacingOccurrences(of: "{title}", with: reminder.title)
            .replacingOccurrences(of: "{notes}", with: reminder.notes)
            .replacingOccurrences(of: "{date}", with: reminder.dueDate.formatted(date: .long, time: .omitted))
            .replacingOccurrences(of: "{time}", with: reminder.dueDate.formatted(date: .omitted, time: .shortened))
            .replacingOccurrences(of: "{deadline}", with: deadlineText)
    }
}

struct EmailAutomationSettingsView: View {
    @EnvironmentObject private var emailStore: EmailAutomationStore
    @EnvironmentObject private var automationStore: AutomationStore

    @State private var draft = EmailAutomationSettings()

    private var canSave: Bool {
        !draft.enabled || (draft.hasValidRecipient && draft.automaticConnectorReady)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                enableSection
                recipientSection
                deliverySection
                connectorSection
                templateSection
                actionSection
                informationSection
            }
            .padding(16)
            .padding(.bottom, 30)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("Email Automations")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = emailStore.settings }
    }

    private var enableSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Fixed Recipient Email")
            Toggle("Enable reminder email automation", isOn: $draft.enabled)
                .padding(14)
                .nextCard()
            Text("When enabled, each reminder can independently choose whether an email should be prepared or sent at its reminder time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recipient", trailing: "Editable anytime")
            TextField("name@example.com", text: $draft.recipient)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .padding(14)
                .nextCard()
            if draft.enabled && !draft.recipient.isEmpty && !draft.hasValidRecipient {
                Label("Enter a valid email address.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var deliverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Sending Method")
            ForEach(EmailDeliveryMethod.allCases) { method in
                Button {
                    draft.deliveryMethod = method
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: method.symbol)
                            .foregroundStyle(draft.deliveryMethod == method ? .nextOrange : .secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(method.title).font(.headline)
                            Text(method.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: draft.deliveryMethod == method ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(draft.deliveryMethod == method ? .nextOrange : .secondary)
                    }
                    .padding(14)
                    .nextCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var connectorSection: some View {
        if draft.deliveryMethod.isAutomatic {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Automatic Sender Connection")
                TextField("Sender label, e.g. Work Gmail", text: $draft.senderLabel)
                    .padding(14)
                    .nextCard()
                TextField("Remote connector ID", text: $draft.remoteConnectorID)
                    .textInputAutocapitalization(.never)
                    .padding(14)
                    .nextCard()
                HStack(spacing: 10) {
                    Image(systemName: automationStore.cloudConfiguration.isConfigured ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    Text(automationStore.cloudConfiguration.isConfigured ? "Scheduler connected" : "Configure the HTTPS scheduler in Automation Connections")
                }
                .font(.caption.bold())
                .foregroundStyle(automationStore.cloudConfiguration.isConfigured ? Color.green : Color.orange)
                Text("The connector ID points to a Gmail OAuth, iCloud SMTP, or other SMTP account stored securely on your scheduler. Email passwords are not stored in this app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Email Template")
            TextField("Subject", text: $draft.subjectTemplate)
                .padding(14)
                .nextCard()
            TextEditor(text: $draft.bodyTemplate)
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(10)
                .nextCard()
            Text("Available fields: {title}, {notes}, {date}, {time}, {deadline}")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            Button("Save Email Automation") {
                emailStore.save(draft)
            }
            .buttonStyle(OrangeActionButtonStyle())
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.5)

            Button {
                Task { await emailStore.test(draft) }
            } label: {
                Label(emailStore.isTesting ? "Testing…" : "Test Configuration", systemImage: "paperplane.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(emailStore.isTesting || !canSave || !draft.enabled)

            if let message = emailStore.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var informationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "How It Works")
            informationRow(
                icon: "bolt.horizontal.circle.fill",
                title: "Automatic methods",
                text: "The job is sent to your scheduler immediately. The server sends the email at the selected reminder time."
            )
            informationRow(
                icon: "hand.tap.fill",
                title: "Apple Mail assisted",
                text: "A notification opens a completed draft in Apple Mail. iOS still requires you to approve the final Send action."
            )
        }
    }

    private func informationRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.nextOrange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .nextCard()
    }
}

struct EmailComposeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let reminder: ReminderItem
    let settings: EmailAutomationSettings

    var body: some View {
        if MFMailComposeViewController.canSendMail() {
            MailComposeController(
                recipient: settings.recipient,
                subject: EmailTemplateRenderer.subject(for: reminder, settings: settings),
                body: EmailTemplateRenderer.body(for: reminder, settings: settings)
            )
        } else {
            VStack(spacing: 18) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.nextOrange)
                Text("Apple Mail Is Not Configured")
                    .font(.title3.bold())
                Text("Configure a mail account in iOS Settings, or open the prepared message in another installed mail app.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Open Prepared Email") { openMailURL() }
                    .buttonStyle(OrangeActionButtonStyle())
                Button("Close") { dismiss() }
            }
            .padding(24)
            .background(Color.nextBackground.ignoresSafeArea())
        }
    }

    private func openMailURL() {
        let subject = EmailTemplateRenderer.subject(for: reminder, settings: settings)
        let body = EmailTemplateRenderer.body(for: reminder, settings: settings)
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = settings.recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
        dismiss()
    }
}

private struct MailComposeController: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
        }
    }
}
