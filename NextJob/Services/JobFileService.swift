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

    func copyFiles(_ urls: [URL], jobID: UUID, kind: AttachmentKind) throws -> [JobAttachment] {
        let targetFolder = folderURL(jobID: jobID, kind: kind)
        try fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)

        return try urls.map { sourceURL in
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

            let originalName = sourceURL.lastPathComponent
            let storedName = uniqueStoredName(for: originalName)
            let destination = targetFolder.appendingPathComponent(storedName)
            try fileManager.copyItem(at: sourceURL, to: destination)
            let values = try destination.resourceValues(forKeys: [.fileSizeKey])
            return JobAttachment(
                originalName: originalName,
                storedName: storedName,
                kind: kind,
                byteCount: Int64(values.fileSize ?? 0)
            )
        }
    }

    func url(for attachment: JobAttachment, jobID: UUID) -> URL {
        folderURL(jobID: jobID, kind: attachment.kind)
            .appendingPathComponent(attachment.storedName)
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
                    destination = outputFolder.appendingPathComponent("\(attachment.id.uuidString.prefix(6))-\(attachment.originalName)")
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
        NSFileCoordinator().coordinate(readingItemAt: packageURL, options: .forUploading, error: &coordinationError) { coordinatedURL in
            do {
                try fileManager.copyItem(at: coordinatedURL, to: finalURL)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        guard fileManager.fileExists(atPath: finalURL.path) else { throw CocoaError(.fileNoSuchFile) }
        try? fileManager.removeItem(at: temporaryRoot)
        return finalURL
    }

    private func folderURL(jobID: UUID, kind: AttachmentKind) -> URL {
        jobFolder(jobID: jobID).appendingPathComponent(kind.rawValue, isDirectory: true)
    }

    private func jobFolder(jobID: UUID) -> URL {
        rootURL.appendingPathComponent(jobID.uuidString, isDirectory: true)
    }

    private func uniqueStoredName(for originalName: String) -> String {
        let ext = (originalName as NSString).pathExtension
        let stem = (originalName as NSString).deletingPathExtension
        let suffix = UUID().uuidString.prefix(8)
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
