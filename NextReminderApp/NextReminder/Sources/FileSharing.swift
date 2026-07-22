import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

struct FileShareShortcut: Identifiable, Codable, Hashable {
    var title: String
    var email: String
    var id: String { title }
}

@MainActor
final class FileShareShortcutStore: ObservableObject {
    static let storageKey = "NextReminder.FileShareShortcuts.v1"
    static let fixedTitles = [
        "Barjous",
        "Erada",
        "Stone",
        "Nabina Email",
        "Atelier Home",
        "Other"
    ]

    @Published var shortcuts: [FileShareShortcut] = []

    init() {
        reload()
    }

    func reload() {
        let saved: [FileShareShortcut]
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([FileShareShortcut].self, from: data) {
            saved = decoded
        } else {
            saved = []
        }

        shortcuts = Self.fixedTitles.map { title in
            saved.first(where: { $0.title == title })
                ?? FileShareShortcut(title: title, email: "")
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

struct FileShareAttachment: Identifiable {
    let id = UUID()
    var fileName: String
    var mimeType: String
    var data: Data

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}

private struct FileShareAttachmentPayload: Encodable {
    var fileName: String
    var mimeType: String
    var base64: String
}

private struct FileSharePayload: Encodable {
    var recipients: [String]
    var subject: String
    var body: String
    var remoteConnectorID: String
    var senderLabel: String
    var attachments: [FileShareAttachmentPayload]
}

private struct FileShareServerResponse: Decodable {
    var id: String?
    var message: String?
}

enum FileShareError: LocalizedError {
    case schedulerNotConfigured
    case gmailNotConnected
    case invalidRecipient
    case missingAttachment
    case attachmentTooLarge
    case totalTooLarge
    case invalidEndpoint
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .schedulerNotConfigured:
            return "Configure and test the HTTPS scheduler in Automation Connections first."
        case .gmailNotConnected:
            return "Connect Gmail in Email Automations before sharing files."
        case .invalidRecipient:
            return "Add at least one valid recipient email address."
        case .missingAttachment:
            return "Attach at least one photo, file, captured image, or scanned document."
        case .attachmentTooLarge:
            return "Each attachment must be smaller than 10 MB."
        case .totalTooLarge:
            return "The combined attachments must be smaller than 18 MB."
        case .invalidEndpoint:
            return "The scheduler URL must be a valid HTTPS address."
        case .invalidResponse:
            return "The Gmail scheduler returned an invalid response."
        case .server(let message):
            return message
        }
    }
}

struct FileShareService {
    private let maximumSingleAttachment = 10_000_000
    private let maximumTotalAttachments = 18_000_000

    func send(
        recipients: [String],
        subject: String,
        body: String,
        attachments: [FileShareAttachment],
        gmail: GmailConnectionRecord,
        configuration: AutomationCloudConfiguration
    ) async throws -> String {
        guard configuration.isConfigured else {
            throw FileShareError.schedulerNotConfigured
        }
        guard !gmail.connectorID.isEmpty else {
            throw FileShareError.gmailNotConnected
        }
        guard !recipients.isEmpty, recipients.allSatisfy(Self.isValidEmail) else {
            throw FileShareError.invalidRecipient
        }
        guard !attachments.isEmpty else {
            throw FileShareError.missingAttachment
        }
        guard attachments.allSatisfy({ $0.data.count <= maximumSingleAttachment }) else {
            throw FileShareError.attachmentTooLarge
        }
        guard attachments.reduce(0, { $0 + $1.data.count }) <= maximumTotalAttachments else {
            throw FileShareError.totalTooLarge
        }

        let normalized = configuration.endpoint.hasSuffix("/")
            ? configuration.endpoint
            : configuration.endpoint + "/"
        guard let baseURL = URL(string: normalized),
              baseURL.scheme?.lowercased() == "https",
              let url = URL(string: "v1/file-shares", relativeTo: baseURL)?.absoluteURL else {
            throw FileShareError.invalidEndpoint
        }

        let payload = FileSharePayload(
            recipients: recipients,
            subject: subject,
            body: body,
            remoteConnectorID: gmail.connectorID,
            senderLabel: gmail.emailAddress,
            attachments: attachments.map {
                FileShareAttachmentPayload(
                    fileName: $0.fileName,
                    mimeType: $0.mimeType,
                    base64: $0.data.base64EncodedString()
                )
            }
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("NextReminder-iOS/1.2.3", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FileShareError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(FileShareServerResponse.self, from: data).message)
                ?? "File sharing failed (\(http.statusCode))."
            throw FileShareError.server(message)
        }

        return (try? JSONDecoder().decode(FileShareServerResponse.self, from: data).message)
            ?? "Email sent successfully."
    }

    static func isValidEmail(_ value: String) -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = cleaned.firstIndex(of: "@"),
              cleaned[cleaned.index(after: at)...].contains(".") else {
            return false
        }
        return !cleaned.contains(" ") && cleaned.count <= 254
    }
}

struct FileSharingView: View {
    @EnvironmentObject private var automationStore: AutomationStore
    @StateObject private var shortcutStore = FileShareShortcutStore()

    @State private var recipients: [String] = []
    @State private var manualRecipient = ""
    @State private var subject = "Attachment"
    @State private var bodyText = "Dear Team,\nPlease find the attached file(s)."
    @State private var attachments: [FileShareAttachment] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []

    @State private var isShowingShortcutEditor = false
    @State private var isShowingFileImporter = false
    @State private var isShowingCamera = false
    @State private var isShowingScanner = false
    @State private var isSending = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var showSentConfirmation = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private var gmailRecord: GmailConnectionRecord? {
        GmailConnectionStore.shared.load()
    }

    private var canSend: Bool {
        !isSending
            && !recipients.isEmpty
            && !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !attachments.isEmpty
            && gmailRecord != nil
            && automationStore.cloudConfiguration.isConfigured
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                connectionCard
                recipientShortcuts
                toSection
                messageSection
                attachmentSection
                actionButtons
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("File Sharing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingShortcutEditor = true
                } label: {
                    Image(systemName: "person.crop.circle.badge.gearshape")
                }
                .accessibilityLabel("Edit recipient shortcuts")
            }
        }
        .sheet(isPresented: $isShowingShortcutEditor) {
            FileShareShortcutEditor(store: shortcutStore)
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraCaptureView { image in
                addCapturedImage(image)
                isShowingCamera = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingScanner) {
            DocumentScannerView { images in
                addScannedDocument(images)
                isShowingScanner = false
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: importFiles
        )
        .onChange(of: selectedPhotos) { items in
            importPhotos(items)
        }
        .alert("Email Sent", isPresented: $showSentConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusMessage ?? "Email sent successfully.")
        }
        .alert("File Sharing", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var connectionCard: some View {
        let connected = gmailRecord != nil && automationStore.cloudConfiguration.isConfigured
        return HStack(spacing: 13) {
            Image(systemName: connected ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(connected ? Color.green : Color.orange)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(connected ? "Gmail file sharing ready" : "Gmail setup required")
                    .font(.headline)
                Text(gmailRecord?.emailAddress ?? "Connect Gmail and the scheduler in Automations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .nextCard()
    }

    private var recipientShortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Quick Recipients", trailing: "Tap to add to To")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(shortcutStore.shortcuts) { shortcut in
                    Button {
                        let email = shortcut.email.trimmingCharacters(in: .whitespacesAndNewlines)
                        if email.isEmpty {
                            isShowingShortcutEditor = true
                        } else {
                            addRecipient(email)
                        }
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: shortcut.email.isEmpty ? "person.crop.circle.badge.plus" : "envelope.fill")
                                .font(.title3)
                            Text(shortcut.title)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                            Text(shortcut.email.isEmpty ? "Set email" : shortcut.email)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(Color.nextCardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var toSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "To")

            if !recipients.isEmpty {
                FlowRecipientList(recipients: recipients) { value in
                    recipients.removeAll { $0 == value }
                }
            }

            HStack(spacing: 10) {
                TextField("name@example.com", text: $manualRecipient)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .submitLabel(.done)
                    .onSubmit { addManualRecipient() }
                Button {
                    addManualRecipient()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.nextOrange)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .nextCard()
        }
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Message")
            TextField("Subject", text: $subject)
                .padding(14)
                .nextCard()

            TextEditor(text: $bodyText)
                .frame(minHeight: 115)
                .scrollContentBackground(.hidden)
                .padding(10)
                .nextCard()
        }
    }

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Attach Things", trailing: "Maximum total 18 MB")

            LazyVGrid(columns: columns, spacing: 10) {
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 10,
                    matching: .images
                ) {
                    attachmentSourceLabel("Gallery", systemImage: "photo.on.rectangle")
                }

                Button {
                    isShowingFileImporter = true
                } label: {
                    attachmentSourceLabel("Files", systemImage: "folder.fill")
                }
                .buttonStyle(.plain)

                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        isShowingCamera = true
                    } else {
                        errorMessage = "Camera is not available on this device."
                    }
                } label: {
                    attachmentSourceLabel("Capture", systemImage: "camera.fill")
                }
                .buttonStyle(.plain)

                Button {
                    if VNDocumentCameraViewController.isSupported {
                        isShowingScanner = true
                    } else {
                        errorMessage = "Document scanning is not available on this device."
                    }
                } label: {
                    attachmentSourceLabel("Scan", systemImage: "doc.viewfinder.fill")
                }
                .buttonStyle(.plain)
            }

            if attachments.isEmpty {
                Text("No attachments selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(attachments) { attachment in
                    HStack(spacing: 12) {
                        Image(systemName: attachment.mimeType == "application/pdf" ? "doc.richtext.fill" : "paperclip")
                            .foregroundStyle(.nextOrange)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(attachment.fileName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(attachment.sizeText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(13)
                    .nextCard()
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                resetDraft()
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button {
                sendEmail()
            } label: {
                HStack(spacing: 8) {
                    if isSending { ProgressView().tint(.white) }
                    Image(systemName: "paperplane.fill")
                    Text(isSending ? "Sending…" : "Send")
                }
            }
            .buttonStyle(OrangeActionButtonStyle())
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.5)
        }
    }

    private func attachmentSourceLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.nextOrange)
            Text(title)
                .font(.subheadline.bold())
            Spacer()
        }
        .padding(13)
        .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.nextCardBorder, lineWidth: 1)
        )
    }

    private func addManualRecipient() {
        let cleaned = manualRecipient.trimmingCharacters(in: .whitespacesAndNewlines)
        addRecipient(cleaned)
        if FileShareService.isValidEmail(cleaned) {
            manualRecipient = ""
        }
    }

    private func addRecipient(_ value: String) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FileShareService.isValidEmail(cleaned) else {
            errorMessage = "Enter a valid email address."
            return
        }
        if !recipients.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame }) {
            recipients.append(cleaned)
        }
    }

    private func addAttachment(_ attachment: FileShareAttachment) {
        guard attachment.data.count <= 10_000_000 else {
            errorMessage = "\(attachment.fileName) is larger than 10 MB."
            return
        }
        let proposedTotal = attachments.reduce(attachment.data.count) { $0 + $1.data.count }
        guard proposedTotal <= 18_000_000 else {
            errorMessage = "The combined attachments cannot exceed 18 MB."
            return
        }
        attachments.append(attachment)
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var imported: [FileShareAttachment] = []
            for (index, item) in items.enumerated() {
                guard let rawData = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: rawData),
                      let jpeg = image.jpegData(compressionQuality: 0.82) else {
                    continue
                }
                imported.append(
                    FileShareAttachment(
                        fileName: "Photo-\(Int(Date().timeIntervalSince1970))-\(index + 1).jpg",
                        mimeType: "image/jpeg",
                        data: jpeg
                    )
                )
            }
            await MainActor.run {
                for attachment in imported { addAttachment(attachment) }
                selectedPhotos = []
            }
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                do {
                    let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
                    if let fileSize = values.fileSize, fileSize > 10_000_000 {
                        errorMessage = "\(url.lastPathComponent) is larger than 10 MB."
                        continue
                    }
                    let data = try Data(contentsOf: url)
                    addAttachment(
                        FileShareAttachment(
                            fileName: url.lastPathComponent,
                            mimeType: values.contentType?.preferredMIMEType ?? "application/octet-stream",
                            data: data
                        )
                    )
                } catch {
                    errorMessage = "Could not attach \(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
        }
    }

    private func addCapturedImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.82) else {
            errorMessage = "The captured photo could not be prepared."
            return
        }
        addAttachment(
            FileShareAttachment(
                fileName: "Captured-\(Int(Date().timeIntervalSince1970)).jpg",
                mimeType: "image/jpeg",
                data: data
            )
        )
    }

    private func addScannedDocument(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let pdf = renderer.pdfData { context in
            for image in images {
                context.beginPage()
                let inset = pageBounds.insetBy(dx: 24, dy: 24)
                let imageRatio = image.size.width / max(image.size.height, 1)
                let targetRatio = inset.width / inset.height
                let drawRect: CGRect
                if imageRatio > targetRatio {
                    let height = inset.width / imageRatio
                    drawRect = CGRect(
                        x: inset.minX,
                        y: inset.midY - height / 2,
                        width: inset.width,
                        height: height
                    )
                } else {
                    let width = inset.height * imageRatio
                    drawRect = CGRect(
                        x: inset.midX - width / 2,
                        y: inset.minY,
                        width: width,
                        height: inset.height
                    )
                }
                image.draw(in: drawRect)
            }
        }
        addAttachment(
            FileShareAttachment(
                fileName: "Scanned-Document-\(Int(Date().timeIntervalSince1970)).pdf",
                mimeType: "application/pdf",
                data: pdf
            )
        )
    }

    private func sendEmail() {
        guard let gmail = gmailRecord else {
            errorMessage = FileShareError.gmailNotConnected.localizedDescription
            return
        }

        isSending = true
        let cleanedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentRecipients = recipients
        let currentAttachments = attachments
        let configuration = automationStore.cloudConfiguration

        Task {
            defer { isSending = false }
            do {
                statusMessage = try await FileShareService().send(
                    recipients: currentRecipients,
                    subject: cleanedSubject,
                    body: cleanedBody,
                    attachments: currentAttachments,
                    gmail: gmail,
                    configuration: configuration
                )
                resetDraft()
                showSentConfirmation = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resetDraft() {
        recipients = []
        manualRecipient = ""
        subject = "Attachment"
        bodyText = "Dear Team,\nPlease find the attached file(s)."
        attachments = []
        selectedPhotos = []
    }
}

struct FlowRecipientList: View {
    var recipients: [String]
    var onRemove: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(recipients, id: \.self) { recipient in
                HStack(spacing: 7) {
                    Image(systemName: "envelope.fill")
                    Text(recipient)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Button {
                        onRemove(recipient)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.nextOrange.opacity(0.14), in: Capsule())
            }
        }
    }
}

struct FileShareShortcutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: FileShareShortcutStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach($store.shortcuts) { $shortcut in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(shortcut.title)
                                .font(.headline)
                            TextField("email@example.com", text: $shortcut.email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                        }
                        .padding(14)
                        .nextCard()
                    }
                }
                .padding(16)
            }
            .background(Color.nextBackground.ignoresSafeArea())
            .navigationTitle("Recipient Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.reload()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        for index in store.shortcuts.indices {
                            store.shortcuts[index].email = store.shortcuts[index].email
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        store.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

struct DocumentScannerView: UIViewControllerRepresentable {
    var onScan: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView

        init(parent: DocumentScannerView) {
            self.parent = parent
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onScan(images)
            controller.dismiss(animated: true)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            controller.dismiss(animated: true)
        }
    }
}
