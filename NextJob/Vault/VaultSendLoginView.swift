import SwiftUI
import UniformTypeIdentifiers

struct VaultSendLoginView: View {
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var jobStore: JobStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var emailConfiguration = EmailConfigurationStore.shared

    let entryID: UUID

    @State private var recipient = ""
    @State private var subject = ""
    @State private var includeAttachments = true
    @State private var showingConfirmation = false
    @State private var isSending = false
    @State private var noticeTitle = ""
    @State private var noticeMessage = ""
    @State private var showingNotice = false

    private var entry: VaultEntry? { vaultStore.entry(id: entryID) }

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    connectionSection
                    emailSection
                    detailsSection
                    attachmentsSection
                    securitySection
                }

                if isSending {
                    Color.black.opacity(0.22).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Sending login details and attachments through Gmail…")
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(30)
                }
            }
            .navigationTitle("Send Login Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review & Send") { showingConfirmation = true }
                        .disabled(isSending || entry == nil || !emailConfiguration.isGmailConnected)
                }
            }
            .onAppear {
                if recipient.isEmpty {
                    recipient = jobStore.settings.companyEmail
                }
                if subject.isEmpty, let entry {
                    subject = "Login Details – \(entry.service)"
                }
            }
            .confirmationDialog(
                "Send Login Details Separately?",
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Send Now") { send() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
            .alert(noticeTitle, isPresented: $showingNotice) {
                Button("OK", role: .cancel) {
                    if noticeTitle == "Login Details Accepted" { dismiss() }
                }
            } message: {
                Text(noticeMessage)
            }
        }
    }

    private var connectionSection: some View {
        Section("Gmail Connection") {
            Label(
                emailConfiguration.isGmailConnected
                    ? "Automatic Gmail ready: \(emailConfiguration.configuration.connectedEmail)"
                    : "Connect Gmail in Settings before sending",
                systemImage: emailConfiguration.isGmailConnected
                    ? "checkmark.shield.fill"
                    : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(emailConfiguration.isGmailConnected ? .green : .orange)
        }
    }

    private var emailSection: some View {
        Section("Email") {
            TextField("Recipient email", text: $recipient)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Subject", text: $subject)
        }
    }

    private var detailsSection: some View {
        Section("Login Details Included") {
            if let entry {
                LabeledContent("Client Name", value: entry.service)
                LabeledContent("Website", value: entry.website.isEmpty ? "Not entered" : entry.website)
                LabeledContent("Login / User ID", value: entry.userID.isEmpty ? "Not entered" : entry.userID)
                LabeledContent("Category", value: entry.displayCategory)
                LabeledContent("Job Reference", value: connectedJobText(entry))
                Text("The Keychain password will be included only after device authentication when you tap Send Now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var attachmentsSection: some View {
        Section("Login Attachments") {
            if let entry {
                Toggle("Include all \(entry.attachments.count) attachments", isOn: $includeAttachments)
                    .disabled(entry.attachments.isEmpty)
                if entry.attachments.isEmpty {
                    Text("No login attachments are saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entry.attachments) { attachment in
                        Label("\(attachment.originalName) • \(attachment.formattedSize)", systemImage: "paperclip")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var securitySection: some View {
        Section {
            Text("This is a separate Secure Logins email. It is not combined with document requests, completion packages or any connected job email history.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var confirmationMessage: String {
        guard let entry else { return "The login is no longer available." }
        let attachmentText = includeAttachments && !entry.attachments.isEmpty
            ? "\(entry.attachments.count) login attachments will be included."
            : "No attachments will be included."
        return "To: \(recipient)\nSubject: \(subject)\n\nThe login ID and password will be sent. \(attachmentText) This email remains separate from all job emails."
    }

    private func connectedJobText(_ entry: VaultEntry) -> String {
        if let linkedJobID = entry.linkedJobID,
           let job = jobStore.job(id: linkedJobID) {
            let client = job.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
            return client.isEmpty ? job.title : "\(job.title) — \(client)"
        }
        let manual = (entry.manualJobReference ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return manual.isEmpty ? "Not connected" : manual
    }

    private func send() {
        guard !isSending, let entry else { return }
        let cleanedRecipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard emailConfiguration.isGmailConnected else {
            showNotice("Gmail Connection Required", "Open Settings → Email & Gmail Setup and connect Gmail before sending login details.")
            return
        }
        guard DirectEmailService.isValidEmail(cleanedRecipient) else {
            showNotice("Invalid Recipient", "Enter a valid recipient email address.")
            return
        }
        guard !cleanedSubject.isEmpty else {
            showNotice("Subject Required", "Enter an email subject before sending.")
            return
        }

        isSending = true
        Task {
            defer { isSending = false }
            guard await VaultSecurity.authenticate(reason: "Authenticate to send the saved login details and password for \(entry.service).") else {
                showNotice("Authentication Required", "The login details were not sent.")
                return
            }

            let password = vaultStore.password(for: entry.id)
            guard !password.isEmpty else {
                showNotice("Password Missing", "No Keychain password is available for this login.")
                return
            }

            do {
                let attachments = try makeAttachments(for: entry)
                let schedulerMessage = try await DirectEmailService().send(
                    recipient: cleanedRecipient,
                    subject: cleanedSubject,
                    body: emailBody(entry: entry, password: password),
                    attachments: attachments,
                    using: emailConfiguration
                )
                showNotice(
                    "Login Details Accepted",
                    "The scheduler accepted this separate login-details email for \(cleanedRecipient).\n\n\(schedulerMessage)"
                )
            } catch {
                showNotice("Login Details Not Sent", error.localizedDescription)
            }
        }
    }

    private func emailBody(entry: VaultEntry, password: String) -> String {
        let website = entry.website.trimmingCharacters(in: .whitespacesAndNewlines)
        let userID = entry.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Dear Team,

        Please find the login details below.

        Client Name: \(entry.service)
        Website: \(website.isEmpty ? "Not entered" : website)
        Login / User ID: \(userID.isEmpty ? "Not entered" : userID)
        Password: \(password)
        Category: \(entry.displayCategory)
        Connected Job / Reference: \(connectedJobText(entry))
        Date Added: \(entry.createdAt.formatted(date: .long, time: .shortened))

        Notes:
        \(notes.isEmpty ? "No additional notes." : notes)

        This message was sent separately from all job document and completion emails.

        \(emailConfiguration.configuration.signature)
        """
    }

    private func makeAttachments(for entry: VaultEntry) throws -> [DirectEmailAttachment] {
        guard includeAttachments else { return [] }
        return try entry.attachments.map { attachment in
            let url = vaultStore.attachmentURL(attachment, entryID: entry.id)
            return DirectEmailAttachment(
                fileName: attachment.originalName,
                mimeType: mimeType(for: url),
                data: try Data(contentsOf: url, options: .mappedIfSafe)
            )
        }
    }

    private func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    private func showNotice(_ title: String, _ message: String) {
        noticeTitle = title
        noticeMessage = message
        showingNotice = true
    }
}
