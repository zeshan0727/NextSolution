#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:320]!r}")
    path.write_text(text.replace(old, new, 1))


# MARK: - Immediate email delivery service for any reminder type.
email_core = SOURCES / "EmailAutomationCore.swift"
replace_once(
    email_core,
    '''import UserNotifications''',
    '''import UserNotifications
import UIKit'''
)
replace_once(
    email_core,
    '''    case invalidResponse
    case server(String)''',
    '''    case invalidResponse
    case mailAppUnavailable
    case server(String)'''
)
replace_once(
    email_core,
    '''        case .invalidResponse:
            return "The email scheduler returned an invalid response."
        case .server(let message):''',
    '''        case .invalidResponse:
            return "The email scheduler returned an invalid response."
        case .mailAppUnavailable:
            return "No email app is available to open the prepared message."
        case .server(let message):'''
)
replace_once(
    email_core,
    '''    func sendTest(using settings: EmailAutomationSettings) async throws -> String {''',
    '''    func sendNow(
        reminder: ReminderItem,
        using settings: EmailAutomationSettings
    ) async throws -> String {
        guard settings.hasValidRecipient else {
            throw EmailAutomationError.invalidRecipient
        }

        if settings.deliveryMethod.isAutomatic {
            guard settings.automaticConnectorReady else {
                throw EmailAutomationError.missingConnector
            }

            do {
                // The scheduler test route performs an immediate delivery instead
                // of creating a future scheduled email reminder.
                try await submit(reminder: reminder, settings: settings, testOnly: true)
            } catch {
                let message = error.localizedDescription
                if settings.deliveryMethod == .gmailAutomatic,
                   GmailConnectionStore.isDisconnectionMessage(message) {
                    GmailConnectionStore.shared.invalidate(reason: message)
                }
                throw error
            }

            return "Email sent now to \(settings.recipient) using \(settings.deliveryMethod.shortTitle)."
        }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = settings.recipient
        components.queryItems = [
            URLQueryItem(
                name: "subject",
                value: EmailTemplateRenderer.subject(for: reminder, settings: settings)
            ),
            URLQueryItem(
                name: "body",
                value: EmailTemplateRenderer.body(for: reminder, settings: settings)
            )
        ]

        guard let url = components.url else {
            throw EmailAutomationError.invalidResponse
        }

        let canOpen = await MainActor.run {
            UIApplication.shared.canOpenURL(url)
        }
        guard canOpen else {
            throw EmailAutomationError.mailAppUnavailable
        }

        await MainActor.run {
            UIApplication.shared.open(url)
        }
        return "Prepared email opened for \(settings.recipient). Review it and tap Send."
    }

    func sendTest(using settings: EmailAutomationSettings) async throws -> String {'''
)


# MARK: - Send Email Now button on every reminder review/detail screen.
detail = SOURCES / "Detail.swift"
replace_once(
    detail,
    '''    @State private var showDeleteConfirmation = false''',
    '''    @State private var showDeleteConfirmation = false
    @State private var isSendingEmail = false
    @State private var showEmailSetup = false
    @State private var emailResultMessage: String?'''
)
replace_once(
    detail,
    '''                        actionButtons(reminder)
                        historySection(reminder)''',
    '''                        actionButtons(reminder)
                        emailActionCard(reminder)
                        historySection(reminder)'''
)
replace_once(
    detail,
    '''                .sheet(isPresented: $isExtending) {
                    ExtendReminderView(reminder: reminder)
                        .environmentObject(store)
                }
                .confirmationDialog(''',
    '''                .sheet(isPresented: $isExtending) {
                    ExtendReminderView(reminder: reminder)
                        .environmentObject(store)
                }
                .sheet(isPresented: $showEmailSetup) {
                    NavigationStack {
                        EmailAutomationSettingsView()
                    }
                }
                .alert("Email", isPresented: Binding(
                    get: { emailResultMessage != nil },
                    set: { if !$0 { emailResultMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { emailResultMessage = nil }
                } message: {
                    Text(emailResultMessage ?? "")
                }
                .confirmationDialog('''
)
replace_once(
    detail,
    '''    private func routineSummaryCard(_ reminder: ReminderItem) -> some View {''',
    '''    private func emailActionCard(_ reminder: ReminderItem) -> some View {
        let settings = emailStore.settings
        let destination = settings.hasValidRecipient
            ? "\(settings.deliveryMethod.shortTitle) • \(settings.recipient)"
            : "Email recipient and sender setup required"

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "envelope.arrow.triangle.branch.fill")
                    .font(.title2)
                    .foregroundStyle(.nextOrange)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Send this reminder by email")
                        .font(.headline)
                    Text(destination)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Button {
                sendEmailNow(reminder)
            } label: {
                HStack(spacing: 9) {
                    if isSendingEmail {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(isSendingEmail ? "Sending Email…" : "Send Email Now")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(OrangeActionButtonStyle())
            .disabled(isSendingEmail)

            Text("Available for one-time, completed, repeating and Routine reminders. This does not change the reminder's automatic email setting.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .nextCard()
    }

    private func sendEmailNow(_ reminder: ReminderItem) {
        let settings = emailStore.settings
        let setupReady = settings.hasValidRecipient
            && (!settings.deliveryMethod.isAutomatic || settings.automaticConnectorReady)

        guard setupReady else {
            showEmailSetup = true
            return
        }

        isSendingEmail = true
        Task {
            defer { isSendingEmail = false }
            do {
                emailResultMessage = try await EmailAutomationManager.shared.sendNow(
                    reminder: reminder,
                    using: settings
                )
            } catch {
                emailResultMessage = error.localizedDescription
            }
        }
    }

    private func routineSummaryCard(_ reminder: ReminderItem) -> some View {'''
)


# Version metadata.
project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.3.10"', 'CFBundleShortVersionString: "1.3.11"')
project_text = project_text.replace('CFBundleVersion: "20"', 'CFBundleVersion: "21"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.10"', 'MARKETING_VERSION: "1.3.11"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "20"', 'CURRENT_PROJECT_VERSION: "21"')
project.write_text(project_text)

settings_file = SOURCES / "Settings.swift"
settings_file.write_text(
    settings_file.read_text().replace(
        "Version 1.3.10 • iOS 16.0+",
        "Version 1.3.11 • iOS 16.0+"
    )
)

for path in SOURCES.glob("*.swift"):
    path.write_text(
        path.read_text().replace(
            "NextReminder-iOS/1.3.10",
            "NextReminder-iOS/1.3.11"
        )
    )

print("Next Reminder v1.3.11 send-email-now feature applied successfully.")
