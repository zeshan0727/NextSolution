import Foundation

struct VaultAttachment: Identifiable, Codable, Equatable {
    var id: UUID
    var originalName: String
    var storedName: String
    var byteCount: Int64
    var addedAt: Date

    init(
        id: UUID = UUID(),
        originalName: String,
        storedName: String,
        byteCount: Int64,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.originalName = originalName
        self.storedName = storedName
        self.byteCount = byteCount
        self.addedAt = addedAt
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

struct VaultEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var service: String
    var website: String
    var userID: String
    var category: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var isFavourite: Bool
    var attachments: [VaultAttachment]

    init(
        id: UUID = UUID(),
        service: String = "",
        website: String = "",
        userID: String = "",
        category: String = "General",
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isFavourite: Bool = false,
        attachments: [VaultAttachment] = []
    ) {
        self.id = id
        self.service = service
        self.website = website
        self.userID = userID
        self.category = category
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavourite = isFavourite
        self.attachments = attachments
    }

    var displayCategory: String {
        let value = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "General" : value
    }

    var initial: String {
        String(service.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    var searchableText: String {
        [service, website, userID, category, notes]
            .joined(separator: " ")
            .lowercased()
    }

    var websiteURL: URL? {
        let value = website.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let url = URL(string: value), url.scheme != nil { return url }
        return URL(string: "https://\(value)")
    }
}

struct VaultDatabase: Codable {
    var schemaVersion: Int
    var categories: [String]
    var entries: [VaultEntry]

    static let empty = VaultDatabase(
        schemaVersion: 1,
        categories: ["General"],
        entries: []
    )
}

enum VaultSort: String, CaseIterable, Identifiable {
    case recentlyUpdated
    case recentlyAdded
    case serviceAZ
    case category

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyUpdated: return "Recently Updated"
        case .recentlyAdded: return "Recently Added"
        case .serviceAZ: return "Service A–Z"
        case .category: return "Category"
        }
    }
}
