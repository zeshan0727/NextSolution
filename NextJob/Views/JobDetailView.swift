import SwiftUI
import MessageUI

struct JobDetailView: View {
    @EnvironmentObject private var store: JobStore
    let jobID: UUID

    @State private var showingEditor = false
    @State private var showingPicker = false
    @State private var pickerKind: AttachmentKind = .related
    @State private var previewItem: PreviewItem?
    @State private var sharePayload: SharePayload?
    @State private var mailDraft: MailDraft?
    @State private var noticeTitle = ""
    @State private var noticeMessage = ""
    @State private var showingNotice = false
    @State private var actualMinutes = 60
    @State private var showingCompletionSheet = false

    private var job: JobRecord? { store.job(id: jobID) }

    var body: some View {
        ZStack {
            AppBackground()
            if let job {
                ScrollView {
                    VStack(spacing: 16) {
                        header(job)
                        actionPanel(job)
                        detailsCard(job)
                        requestedDocumentsCard(job)
                        filesCard(job, kind: .related)
                        filesCard(job, kind: .completedWork)
                        emailPanel(job)
                        historyCard(job)
                    }
                    .padding()
                    .padding(.bottom, 30)
                }
            } else {
                EmptyStateView(title: "Job not found", message: "This job may have been deleted.", systemImage: "exclamationmark.triangle")
                    .padding()
            }
        }
        .navigationTitle(job?.title ?? "Job")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if job != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") { showingEditor = true }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            if let job { JobEditorView(job: job).environmentObject(store) }
        }
        .sheet(isPresented: $showingPicker) {
            DocumentPicker(allowsMultipleSelection: true) { result in
                showingPicker = false
                handleFiles(result)
            }
        }
        .sheet(item: $previewItem) { item in
            QuickLookPreview(url: item.url)
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .sheet(item: $mailDraft) { draft in
            MailComposer(draft: draft) { result in
                if result == .sent {
                    store.addEmailRecord(
                        JobEmailRecord(kind: draft.kind, recipient: draft.recipients.first ?? "", subject: draft.subject),
                        to: jobID
                    )
                }
                mailDraft = nil
            }
        }
        .sheet(isPresented: $showingCompletionSheet) {
            completionSheet
        }
        .alert(noticeTitle, isPresented: $showingNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(noticeMessage)
        }
    }

    private func header(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(job.title)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("\(job.jobType) • \(job.clientName)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(status: job.status, overdue: job.isOverdue)
            }
            HStack {
                Label("Due \(job.dueDate.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
                Spacer()
                Text("\(store.settings.currency) \(job.price, specifier: "%.2f")")
                    .fontWeight(.bold)
            }
            .font(.subheadline)
        }
        .glassCard()
    }

    private func actionPanel(_ job: JobRecord) -> some View {
        HStack(spacing: 10) {
            if job.status == .notStarted {
                actionButton("Start", icon: "play.fill", tint: .blue) {
                    store.setStatus(.inProgress, jobID: job.id)
                }
            }
            if job.status != .completed {
                actionButton("Waiting", icon: "doc.badge.ellipsis", tint: .orange) {
                    store.setStatus(.waitingForDocuments, jobID: job.id)
                }
                actionButton("Complete", icon: "checkmark", tint: .green) {
                    actualMinutes = job.actualMinutes ?? job.targetMinutes
                    showingCompletionSheet = true
                }
            } else {
                actionButton("Reopen", icon: "arrow.uturn.backward", tint: .blue) {
                    store.setStatus(.inProgress, jobID: job.id)
                }
            }
        }
        .glassCard()
    }

    private func actionButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(tint)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func detailsCard(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionTitle(title: "Job Details", systemImage: "list.bullet.rectangle")
            detailRow("Assigned", value: job.assignedDate.formatted(date: .abbreviated, time: .shortened))
            detailRow("Target time", value: job.targetTimeText)
            detailRow("Actual time", value: job.actualTimeText)
            if let completedDate = job.completedDate {
                detailRow("Completed", value: completedDate.formatted(date: .abbreviated, time: .shortened))
            }
            if !job.notes.isEmpty {
                Divider()
                Text(job.notes).font(.subheadline)
            }
            if !job.completionNotes.isEmpty {
                Divider()
                Text("Completion notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(job.completionNotes).font(.subheadline)
            }
        }
        .glassCard()
    }

    private func requestedDocumentsCard(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Documents Required", systemImage: "doc.text.magnifyingglass")
            if job.requestedDocuments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No document request has been written for this job.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(job.requestedDocuments).font(.subheadline)
            }
        }
        .glassCard()
    }

    private func filesCard(_ job: JobRecord, kind: AttachmentKind) -> some View {
        let files = job.attachments.filter { $0.kind == kind }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: kind.title, systemImage: kind == .related ? "paperclip" : "checkmark.doc")
                Button {
                    pickerKind = kind
                    showingPicker = true
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
            if files.isEmpty {
                Text(kind == .related ? "Add source documents, spreadsheets or instructions." : "Upload the completed files you will send back.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(files) { attachment in
                    HStack(spacing: 12) {
                        Image(systemName: "doc.fill").foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.originalName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(attachment.formattedSize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button {
                                previewItem = PreviewItem(url: JobFileService.shared.url(for: attachment, jobID: job.id))
                            } label: {
                                Label("Preview", systemImage: "eye")
                            }
                            Button {
                                sharePayload = SharePayload(items: [JobFileService.shared.url(for: attachment, jobID: job.id)])
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                store.removeAttachment(attachment, from: job.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .glassCard()
    }

    private func emailPanel(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Email & Package", systemImage: "envelope.fill")
            Button {
                requestDocuments(job)
            } label: {
                Label("Request Documents", systemImage: "envelope.badge").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                completeAndEmail(job)
            } label: {
                Label("Create ZIP & Email Completion", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                shareZip(job)
            } label: {
                Label("Create & Share Job ZIP", systemImage: "doc.zipper").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Text("iOS opens the Mail compose screen so you can review the recipient, message and ZIP before tapping Send.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private func historyCard(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Email History", systemImage: "clock.arrow.circlepath")
            if job.emailHistory.isEmpty {
                Text("No sent emails recorded yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(job.emailHistory) { record in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.subject).font(.subheadline.weight(.medium))
                        Text("To: \(record.recipient) • \(record.sentAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .glassCard()
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private var completionSheet: some View {
        NavigationStack {
            Form {
                Section("Actual Time") {
                    Stepper(value: $actualMinutes, in: 0...100_000, step: 15) {
                        LabeledContent("Time spent", value: JobRecord.timeText(minutes: actualMinutes))
                    }
                }
                Section {
                    Text("After completion, upload your finished work and use Create ZIP & Email Completion to send the full package.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Complete Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingCompletionSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Complete") {
                        store.complete(jobID: jobID, actualMinutes: actualMinutes)
                        showingCompletionSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func handleFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            let attachments = try JobFileService.shared.copyFiles(urls, jobID: jobID, kind: pickerKind)
            store.addAttachments(attachments, to: jobID)
        } catch {
            showNotice("Files Not Added", error.localizedDescription)
        }
    }

    private func requestDocuments(_ job: JobRecord) {
        guard let recipient = configuredRecipient() else { return }
        let subject = "Documents Required – \(job.title)"
        let requested = job.requestedDocuments.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = requested.isEmpty ? "Please send the documents and information required to complete this job." : requested
        let body = """
        Hello,

        I am working on the following job:
        \(job.title)

        Please provide the following documents/information:
        \(list)

        Target completion date: \(job.dueDate.formatted(date: .long, time: .shortened))

        Thank you,
        Zeeshan
        """
        guard MFMailComposeViewController.canSendMail() else {
            sharePayload = SharePayload(items: [subject, body])
            showNotice("Mail Not Configured", "The message is ready in the share sheet. Add an account to Apple Mail to send directly from Next Job.")
            return
        }
        mailDraft = MailDraft(recipients: [recipient], subject: subject, body: body, attachments: [], kind: .documentRequest)
    }

    private func completeAndEmail(_ job: JobRecord) {
        guard let recipient = configuredRecipient() else { return }
        do {
            if job.status != .completed {
                store.complete(jobID: job.id, actualMinutes: job.actualMinutes ?? job.targetMinutes)
            }
            let updatedJob = store.job(id: job.id) ?? job
            let zipURL = try JobFileService.shared.createJobZip(job: updatedJob, currency: store.settings.currency)
            let subject = "Completed – \(updatedJob.title)"
            let body = """
            Hello,

            The following job has been completed:
            \(updatedJob.title)

            Job type: \(updatedJob.jobType)
            Completed: \((updatedJob.completedDate ?? Date()).formatted(date: .long, time: .shortened))

            The completed work and supporting files are included in the attached ZIP package.

            Thank you,
            Zeeshan
            """
            guard MFMailComposeViewController.canSendMail() else {
                sharePayload = SharePayload(items: [zipURL, subject, body])
                showNotice("Mail Not Configured", "The ZIP and completion message are ready in the share sheet.")
                return
            }
            let data = try Data(contentsOf: zipURL)
            mailDraft = MailDraft(
                recipients: [recipient],
                subject: subject,
                body: body,
                attachments: [MailAttachment(data: data, mimeType: "application/zip", fileName: zipURL.lastPathComponent)],
                kind: .completion
            )
        } catch {
            showNotice("Package Could Not Be Created", error.localizedDescription)
        }
    }

    private func shareZip(_ job: JobRecord) {
        do {
            sharePayload = SharePayload(items: [try JobFileService.shared.createJobZip(job: job, currency: store.settings.currency)])
        } catch {
            showNotice("ZIP Could Not Be Created", error.localizedDescription)
        }
    }

    private func configuredRecipient() -> String? {
        let email = store.settings.companyEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, email.contains("@") else {
            showNotice("Company Email Needed", "Open Settings and add the email address used for KB Accountants.")
            return nil
        }
        return email
    }

    private func showNotice(_ title: String, _ message: String) {
        noticeTitle = title
        noticeMessage = message
        showingNotice = true
    }
}
