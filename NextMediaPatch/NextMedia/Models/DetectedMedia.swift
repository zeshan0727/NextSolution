import Foundation

struct DetectedMedia: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case video
        case audio
        case playlist
        case unknown

        var title: String {
            switch self {
            case .video: return "Video"
            case .audio: return "Audio"
            case .playlist: return "Stream"
            case .unknown: return "Media"
            }
        }

        var iconName: String {
            switch self {
            case .video: return "film.fill"
            case .audio: return "music.note"
            case .playlist: return "dot.radiowaves.left.and.right"
            case .unknown: return "play.rectangle.fill"
            }
        }
    }

    let id: UUID
    let url: URL
    var title: String
    var pageURL: URL?
    var mimeType: String?
    var kind: Kind
    var width: Int?
    var height: Int?
    var duration: Double?
    var detectionSource: String
    var wasPlaying: Bool
    var detectedAt: Date

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        pageURL: URL? = nil,
        mimeType: String? = nil,
        kind: Kind = .unknown,
        width: Int? = nil,
        height: Int? = nil,
        duration: Double? = nil,
        detectionSource: String = "page",
        wasPlaying: Bool = false,
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Detected media" : title
        self.pageURL = pageURL
        self.mimeType = mimeType
        self.kind = kind
        self.width = width
        self.height = height
        self.duration = duration
        self.detectionSource = detectionSource
        self.wasPlaying = wasPlaying
        self.detectedAt = detectedAt
    }

    var hostText: String {
        url.host ?? "Media source"
    }

    var qualityText: String? {
        guard let height, height > 0 else { return nil }
        switch height {
        case 2160...: return "4K"
        case 1440...: return "1440p"
        case 1080...: return "1080p"
        case 720...: return "720p"
        case 480...: return "480p"
        case 360...: return "360p"
        default: return "\(height)p"
        }
    }

    var formatText: String {
        let ext = url.pathExtension.uppercased()
        if !ext.isEmpty { return ext }
        if let mimeType, let subtype = mimeType.split(separator: "/").last {
            return String(subtype).uppercased()
        }
        return kind.title
    }

    var isPlaylist: Bool {
        let lower = url.absoluteString.lowercased()
        return kind == .playlist || lower.contains(".m3u8") || lower.contains(".mpd") ||
            mimeType?.lowercased().contains("mpegurl") == true ||
            mimeType?.lowercased().contains("dash+xml") == true
    }

    var isLikelySegment: Bool {
        let lowerPath = url.path.lowercased()
        let lower = url.absoluteString.lowercased()
        let segmentExtensions = [".m4s", ".cmfv", ".cmfa", ".ts"]
        if segmentExtensions.contains(where: lowerPath.hasSuffix) { return true }
        if lower.contains("range=") || lower.contains("/segment/") || lower.contains("/segments/") { return true }
        return false
    }

    var canDownloadAsFile: Bool {
        !isPlaylist && !isLikelySegment && ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }
}
