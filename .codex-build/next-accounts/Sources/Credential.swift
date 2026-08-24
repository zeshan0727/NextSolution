import Foundation

struct Credential: Codable, Equatable, Identifiable {
    let id: UUID
    let email: String
    let password: String
    let isGenerated: Bool

    init(
        id: UUID = UUID(),
        email: String,
        password: String,
        isGenerated: Bool = false
    ) {
        self.id = id
        self.email = email
        self.password = password
        self.isGenerated = isGenerated
    }
}

struct SeedCredential: Codable {
    let email: String
    let password: String
}
