import Foundation

final class JobFileService {
    static let shared = JobFileService()

    private let fileManager = FileManager.default
    private let rootURL: URL

    private init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rootURL = documents.appendingPathComponent("Next Job Files", isDirectory: true)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func copyItems(_ urls: [URL], jobID: UUID, kind: AttachmentKind) throws -> [JobAttachment] {
        let targetFolder = folderURL(jobID: jobID, kind: kind)
        try fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)

        var attachments: [JobAttachment] = []
        var copiedDestinations: [URL] = []

        do {
            for sourceURL in urls {
                let copied: (attachment: JobAttachment, destination: URL) = try {
                    let accessing = sourceURL.startAccessingSecurityScopedResource()
                    defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

                    let sourceValues = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
                    let isDirectory = sourceValues.isDirectory == true
                    let originalName = sourceURL.lastPathComponent
                    let storedName = uniqueStoredName(for: originalName, isDirectory: isDirectory)
                    let destination = targetFolder.appendingPathComponent(storedName, isDirectory: isDirectory)

                    try copyCoordinatedItem(from: sourceURL, to: destination)
                    let attachment = JobAttachment(
                        originalName: originalName,
                        storedName: storedName,
                        kind: kind,
                        byteCount: byteCount(at: destination)
                    )
                    return (attachment, destination)
                }()

                copiedDestinations.append(copied.destination)
                attachments.append(copied.attachment)
            }
            return attachments
        } catch {
            for destination in copiedDestinations {
                try? fileManager.removeItem(at: destination)
            }
            throw error
        }
    }

    func copyFiles(_ urls: [URL], jobID: UUID, kind: AttachmentKind) throws -> [JobAttachment] {
        try copyItems(urls, jobID: jobID, kind: kind)
    }

    func url(for attachment: JobAttachment, jobID: UUID) -> URL {
        folderURL(jobID: jobID, kind: attachment.kind)
            .appendingPathComponent(attachment.storedName)
    }

    func isFolder(_ attachment: JobAttachment, jobID: UUID) -> Bool {
        let itemURL = url(for: attachment, jobID: jobID)
        return (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    func detailText(for attachment: JobAttachment, jobID: UUID) -> String {
        let size = ByteCountFormatter.string(fromByteCount: attachment.byteCount, countStyle: .file)
        return isFolder(attachment, jobID: jobID) ? "Folder • \(size)" : size
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
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let packageName = "Next Job - \(safeName(job.title))"
        let packageURL = temporaryRoot.appendingPathComponent(packageName, isDirectory: true)
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)

        try makeSummary(job: job, currency: currency).write(
            to: packageURL.appendingPathComponent("Job Summary.txt"),
            atomically: true,
            encoding: .utf8
        )

        for kind in AttachmentKind.allCases {
            let matching = job.attachments.filter { $0.kind == kind }
            guard !matching.isEmpty else { continue }
            let outputFolder = packageURL.appendingPathComponent(kind.folderName, isDirectory: true)
            try fileManager.createDirectory(at: outputFolder, withIntermediateDirectories: true)

            for attachment in matching {
                let source = url(for: attachment, jobID: job.id)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                var destination = outputFolder.appendingPathComponent(attachment.originalName)
                if fileManager.fileExists(atPath: destination.path) {
                    destination = outputFolder.appendingPathComponent(
                        "\(attachment.id.uuidString.prefix(6))-\(attachment.originalName)"
                    )
                }
                try fileManager.copyItem(at: source, to: destination)
            }
        }

        let finalURL = fileManager.temporaryDirectory
            .appendingPathComponent("\(packageName)-\(Self.dateFormatter.string(from: Date())).zip")
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
        try? fileManager.removeItem(at: temporaryRoot)
        return finalURL
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

    private func byteCount(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        guard values?.isDirectory == true else {
            return Int64(values?.fileSize ?? 0)
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        for case let itemURL as URL in enumerator {
            guard let itemValues = try? itemURL.resourceValues(forKeys: Set(keys)),
                  itemValues.isRegularFile == true else { continue }
            total += Int64(itemValues.fileSize ?? 0)
        }
        return total
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
            "NEXT JOB – JOB PACKAGE",
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
