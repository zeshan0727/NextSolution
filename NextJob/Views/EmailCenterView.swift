import MessageUI
import SwiftUI

struct EmailCenterView: View {
    @EnvironmentObject private var store: JobStore
    @EnvironmentObject private var draftStore: EmailDraftStore
    @StateObject private var emailConfiguration = EmailConfigurationStore.shared

    @State private var selectedJobID: UUID?
    @State private var deliveryMode: EmailDeliveryMode = .gmailDirect
    @State private var isSending = false
    @State private var mailDraft: MailDraft?
    @State private var sharePayload: SharePayload?
    @State private var noticeTitle = ""
    @State private var noticeMessage = ""
    @State private var showingNotice = false

    private var selectedJob: JobRecord? {
        guard let selectedJobID else { return nil }
        return store.job(id: selectedJobID)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                if store.jobs.isEmpty {
                    EmptyStateView(
                        title: "No jobs available",
                        message: "Create a job before preparing an email.",
                        systemImage: "envelope.badge"
                    )
                    .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            connectionCard
                            jobCard
                            messageCard
                            deliveryCard
                            sendButton
                        }
                        .padding()
                        .padding(.bottom, 24)
                    }
                }

                if isSending {
                    Color.black.opacity(0.22).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Preparing and sending email…")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .navigationTitle("Email")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        EmailSetupView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Email setup")
                }
            }
            .onAppear(perform: prepareInitialDraft)
            .onChange(of: selectedJobID) { _ in refreshDraft(force: true) }
            .onChange(of: draftStore.purpose) { _ in refreshDraft(force: true) }
            .sheet(item: $mailDraft) { draft in
                MailComposer(draft: draft) { result in
                    if result == .sent, let job = selectedJob {
                        store.addEmailRecord(
                            JobEmailRecord(
                                kind: draftStore.purpose.recordKind,
                                recipient: draft.recipients.first ?? "",
                                subject: draft.subject
                            ),
                            to: job.id
                        )
                        showNotice("Email Sent", "The email was sent from Apple Mail.")
                    }
                    mailDraft = nil
                }
            }
            .sheet(item: $sharePayload) { payload in
                ShareSheet(items: payload.items)
            }
            .alert(noticeTitle, isPresented: $showingNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(noticeMessage)
            }
        }
    }

    private var connectionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: emailConfiguration.isGmailConnected ? "checkmark.shield.fill" : "envelope.badge")
                .font(.title2)
                .foregroundStyle(emailConfiguration.isGmailConnected ? .green : .orange)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(emailConfiguration.isGmailConnected ? "Gmail direct sending ready" : "Apple Mail assisted sending available")
                    .font(.headline)
                Text(emailConfiguration.configuration.connectedEmail.isEmpty
                     ? "Open Email Setup to connect Gmail"
                     : emailConfiguration.configuration.connectedEmail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .glassCard()
    }

    private var jobCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionTitle(title: "Job & Email Type", systemImage: "briefcase.fill")

            Picker("Job", selection: $selectedJobID) {
                ForEach(store.sortedJobs) { job in
                    Text("\(job.title) • \(job.status.title)").tag(Optional(job.id))
                }
            }
            .pickerStyle(.menu)

            Picker("Email purpose", selection: $draftStore.purpose) {
                ForEach(JobEmailPurpose.allCases) { purpose in
                    Text(purpose.title).tag(purpose)
                }
            }
            .pickerStyle(.menu)

            if let job = selectedJob {
                HStack {
                    StatusBadge(status: job.status, overdue: job.isOverdue)
                    Spacer()
                    Text("Due \(job.dueDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .glassCard()
    }

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title: "Message", systemImage: "envelope.fill")
                Spacer()
                if draftStore.hasAIDraft {
                    Label("AI Draft", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                }
            }

            TextField("Recipient email", text: $draftStore.recipient)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

            TextField("Subject", text: $draftStore.subject)
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

            TextEditor(text: $draftStore.body)
                .frame(minHeight: 190)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Toggle("Attach completion ZIP package", isOn: $draftStore.attachCompletionPackage)

            Button {
                refreshDraft(force: true)
            } label: {
                Label("Reset from Job Details", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
        }
        .glassCard()
    }

    private var deliveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Delivery", systemImage: "paperplane.fill")
            Picker("Sending method", selection: $deliveryMode) {
                ForEach(EmailDeliveryMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(deliveryMode == .gmailDirect
                 ? "Sends immediately through the Gmail connection used by Next Reminder."
                 : "Opens Apple Mail so you can review the email before tapping Send.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private var sendButton: some View {
        Button {
            sendEmail()
        } label: {
            Label(
                deliveryMode == .gmailDirect ? "Send with Gmail" : "Open in Apple Mail",
                systemImage: "paperplane.fill"
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isSending || selectedJob == nil)
    }

    private func prepareInitialDraft() {
        deliveryMode = emailConfiguration.configuration.preferredMode
        if let existingID = draftStore.selectedJobID, store.job(id: existingID) != nil {
            selectedJobID = existingID
            if draftStore.subject.isEmpty || draftStore.body.isEmpty {
                refreshDraft(force: true)
            }
        } else {
            selectedJobID = store.sortedJobs.first?.id
            refreshDraft(force: true)
        }
    }

    private func refreshDraft(force: Bool) {
        guard let job = selectedJob else { return }
        draftStore.load(
            job: job,
            purpose: draftStore.purpose,
            recipient: draftStore.recipient.isEmpty ? store.settings.companyEmail : draftStore.recipient,
            signature: emailConfiguration.configuration.signature,
            force: force
        )
    }

    private func sendEmail() {
        guard let job = selectedJob else { return }
        let recipient = draftStore.recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DirectEmailService.isValidEmail(recipient) else {
            showNotice("Recipient Needed", "Enter a valid email address before sending.")
            return
        }
        guard !draftStore.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draftStore.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showNotice("Email Incomplete", "Add a subject and message before sending.")
            return
        }

        isSending = true
        Task {
            defer { isSending = false }
            do {
                let package = try await preparePackage(for: job)
                switch deliveryMode {
                case .gmailDirect:
                    var attachments: [DirectEmailAttachment] = []
                    if let package {
                        attachments.append(
                            DirectEmailAttachment(
                                fileName: package.lastPathComponent,
                                mimeType: "application/zip",
                                data: try Data(contentsOf: package, options: .mappedIfSafe)
                            )
                        )
                    }
                    let message = try await DirectEmailService().send(
                        recipient: recipient,
                        subject: draftStore.subject,
                        body: draftStore.body,
                        attachments: attachments,
                        using: emailConfiguration
                    )
                    store.addEmailRecord(
                        JobEmailRecord(
                            kind: draftStore.purpose.recordKind,
                            recipient: recipient,
                            subject: draftStore.subject
                        ),
                        to: job.id
                    )
                    showNotice("Email Sent", message)

                case .appleMail:
                    var attachments: [MailAttachment] = []
                    if let package {
                        attachments.append(
                            MailAttachment(
                                data: try Data(contentsOf: package, options: .mappedIfSafe),
                                mimeType: "application/zip",
                                fileName: package.lastPathComponent
                            )
                        )
                    }
                    if MFMailComposeViewController.canSendMail() {
                        mailDraft = MailDraft(
                            recipients: [recipient],
                            subject: draftStore.subject,
                            body: draftStore.body,
                            attachments: attachments,
                            kind: draftStore.purpose.recordKind
                        )
                    } else {
                        var items: [Any] = [draftStore.subject, draftStore.body]
                        if let package { items.insert(package, at: 0) }
                        sharePayload = SharePayload(items: items)
                        showNotice(
                            "Apple Mail Not Configured",
                            "The email text and package are ready in the share sheet."
                        )
                    }
                }
            } catch {
                showNotice("Email Could Not Be Prepared", error.localizedDescription)
            }
        }
    }

    private func preparePackage(for job: JobRecord) async throws -> URL? {
        guard draftStore.attachCompletionPackage else { return nil }
        let currency = store.settings.currency
        return try await Task.detached(priority: .userInitiated) {
            try JobFileService.shared.createJobZip(job: job, currency: currency)
        }.value
    }

    private func showNotice(_ title: String, _ message: String) {
        noticeTitle = title
        noticeMessage = message
        showingNotice = true
    }
}
