import MessageUI
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

private struct ManualEmailAttachment: Identifiable {
    let id: UUID
    let fileName: String
    let mimeType: String
    let data: Data

    init(id: UUID = UUID(), fileName: String, mimeType: String, data: Data) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}

private enum ManualEmailAttachmentError: LocalizedError {
    case folderNotSupported
    case photoCouldNotBeLoaded
    case attachmentMissing(String)

    var errorDescription: String? {
        switch self {
        case .folderNotSupported:
            return "Select individual files. Folders can be sent by selecting the saved job folder attachment or by using the full ZIP package option."
        case .photoCouldNotBeLoaded:
            return "The selected photo could not be prepared as an email attachment."
        case .attachmentMissing(let name):
            return "The attachment \"\(name)\" could not be found on this iPhone."
        }
    }
}

struct EmailCenterV111: View {
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

    @State private var selectedJobAttachmentIDs: Set<UUID> = []
    @State private var addedAttachments: [ManualEmailAttachment] = []
    @State private var showingFileImporter = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isImportingAttachments = false

    private var selectedJob: JobRecord? {
        guard let selectedJobID else { return nil }
        return store.job(id: selectedJobID)
    }

    private var selectedJobAttachments: [JobAttachment] {
        guard let job = selectedJob else { return [] }
        return job.attachments.filter { selectedJobAttachmentIDs.contains($0.id) }
    }

    private var attachmentCount: Int {
        selectedJobAttachments.count + addedAttachments.count + (draftStore.attachCompletionPackage ? 1 : 0)
    }

    private var estimatedAttachmentBytes: Int64 {
        let stored = selectedJobAttachments.reduce(Int64(0)) { $0 + $1.byteCount }
        let added = addedAttachments.reduce(Int64(0)) { $0 + Int64($1.data.count) }
        return stored + added
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
                            attachmentsCard
                            deliveryCard
                            sendButton
                        }
                        .padding()
                        .padding(.bottom, 24)
                    }
                }

                if isSending || isImportingAttachments {
                    Color.black.opacity(0.22).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text(isSending ? "Preparing and sending email…" : "Preparing selected attachments…")
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
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
            .onChange(of: selectedJobID) { _ in
                selectedJobAttachmentIDs.removeAll()
                refreshDraft(force: true)
            }
            .onChange(of: draftStore.purpose) { _ in refreshDraft(force: true) }
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 20,
                matching: .images
            )
            .onChange(of: selectedPhotoItems) { items in
                importPhotos(items)
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                importFiles(result)
            }
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

            Button {
                refreshDraft(force: true)
            } label: {
                Label("Reset from Job Details", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
        }
        .glassCard()
    }

    private var attachmentsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(title: "Attachments", systemImage: "paperclip")
                Spacer()
                if attachmentCount > 0 {
                    Text("\(attachmentCount) selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Attach full completion ZIP package", isOn: $draftStore.attachCompletionPackage)

            if let job = selectedJob {
                jobAttachmentGroup(
                    title: "Relevant Files",
                    systemImage: "doc.text.fill",
                    attachments: job.relatedFiles,
                    job: job
                )

                jobAttachmentGroup(
                    title: "Completion Files",
                    systemImage: "checkmark.doc.fill",
                    attachments: job.completedFiles,
                    job: job
                )
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Files App", systemImage: "folder.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showingPhotoPicker = true
                } label: {
                    Label("Photos", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .disabled(isImportingAttachments)

            if !addedAttachments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New Attachments")
                        .font(.subheadline.weight(.semibold))

                    ForEach(addedAttachments) { attachment in
                        HStack(spacing: 10) {
                            Image(systemName: attachment.mimeType.hasPrefix("image/") ? "photo.fill" : "doc.fill")
                                .foregroundStyle(attachment.mimeType.hasPrefix("image/") ? .purple : .blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(attachment.fileName)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(attachment.formattedSize)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                addedAttachments.removeAll { $0.id == attachment.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if attachmentCount == 0 {
                Text("Select saved relevant or completion files, or add new files and photos from this iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Selected files: \(ByteCountFormatter.string(fromByteCount: estimatedAttachmentBytes, countStyle: .file)) before any full ZIP package.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !selectedJobAttachmentIDs.isEmpty || !addedAttachments.isEmpty {
                Button(role: .destructive) {
                    selectedJobAttachmentIDs.removeAll()
                    addedAttachments.removeAll()
                } label: {
                    Label("Clear Selected Files", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .glassCard()
    }

    @ViewBuilder
    private func jobAttachmentGroup(
        title: String,
        systemImage: String,
        attachments: [JobAttachment],
        job: JobRecord
    ) -> some View {
        if attachments.isEmpty {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(allSelected(attachments) ? "Clear" : "Select All") {
                        toggleAll(attachments)
                    }
                    .font(.caption.weight(.semibold))
                }

                ForEach(attachments) { attachment in
                    Button {
                        toggleAttachment(attachment)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedJobAttachmentIDs.contains(attachment.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedJobAttachmentIDs.contains(attachment.id) ? Color.blue : Color.secondary)
                            Image(systemName: JobFileService.shared.isFolder(attachment, jobID: job.id) ? "folder.fill" : "doc.fill")
                                .foregroundStyle(JobFileService.shared.isFolder(attachment, jobID: job.id) ? .orange : .blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(attachment.originalName)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(JobFileService.shared.detailText(for: attachment, jobID: job.id))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
                 ? "Sends immediately through Gmail. Each attachment must be under 10 MB and the total must be under 18 MB."
                 : "Opens Apple Mail so you can review the message and all selected attachments before sending.")
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
        .disabled(isSending || isImportingAttachments || selectedJob == nil)
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

    private func toggleAttachment(_ attachment: JobAttachment) {
        if selectedJobAttachmentIDs.contains(attachment.id) {
            selectedJobAttachmentIDs.remove(attachment.id)
        } else {
            selectedJobAttachmentIDs.insert(attachment.id)
        }
    }

    private func allSelected(_ attachments: [JobAttachment]) -> Bool {
        !attachments.isEmpty && attachments.allSatisfy { selectedJobAttachmentIDs.contains($0.id) }
    }

    private func toggleAll(_ attachments: [JobAttachment]) {
        if allSelected(attachments) {
            attachments.forEach { selectedJobAttachmentIDs.remove($0.id) }
        } else {
            attachments.forEach { selectedJobAttachmentIDs.insert($0.id) }
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            isImportingAttachments = true
            Task {
                defer { isImportingAttachments = false }
                for url in urls {
                    do {
                        let attachment = try await loadFileAttachment(from: url)
                        addedAttachments.append(attachment)
                    } catch {
                        showNotice("File Not Added", error.localizedDescription)
                    }
                }
            }
        } catch {
            showNotice("Files Not Added", error.localizedDescription)
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isImportingAttachments = true
        Task {
            defer {
                isImportingAttachments = false
                selectedPhotoItems = []
            }
            for (index, item) in items.enumerated() {
                do {
                    guard let sourceData = try await item.loadTransferable(type: Data.self) else {
                        throw ManualEmailAttachmentError.photoCouldNotBeLoaded
                    }
                    let fileName = "Photo-\(Self.attachmentDateFormatter.string(from: Date()))-\(index + 1).jpg"
                    let attachment = try await Task.detached(priority: .userInitiated) {
                        guard let image = UIImage(data: sourceData),
                              let jpeg = image.jpegData(compressionQuality: 0.88) else {
                            throw ManualEmailAttachmentError.photoCouldNotBeLoaded
                        }
                        return ManualEmailAttachment(fileName: fileName, mimeType: "image/jpeg", data: jpeg)
                    }.value
                    addedAttachments.append(attachment)
                } catch {
                    showNotice("Photo Not Added", error.localizedDescription)
                }
            }
        }
    }

    private func loadFileAttachment(from url: URL) async throws -> ManualEmailAttachment {
        try await Task.detached(priority: .userInitiated) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else {
                throw ManualEmailAttachmentError.folderNotSupported
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return ManualEmailAttachment(
                fileName: url.lastPathComponent.isEmpty ? "Attachment" : url.lastPathComponent,
                mimeType: Self.mimeType(for: url),
                data: data
            )
        }.value
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
                let attachments = try await prepareAttachments(for: job)
                switch deliveryMode {
                case .gmailDirect:
                    let message = try await DirectEmailService().send(
                        recipient: recipient,
                        subject: draftStore.subject,
                        body: draftStore.body,
                        attachments: attachments.map {
                            DirectEmailAttachment(fileName: $0.fileName, mimeType: $0.mimeType, data: $0.data)
                        },
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
                    if MFMailComposeViewController.canSendMail() {
                        mailDraft = MailDraft(
                            recipients: [recipient],
                            subject: draftStore.subject,
                            body: draftStore.body,
                            attachments: attachments.map {
                                MailAttachment(data: $0.data, mimeType: $0.mimeType, fileName: $0.fileName)
                            },
                            kind: draftStore.purpose.recordKind
                        )
                    } else {
                        let fileURLs = try makeShareFiles(from: attachments)
                        sharePayload = SharePayload(items: fileURLs + [draftStore.subject, draftStore.body])
                        showNotice(
                            "Apple Mail Not Configured",
                            "The email text and all selected attachments are ready in the share sheet."
                        )
                    }
                }
            } catch {
                showNotice("Email Could Not Be Prepared", error.localizedDescription)
            }
        }
    }

    private func prepareAttachments(for job: JobRecord) async throws -> [ManualEmailAttachment] {
        let selectedStored = selectedJobAttachments
        let added = addedAttachments
        let includePackage = draftStore.attachCompletionPackage
        let currency = store.settings.currency

        return try await Task.detached(priority: .userInitiated) {
            var prepared: [ManualEmailAttachment] = []

            if includePackage {
                let package = try JobFileService.shared.createJobZip(job: job, currency: currency)
                prepared.append(
                    ManualEmailAttachment(
                        fileName: package.lastPathComponent,
                        mimeType: "application/zip",
                        data: try Data(contentsOf: package, options: .mappedIfSafe)
                    )
                )
            }

            for attachment in selectedStored {
                prepared.append(try Self.loadSavedJobAttachment(attachment, job: job))
            }

            prepared.append(contentsOf: added)
            return prepared
        }.value
    }

    private static func loadSavedJobAttachment(_ attachment: JobAttachment, job: JobRecord) throws -> ManualEmailAttachment {
        let service = JobFileService.shared
        let url = service.url(for: attachment, jobID: job.id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ManualEmailAttachmentError.attachmentMissing(attachment.originalName)
        }

        if service.isFolder(attachment, jobID: job.id) {
            var coordinationError: NSError?
            var prepared: ManualEmailAttachment?
            var preparationError: Error?
            NSFileCoordinator().coordinate(
                readingItemAt: url,
                options: .forUploading,
                error: &coordinationError
            ) { zippedURL in
                do {
                    let name = attachment.originalName.lowercased().hasSuffix(".zip")
                        ? attachment.originalName
                        : attachment.originalName + ".zip"
                    prepared = ManualEmailAttachment(
                        fileName: name,
                        mimeType: "application/zip",
                        data: try Data(contentsOf: zippedURL, options: .mappedIfSafe)
                    )
                } catch {
                    preparationError = error
                }
            }
            if let coordinationError { throw coordinationError }
            if let preparationError { throw preparationError }
            guard let prepared else {
                throw ManualEmailAttachmentError.attachmentMissing(attachment.originalName)
            }
            return prepared
        }

        return ManualEmailAttachment(
            fileName: attachment.originalName,
            mimeType: mimeType(for: url),
            data: try Data(contentsOf: url, options: .mappedIfSafe)
        )
    }

    private func makeShareFiles(from attachments: [ManualEmailAttachment]) throws -> [URL] {
        guard !attachments.isEmpty else { return [] }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NextJobEmailShare-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return try attachments.enumerated().map { index, attachment in
            let safeName = Self.safeFileName(attachment.fileName, fallback: "Attachment-\(index + 1)")
            var destination = directory.appendingPathComponent(safeName)
            if FileManager.default.fileExists(atPath: destination.path) {
                destination = directory.appendingPathComponent("\(index + 1)-\(safeName)")
            }
            try attachment.data.write(to: destination, options: .atomic)
            return destination
        }
    }

    private static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    private static func safeFileName(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? fallback : trimmed
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = source.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? fallback : cleaned
    }

    private func showNotice(_ title: String, _ message: String) {
        noticeTitle = title
        noticeMessage = message
        showingNotice = true
    }

    private static let attachmentDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
