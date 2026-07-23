import Foundation
import UniformTypeIdentifiers

final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()

    @Published private(set) var records: [DownloadRecord] = []

    private var taskToRecord: [Int: UUID] = [:]
    private var preferredTitles: [UUID: String] = [:]
    private let mappingLock = NSLock()

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = true
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 8
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
    }

    func start(urlString: String, title: String? = nil, headers: [String: String] = [:]) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            addFailedRecord(title: title ?? "Invalid URL", sourceURL: trimmed, message: "Enter a valid HTTP or HTTPS direct media link.")
            return
        }

        if Self.isPlaylistURL(url) {
            addFailedRecord(
                title: title ?? "Streaming playlist",
                sourceURL: trimmed,
                message: "This address is a streaming playlist rather than one complete file. Offline HLS packaging is not enabled in this build."
            )
            return
        }

        var record = DownloadRecord(
            title: title?.isEmpty == false ? title! : (url.deletingPathExtension().lastPathComponent.isEmpty ? "Download" : url.deletingPathExtension().lastPathComponent),
            sourceURL: trimmed,
            state: .downloading
        )
        if record.title.isEmpty { record.title = "Download" }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "GET"
        for (field, value) in sanitized(headers: headers) {
            request.setValue(value, forHTTPHeaderField: field)
        }

        DispatchQueue.main.async {
            self.records.insert(record, at: 0)
            self.withMappingLock {
                self.preferredTitles[record.id] = record.title
            }
            let task = self.session.downloadTask(with: request)
            self.withMappingLock {
                self.taskToRecord[task.taskIdentifier] = record.id
            }
            task.resume()
        }
    }

    func cancel(_ record: DownloadRecord) {
        let taskIdentifier: Int? = withMappingLock {
            taskToRecord.first(where: { $0.value == record.id })?.key
        }
        guard let taskIdentifier else { return }
        session.getAllTasks { tasks in
            tasks.first { $0.taskIdentifier == taskIdentifier }?.cancel()
        }
        update(recordID: record.id) {
            $0.state = .cancelled
            $0.errorMessage = "Cancelled"
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let recordID = recordID(for: downloadTask.taskIdentifier), totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        update(recordID: recordID) {
            $0.progress = min(max(progress, 0), 1)
            $0.state = .downloading
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let recordID = recordID(for: downloadTask.taskIdentifier) else { return }
        guard let response = downloadTask.response as? HTTPURLResponse else {
            fail(recordID, message: "The server returned an invalid response.")
            return
        }

        guard (200..<300).contains(response.statusCode) else {
            fail(recordID, message: "The server returned HTTP \(response.statusCode).")
            return
        }

        let mime = response.mimeType?.lowercased()
        let responseURL = response.url ?? downloadTask.originalRequest?.url
        if response.statusCode == 206 || response.value(forHTTPHeaderField: "Content-Range") != nil {
            fail(recordID, message: "The page exposed only a partial media segment, not one complete downloadable file.")
            return
        }
        if Self.isPlaylistURL(responseURL) || mime?.contains("mpegurl") == true || mime?.contains("dash+xml") == true {
            fail(recordID, message: "A streaming playlist was detected. This build downloads complete media files only.")
            return
        }
        if Self.isWebDocumentMIME(mime) {
            fail(recordID, message: "The link returned a webpage instead of a media file.")
            return
        }

        let suggested = response.suggestedFilename
        let sourceExtension = responseURL?.pathExtension
        let suggestedExtension = (suggested as NSString?)?.pathExtension
        let finalExtension: String = {
            if let suggestedExtension, !suggestedExtension.isEmpty { return suggestedExtension }
            if let sourceExtension, !sourceExtension.isEmpty { return sourceExtension }
            return extensionFromMIME(mime)
        }()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(finalExtension.isEmpty ? "media" : finalExtension)")

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else { throw DownloadError.emptyFile }

            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.moveItem(at: location, to: tempURL)

            let title = preferredTitle(for: recordID)
                ?? suggested?.deletingPathExtension
                ?? responseURL?.deletingPathExtension().lastPathComponent
                ?? "Download"
            _ = try MediaLibraryStore.shared.addFile(from: tempURL, preferredTitle: title, source: .downloaded)
            try? FileManager.default.removeItem(at: tempURL)
            update(recordID: recordID) {
                $0.progress = 1
                $0.state = .completed
                $0.errorMessage = nil
            }
        } catch {
            fail(recordID, message: error.localizedDescription)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let recordID = recordID(for: task.taskIdentifier) else { return }
        if let error = error as NSError?, error.code != NSURLErrorCancelled {
            fail(recordID, message: error.localizedDescription)
        }
        withMappingLock {
            taskToRecord.removeValue(forKey: task.taskIdentifier)
            preferredTitles.removeValue(forKey: recordID)
        }
    }

    private func update(recordID: UUID, mutation: @escaping (inout DownloadRecord) -> Void) {
        DispatchQueue.main.async {
            guard let index = self.records.firstIndex(where: { $0.id == recordID }) else { return }
            mutation(&self.records[index])
        }
    }

    private func fail(_ recordID: UUID, message: String) {
        update(recordID: recordID) {
            $0.state = .failed
            $0.errorMessage = message
        }
    }

    private func addFailedRecord(title: String, sourceURL: String, message: String) {
        let record = DownloadRecord(title: title, sourceURL: sourceURL, state: .failed, errorMessage: message)
        DispatchQueue.main.async { self.records.insert(record, at: 0) }
    }

    private func extensionFromMIME(_ mime: String?) -> String {
        guard let mime else { return "media" }
        if mime.hasPrefix("video/") { return UTType(mimeType: mime)?.preferredFilenameExtension ?? "mp4" }
        if mime.hasPrefix("audio/") { return UTType(mimeType: mime)?.preferredFilenameExtension ?? "m4a" }
        return UTType(mimeType: mime)?.preferredFilenameExtension ?? "media"
    }

    private func sanitized(headers: [String: String]) -> [String: String] {
        let allowed = Set(["user-agent", "referer", "origin", "cookie", "accept", "accept-language"])
        return headers.reduce(into: [:]) { result, entry in
            let field = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard allowed.contains(field.lowercased()), !value.isEmpty else { return }
            result[field] = value
        }
    }

    private func recordID(for taskIdentifier: Int) -> UUID? {
        withMappingLock { taskToRecord[taskIdentifier] }
    }

    private func preferredTitle(for recordID: UUID) -> String? {
        withMappingLock { preferredTitles[recordID] }
    }

    private func withMappingLock<T>(_ work: () -> T) -> T {
        mappingLock.lock()
        defer { mappingLock.unlock() }
        return work()
    }

    private static func isPlaylistURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        let lower = url.absoluteString.lowercased()
        return lower.contains(".m3u8") || lower.contains(".mpd")
    }

    private static func isWebDocumentMIME(_ mime: String?) -> Bool {
        guard let mime else { return false }
        return mime.hasPrefix("text/html") || mime.hasPrefix("application/xhtml") ||
            mime.hasPrefix("application/json") || mime.hasPrefix("text/javascript") ||
            mime.hasPrefix("text/css")
    }
}

private enum DownloadError: LocalizedError {
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .emptyFile: return "The server returned an empty file."
        }
    }
}

private extension String {
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }
}
