import Foundation

enum ProxySecrets {
    private static let config: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "ProxyConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }()

    static let host = config["host"] as? String ?? ""
    static let port = config["port"] as? Int ?? 0
    static let username = config["username"] as? String ?? ""
    static let password = config["password"] as? String ?? ""

    static var isConfigured: Bool {
        !host.isEmpty && port > 0 && !username.isEmpty && !password.isEmpty
    }
}
