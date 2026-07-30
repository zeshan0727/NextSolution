import Foundation
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case tutorials
    case videos
    case downloads
    case uploads
    case faq

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .tutorials: return "Tutorials"
        case .videos: return "Videos"
        case .downloads: return "Downloads"
        case .uploads: return "Uploads"
        case .faq: return "FAQ"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .tutorials: return "book.closed.fill"
        case .videos: return "play.rectangle.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .uploads: return "icloud.and.arrow.up.fill"
        case .faq: return "questionmark.circle.fill"
        }
    }
}

struct Tutorial: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let tags: [String]
    let heroURL: URL?
    let sourceURL: URL
    let featured: Bool
    let sections: [TutorialSection]
    let relatedDownloadIDs: [String]
}

struct TutorialSection: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let body: String
    let bullets: [String]
}

struct DownloadItem: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case package = "Packages"
        case app = "Apps"
        case source = "Source"
        case repository = "Repository"
    }

    let id: String
    let title: String
    let detail: String
    let version: String
    let kind: Kind
    let icon: String
    let url: URL
    let fileName: String?
    let externalOnly: Bool
}

struct UploadDestination: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let url: URL
}

struct FAQItem: Identifiable, Hashable {
    let id: String
    let question: String
    let answer: String
}

struct SharedPayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct DownloadedFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct YouTubeVideo: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let publishedAt: Date
    let thumbnailURL: URL?

    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(id)")!
    }
}

enum AppTheme {
    static let purple = Color(red: 0.42, green: 0.07, blue: 0.80)
    static let blue = Color(red: 0.15, green: 0.46, blue: 0.99)
    static let cyan = Color(red: 0.00, green: 0.74, blue: 0.95)
    static let gradient = LinearGradient(
        colors: [purple, blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
