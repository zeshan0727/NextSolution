import Foundation

enum ProxySecrets {
    static let host = "195.40.57.11"
    static let port = 7731

    // Build-time placeholders. The finished TIPA is patched locally so the
    // user's real credentials never enter this public repository.
    static let username = "USER0000"
    static let password = "PASS00000000"

    static var isConfigured: Bool {
        !username.isEmpty && !password.isEmpty
    }
}
