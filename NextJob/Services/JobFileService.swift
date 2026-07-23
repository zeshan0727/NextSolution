import Foundation

enum JobFileError: LocalizedError {
    case mixedFileAndFolderSelection
    case folderExpected
    case filesExpected
    case emptyFolder
    case symbolicLinkNotSupported
    case invalidFolderName

    var errorDescription: String? {
        switch self {
        case .mixedFileAndFolderSelection:
            return "Select either files or one complete folder. Files and folders cannot be mixed in the same import."
        case .folderExpected:
            return "The selected item is not a folder. Use Add Folder and select the folder itself, not the files inside it."
        case .filesExpected:
            return "A folder was selected from Add Files. Use Add Folder so the complete directory is attached as one item."
        case .emptyFolder:
            return "The selected folder is empty. Add documents to it before importing."
        case .symbolicLinkNotSupported:
            return "This folder contains a linked item that cannot be safely imported."
        case .invalidFolderName:
            return "The selected folder does not have a usable name."
        }
    }
}

final class JobFileService {
    static let shared = JobFileService()

    private let fileManager = FileManager.default
    private let rootURL: URL

    var filesRootURL: URL { rootURL }

    private init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rootURL = documents.appendingPathComponent("Next Job Files", isDirectory: true)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func copyItems(_ urls: [URL], jobID: UUID, kind: AttachmentKind) throws -> [JobAttachment] {
        guard !urls.isEmpty else { return [] }

        var directoryURLs: [URL] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                directoryURLs.append(url)
            }
        }

        if !directoryURLs.isEmpty {
            guard urls.count == 1, directoryURLs.count == 1 else {
                throw JobFileError.mixedFileAndFolderSelection
            }
            return [try copyFolder(directoryURLs[0], jobID: jobID, kind: kind)]
        }

        return try copyFiles(urls, jobID: jobID, kind: kind)
    }

    func copyFiles(_ urls: [URL], jobID: UUID, kind: AttachmentKind) throws -> [JobAttachment] {
        let targetFolder = folderURL(jobID: jobID, kind: kind)
        try fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)

        var attachments: [JobAttachment] = []
        var copiedDestinations: [URL] = []

        do {
            for sourceURL in urls {
                let accessing = sourceURL.startAccessingSecurityScopedResource()
                defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

                let sourceValues = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                guard sourceValues.isDirectory != true else { throw JobFileError.filesExpected }

                let originalName = sourceURL.lastPathComponent
                let storedName = uniqueStoredName(for: originalName, isDirectory: false)
                let destination = targetFolder.appendingPathComponent(storedName)

                try copyCoordinatedItem(from: sourceURL, to: destination)
                copiedDestinations.append(destination)
                attachments.append(
                    JobAttachment(
                        originalName: originalName,
                        storedName: storedName,
                        kind: kind,
                        byteCount: Int64((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0),
                        isFolder: false,
                        childCount: nil
                    )
                )
            }
            return attachments
        } catch {
            copiedDestinations.forEach { try? fileManager.removeItem(at: $0) }
            throw error
        }
    }

    func copyFolder(_ sourceURL: URL, jobID: UUID, kind: AttachmentKind) throws -> JobAttachment {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .nameKey])
        guard values.isDirectory == true else { throw JobFileError.folderExpected }

        let originalName = sourceURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !originalName.isEmpty else { throw JobFileError.invalidFolderName }

        let targetFolder = folderURL(jobID: jobID, kind: kind)
        try fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)

        let storedName = uniqueStoredName(for: originalName, isDirectory: true)
        let destination = targetFolder.appendingPathComponent(storedName, isDirectory: true)
        let stagingParent = fileManager.temporaryDirectory
            .appendingPathComponent("NextJobFolderImport-\(UUID().uuidString)", isDirectory: true)
        let stagingFolder = stagingParent.appendingPathComponent(originalName, isDirectory: true)

        try fileManager.createDirectory(at: stagingParent, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingParent) }

        do {
            try copyCoordinatedItem(from: sourceURL, to: stagingFolder)
            let metrics = try validateFolder(at: stagingFolder)
            guard metrics.fileCount > 0 else { throw JobFileError.emptyFolder }
            try fileManager.moveItem(at: stagingFolder, to: destination)
            return JobAttachment(
                originalName: originalName,
                storedName: storedName,
                kind: kind,
                byteCount: metrics.byteCount,
                isFolder: true,
                childCount: metrics.fileCount
            )
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    func copyFiles(_ urls: [URL], jobID: UUID, kind: AttachmentKind, legacy: Bool = true) throws -> [JobAttachment] {
        try copyFiles(urls, jobID: jobID, kind: kind)
    }

    func url(for attachment: JobAttachment, jobID: UUID) -> URL {
        folderURL(jobID: jobID, kind: attachment.kind)
            .appendingPathComponent(attachment.storedName, isDirectory: attachment.isFolder == true)
    }

    func isFolder(_ attachment: JobAttachment, jobID: UUID) -> Bool {
        if let isFolder = attachment.isFolder { return isFolder }
        let itemURL = url(for: attachment, jobID: jobID)
        return (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    func detailText(for attachment: JobAttachment, jobID: UUID) -> String {
        let size = ByteCountFormatter.string(fromByteCount: attachment.byteCount, countStyle: .file)
        guard isFolder(attachment, jobID: jobID) else { return size }
        if let count = attachment.childCount {
            return "Folder • \(count) file\(count == 1 ? "" : "s") • \(size)"
        }
        return "Folder • \(size)"
    }

    func deleteAttachment(_ attachment: JobAttachment, jobID: UUID) throws {
        let fileURL = url(for: attachment, jobID: jobID)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    func deleteJobFolder(jobID: UUID) throws {
        let url = jobFolder(jobID: jobID)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func createJobZip(job: JobRecord, currency: String) throws -> URL {
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("NextJobPackage-\(UUID().uuidString)", isDirectory: true)
        let company = safeName(job.clientName.isEmpty ? "KB Accountants" : job.clientName)
        let title = safeName(job.title)
        let packageName = "\(company) - Completion Documents - \(title)"
        let packageURL = temporaryRoot.appendingPathComponent(packageName, isDirectory: true)
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)

        defer { try? fileManager.removeItem(at: temporaryRoot) }

        try makeSummary(job: job, currency: currency).write(
            to: packageURL.appendingPathComponent("Job Summary.txt"),
            atomically: true,
            encoding: .utf8
        )

        let completionFolder = packageURL.appendingPathComponent("Completion Documents", isDirectory: true)
        try fileManager.createDirectory(at: completionFolder, withIntermediateDirectories: true)
        try copyAttachments(job.completedFiles, jobID: job.id, to: completionFolder)

        if !job.relatedFiles.isEmpty {
            let relatedFolder = packageURL.appendingPathComponent("Related Files - Reference", isDirectory: true)
            try fileManager.createDirectory(at: relatedFolder, withIntermediateDirectories: true)
            try copyAttachments(job.relatedFiles, jobID: job.id, to: relatedFolder)
        }

        let finalURL = fileManager.temporaryDirectory
            .appendingPathComponent("\(packageName) - \(Self.dateFormatter.string(from: Date())).zip")
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }

        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: packageURL,
            options: .forUploading,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try fileManager.copyItem(at: coordinatedURL, to: finalURL)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        guard fileManager.fileExists(atPath: finalURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return finalURL
    }

    func installRestoredRoot(from stagingRoot: URL) throws -> URL? {
        let parent = rootURL.deletingLastPathComponent()
        let previous = parent.appendingPathComponent("Next Job Files Previous-\(UUID().uuidString)", isDirectory: true)
        var previousURL: URL?

        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.moveItem(at: rootURL, to: previous)
            previousURL = previous
        }

        do {
            try fileManager.moveItem(at: stagingRoot, to: rootURL)
            return previousURL
        } catch {
            if let previousURL, fileManager.fileExists(atPath: previousURL.path) {
                try? fileManager.moveItem(at: previousURL, to: rootURL)
            }
            throw error
        }
    }

    func rollbackRestoredRoot(previousRoot: URL?) {
        try? fileManager.removeItem(at: rootURL)
        if let previousRoot, fileManager.fileExists(atPath: previousRoot.path) {
            try? fileManager.moveItem(at: previousRoot, to: rootURL)
        } else {
            try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
    }

    func discardPreviousRoot(_ previousRoot: URL?) {
        if let previousRoot { try? fileManager.removeItem(at: previousRoot) }
    }

    private func copyAttachments(_ attachments: [JobAttachment], jobID: UUID, to outputFolder: URL) throws {
        for attachment in attachments {
            let source = url(for: attachment, jobID: jobID)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            var destination = outputFolder.appendingPathComponent(
                attachment.originalName,
                isDirectory: isFolder(attachment, jobID: jobID)
            )
            if fileManager.fileExists(atPath: destination.path) {
                destination = outputFolder.appendingPathComponent(
                    "\(attachment.id.uuidString.prefix(6))-\(attachment.originalName)",
                    isDirectory: isFolder(attachment, jobID: jobID)
                )
            }
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    private func copyCoordinatedItem(from sourceURL: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { coordinatedURL in
            do {
                try fileManager.copyItem(at: coordinatedURL, to: destination)
            } catch {
                copyError = error
            }
        }

        if let coordinationError {
            try? fileManager.removeItem(at: destination)
            throw coordinationError
        }
        if let copyError {
            try? fileManager.removeItem(at: destination)
            throw copyError
        }
        guard fileManager.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
    }

    private func validateFolder(at url: URL) throws -> (fileCount: Int, byteCount: Int64) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return (0, 0) }

        var count = 0
        var total: Int64 = 0
        for case let itemURL as URL in enumerator {
            let values = try itemURL.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { throw JobFileError.symbolicLinkNotSupported }
            if values.isRegularFile == true {
                count += 1
                total += Int64(values.fileSize ?? 0)
            }
        }
        return (count, total)
    }

    private func folderURL(jobID: UUID, kind: AttachmentKind) -> URL {
        jobFolder(jobID: jobID).appendingPathComponent(kind.rawValue, isDirectory: true)
    }

    private func jobFolder(jobID: UUID) -> URL {
        rootURL.appendingPathComponent(jobID.uuidString, isDirectory: true)
    }

    private func uniqueStoredName(for originalName: String, isDirectory: Bool) -> String {
        let suffix = UUID().uuidString.prefix(8)
        if isDirectory {
            return "\(safeName(originalName))-\(suffix)"
        }

        let ext = (originalName as NSString).pathExtension
        let stem = (originalName as NSString).deletingPathExtension
        return ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
    }

    private func safeName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Job" : String(trimmed.prefix(80))
    }

    private func makeSummary(job: JobRecord, currency: String) -> String {
        var lines = [
            "NEXT JOB – COMPLETION PACKAGE",
            "",
            "Job: \(job.title)",
            "Company: \(job.clientName)",
            "Type: \(job.jobType)",
            "Status: \(job.status.title)",
            "Assigned: \(Self.fullDateFormatter.string(from: job.assignedDate))",
            "Due: \(Self.fullDateFormatter.string(from: job.dueDate))",
            "Target time: \(job.targetTimeText)",
            "Actual time: \(job.actualTimeText)",
            "Price: \(currency) \(String(format: "%.2f", job.price))"
        ]
        if let completedDate = job.completedDate {
            lines.append("Completed: \(Self.fullDateFormatter.string(from: completedDate))")
        }
        if !job.requestedDocuments.isEmpty {
            lines.append(contentsOf: ["", "DOCUMENTS REQUESTED", job.requestedDocuments])
        }
        if !job.notes.isEmpty {
            lines.append(contentsOf: ["", "JOB NOTES", job.notes])
        }
        if !job.completionNotes.isEmpty {
            lines.append(contentsOf: ["", "COMPLETION NOTES", job.completionNotes])
        }
        lines.append(contentsOf: ["", "Prepared with Next Job", "Next Solution – Zeeshan Barvi"])
        return lines.joined(separator: "\n")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
