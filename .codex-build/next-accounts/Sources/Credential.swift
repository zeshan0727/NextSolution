import Foundation

enum AccountPlatform: String, Codable, CaseIterable, Identifiable {
    case apple
    case google
    case youtube
    case instagram
    case facebook
    case twitter
    case tiktok

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "Apple"
        case .google: return "Google"
        case .youtube: return "YouTube"
        case .instagram: return "Insta"
        case .facebook: return "FB"
        case .twitter: return "Twitter"
        case .tiktok: return "TikTok"
        }
    }

    var systemImage: String {
        switch self {
        case .apple: return "apple.logo"
        case .google: return "globe"
        case .youtube: return "play.rectangle.fill"
        case .instagram: return "camera.fill"
        case .facebook: return "person.2.fill"
        case .twitter: return "paperplane.fill"
        case .tiktok: return "music.note"
        }
    }

}

struct Credential: Codable, Equatable, Identifiable {
    let id: UUID
    var email: String
    var password: String
    let isGenerated: Bool
    var activePlatforms: Set<AccountPlatform>

    init(
        id: UUID = UUID(),
        email: String,
        password: String,
        isGenerated: Bool = false,
        activePlatforms: Set<AccountPlatform> = []
    ) {
        self.id = id
        self.email = email
        self.password = password
        self.isGenerated = isGenerated
        self.activePlatforms = activePlatforms
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case email
        case password
        case isGenerated
        case activePlatforms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        password = try container.decode(String.self, forKey: .password)
        isGenerated = try container.decodeIfPresent(Bool.self, forKey: .isGenerated) ?? false
        activePlatforms = try container.decodeIfPresent(Set<AccountPlatform>.self, forKey: .activePlatforms) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(email, forKey: .email)
        try container.encode(password, forKey: .password)
        try container.encode(isGenerated, forKey: .isGenerated)
        try container.encode(activePlatforms, forKey: .activePlatforms)
    }
}

struct SeedCredential: Codable {
    let email: String
    let password: String
}
