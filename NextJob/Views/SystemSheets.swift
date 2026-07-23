import SwiftUI
import UIKit
import UniformTypeIdentifiers
import MessageUI
import QuickLook

enum DocumentPickerMode {
    case files
    case folder

    var contentTypes: [UTType] {
        switch self {
        case .files: return [.item]
        case .folder: return [.folder]
        }
    }

    var copiesSelection: Bool {
        switch self {
        case .files: return true
        case .folder: return false
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let mode: DocumentPickerMode
    let allowsMultipleSelection: Bool
    let completion: (Result<[URL], Error>) -> Void

    init(
        mode: DocumentPickerMode = .files,
        allowsMultipleSelection: Bool,
        completion: @escaping (Result<[URL], Error>) -> Void
    ) {
        self.mode = mode
        self.allowsMultipleSelection = allowsMultipleSelection
        self.completion = completion
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: mode.contentTypes,
            asCopy: mode.copiesSelection
        )
        picker.allowsMultipleSelection = mode == .files && allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let completion: (Result<[URL], Error>) -> Void
        private var hasFinished = false

        init(completion: @escaping (Result<[URL], Error>) -> Void) {
            self.completion = completion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish(.success([]))
        }

        private func finish(_ result: Result<[URL], Error>) {
            guard !hasFinished else { return }
            hasFinished = true
            DispatchQueue.main.async { [completion] in
                completion(result)
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct MailAttachment {
    let data: Data
    let mimeType: String
    let fileName: String
}

struct MailDraft: Identifiable {
    let id = UUID()
    let recipients: [String]
    let subject: String
    let body: String
    let attachments: [MailAttachment]
    let kind: JobEmailRecord.Kind
}

struct MailComposer: UIViewControllerRepresentable {
    let draft: MailDraft
    let completion: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(draft.recipients)
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        for attachment in draft.attachments {
            controller.addAttachmentData(attachment.data, mimeType: attachment.mimeType, fileName: attachment.fileName)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let completion: (MFMailComposeResult) -> Void

        init(completion: @escaping (MFMailComposeResult) -> Void) {
            self.completion = completion
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            completion(result)
        }
    }
}

struct PreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}
