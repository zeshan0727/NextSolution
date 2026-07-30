import Foundation

@MainActor
final class VideoService: ObservableObject {
    @Published private(set) var videos: [YouTubeVideo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var canLoadMore = true
    @Published var errorMessage: String?

    private let apiKey = "AIzaSyDYe_SEtiDPtOd09aVOd4wR362jyC3cIRc"
    private let channelID = "UCyj0U_7r0gcQgL-fNvf9NYg"
    private var nextPageToken: String?
    private var hasLoaded = false

    func loadInitialIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await load(reset: true)
    }

    func refresh() async {
        await load(reset: true)
    }

    func loadMore() async {
        guard canLoadMore else { return }
        await load(reset: false)
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        if reset {
            nextPageToken = nil
        }

        do {
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
            var queryItems = [
                URLQueryItem(name: "part", value: "snippet"),
                URLQueryItem(name: "channelId", value: channelID),
                URLQueryItem(name: "maxResults", value: "12"),
                URLQueryItem(name: "order", value: "date"),
                URLQueryItem(name: "type", value: "video"),
                URLQueryItem(name: "key", value: apiKey)
            ]
            if !reset, let token = nextPageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: token))
            }
            components.queryItems = queryItems

            guard let url = components.url else {
                throw URLError(.badURL)
            }

            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let result = try JSONDecoder.youtube.decode(YouTubeSearchResponse.self, from: data)
            let mapped = result.items.compactMap { item -> YouTubeVideo? in
                guard let videoID = item.id.videoId else { return nil }
                let thumbnail = item.snippet.thumbnails.high?.url
                    ?? item.snippet.thumbnails.medium?.url
                    ?? item.snippet.thumbnails.defaultValue?.url
                return YouTubeVideo(
                    id: videoID,
                    title: item.snippet.title.decodingHTMLEntities,
                    description: item.snippet.description.decodingHTMLEntities,
                    publishedAt: item.snippet.publishedAt,
                    thumbnailURL: thumbnail
                )
            }

            if reset {
                videos = mapped
            } else {
                let existing = Set(videos.map(\.id))
                videos.append(contentsOf: mapped.filter { !existing.contains($0.id) })
            }

            nextPageToken = result.nextPageToken
            canLoadMore = result.nextPageToken != nil
        } catch {
            if videos.isEmpty {
                errorMessage = "The latest videos could not be loaded. You can still open the YouTube channel."
            } else {
                errorMessage = "More videos could not be loaded right now."
            }
        }

        isLoading = false
    }
}

final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published private(set) var activeItem: DownloadItem?
    @Published private(set) var progress: Double = 0
    @Published private(set) var isDownloading = false
    @Published var completedFile: DownloadedFile?
    @Published var errorMessage: String?

    private var session: URLSession!
    private var preferredFileName: String?

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func download(_ item: DownloadItem) {
        guard !isDownloading else { return }
        activeItem = item
        preferredFileName = item.fileName
        progress = 0
        errorMessage = nil
        isDownloading = true
        session.downloadTask(with: item.url).resume()
    }

    func cancel() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
        DispatchQueue.main.async {
            self.isDownloading = false
            self.activeItem = nil
            self.progress = 0
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.progress = value
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let fileName = preferredFileName
                ?? downloadTask.response?.suggestedFilename
                ?? downloadTask.originalRequest?.url?.lastPathComponent
                ?? "NextSolution-Download"
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destination = uniqueDestination(in: documents, fileName: fileName)
            try FileManager.default.copyItem(at: location, to: destination)

            DispatchQueue.main.async {
                self.completedFile = DownloadedFile(url: destination)
                self.isDownloading = false
                self.activeItem = nil
                self.progress = 1
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "The file downloaded, but it could not be saved: \(error.localizedDescription)"
                self.isDownloading = false
                self.activeItem = nil
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        DispatchQueue.main.async {
            self.errorMessage = "Download failed: \(error.localizedDescription)"
            self.isDownloading = false
            self.activeItem = nil
            self.progress = 0
        }
    }

    private func uniqueDestination(in directory: URL, fileName: String) -> URL {
        let fileManager = FileManager.default
        let original = directory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: original.path) else { return original }

        let extensionName = original.pathExtension
        let baseName = original.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let candidateName = extensionName.isEmpty
                ? "\(baseName)-\(index)"
                : "\(baseName)-\(index).\(extensionName)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}

private struct YouTubeSearchResponse: Decodable {
    let nextPageToken: String?
    let items: [YouTubeSearchItem]
}

private struct YouTubeSearchItem: Decodable {
    struct Identifier: Decodable {
        let videoId: String?
    }

    struct Snippet: Decodable {
        struct Thumbnails: Decodable {
            struct Thumbnail: Decodable {
                let url: URL
            }

            let defaultValue: Thumbnail?
            let medium: Thumbnail?
            let high: Thumbnail?

            enum CodingKeys: String, CodingKey {
                case defaultValue = "default"
                case medium
                case high
            }
        }

        let publishedAt: Date
        let title: String
        let description: String
        let thumbnails: Thumbnails
    }

    let id: Identifier
    let snippet: Snippet
}

private extension JSONDecoder {
    static var youtube: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension String {
    var decodingHTMLEntities: String {
        guard let data = data(using: .utf8) else { return self }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return self
        }
        return attributed.string
    }
}
