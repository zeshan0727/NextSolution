import SwiftUI

struct EmailAutomationSettingsView: View {
    @EnvironmentObject private var emailStore: EmailAutomationStore
    @EnvironmentObject private var automationStore: AutomationStore
    @EnvironmentObject private var reminderStore: ReminderStore

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
            Text("Each reminder can independently choose whether an email should be prepared or sent at its reminder time.")
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
                    Image(
                        systemName: automationStore.cloudConfiguration.isConfigured
                            ? "checkmark.shield.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    Text(
                        automationStore.cloudConfiguration.isConfigured
                            ? "Scheduler connected"
                            : "Configure the HTTPS scheduler in Automation Connections"
                    )
                }
                .font(.caption.bold())
                .foregroundStyle(
                    automationStore.cloudConfiguration.isConfigured ? Color.green : Color.orange
                )

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
                saveAndReschedule()
            }
            .buttonStyle(OrangeActionButtonStyle())
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.5)

            Button {
                Task { await emailStore.test(draft) }
            } label: {
                Label(
                    emailStore.isTesting ? "Testing…" : "Test Configuration",
                    systemImage: "paperplane.circle.fill"
                )
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

    private func saveAndReschedule() {
        emailStore.save(draft)
        let reminders = reminderStore.pendingReminders
        Task {
            for reminder in reminders {
                await EmailAutomationManager.shared.sync(reminder)
            }
        }
    }
}
