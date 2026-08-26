import Foundation
import Network
import Security
import WebKit

extension Notification.Name {
    static let nextMultiBrowserProxyRouteDidChange = Notification.Name("NextMultiBrowserProxyRouteDidChange")
}

enum BrowserProxyKind: String, Codable, CaseIterable {
    case httpConnect
    case socks5

    var title: String {
        switch self {
        case .httpConnect: return "HTTP CONNECT"
        case .socks5: return "SOCKS5"
        }
    }

    var scheme: String {
        switch self {
        case .httpConnect: return "http"
        case .socks5: return "socks5"
        }
    }
}

struct BrowserProxyRoute: Codable, Equatable {
    var kind: BrowserProxyKind
    var host: String
    var port: UInt16
    var username: String?

    var displayAddress: String {
        "\(host):\(port)"
    }

    var isValid: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && port > 0
    }

    @available(iOS 17.0, *)
    func makeConfiguration(password: String?) -> ProxyConfiguration? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty,
              let nwPort = NWEndpoint.Port(rawValue: port) else {
            return nil
        }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(trimmedHost),
            port: nwPort
        )
        var configuration: ProxyConfiguration
        switch kind {
        case .httpConnect:
            configuration = ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: nil)
        case .socks5:
            configuration = ProxyConfiguration(socksv5Proxy: endpoint)
        }

        configuration.allowFailover = false
        let trimmedUser = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedUser.isEmpty, let password, !password.isEmpty {
            configuration.applyCredential(username: trimmedUser, password: password)
        }
        return configuration
    }
}

struct BrowserProxyParsedRoute {
    let route: BrowserProxyRoute
    let password: String?
}

enum BrowserProxyParser {
    static func parse(_ text: String) -> [BrowserProxyParsedRoute] {
        text
            .components(separatedBy: .newlines)
            .compactMap(parseLine)
    }

    static func parseLine(_ rawLine: String) -> BrowserProxyParsedRoute? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

        if line.contains("://") {
            return parseURLStyle(line)
        }

        if line.contains("@") {
            return parseAtStyle(line)
        }

        let parts = line.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        switch parts.count {
        case 2:
            guard let port = UInt16(parts[1]) else { return nil }
            return BrowserProxyParsedRoute(
                route: BrowserProxyRoute(kind: .httpConnect, host: parts[0], port: port, username: nil),
                password: nil
            )
        case 4:
            guard let port = UInt16(parts[1]) else { return nil }
            return BrowserProxyParsedRoute(
                route: BrowserProxyRoute(kind: .httpConnect, host: parts[0], port: port, username: emptyToNil(parts[2])),
                password: emptyToNil(parts[3])
            )
        default:
            return nil
        }
    }

    private static func parseURLStyle(_ line: String) -> BrowserProxyParsedRoute? {
        guard let components = URLComponents(string: line),
              let host = components.host,
              let intPort = components.port,
              (1...65535).contains(intPort) else {
            return nil
        }

        let scheme = components.scheme?.lowercased() ?? "http"
        let kind: BrowserProxyKind
        switch scheme {
        case "http", "https", "connect": kind = .httpConnect
        case "socks", "socks5", "socks5h": kind = .socks5
        default: return nil
        }

        return BrowserProxyParsedRoute(
            route: BrowserProxyRoute(
                kind: kind,
                host: host,
                port: UInt16(intPort),
                username: emptyToNil(components.user?.removingPercentEncoding)
            ),
            password: emptyToNil(components.password?.removingPercentEncoding)
        )
    }

    private static func parseAtStyle(_ line: String) -> BrowserProxyParsedRoute? {
        let parts = line.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return nil }
        let credentials = parts[0].split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let address = parts[1].split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard credentials.count == 2,
              address.count == 2,
              let port = UInt16(address[1]) else {
            return nil
        }
        return BrowserProxyParsedRoute(
            route: BrowserProxyRoute(
                kind: .httpConnect,
                host: address[0],
                port: port,
                username: emptyToNil(credentials[0])
            ),
            password: emptyToNil(credentials[1])
        )
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

final class BrowserProxyKeychain {
    static let shared = BrowserProxyKeychain()
    private let service = "com.nextsolution.multibrowser.privateproxy"

    func password(for profileIndex: Int) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: profileIndex),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func setPassword(_ password: String?, for profileIndex: Int) {
        deletePassword(for: profileIndex)
        guard let password, !password.isEmpty,
              let data = password.data(using: .utf8) else {
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: profileIndex),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func deletePassword(for profileIndex: Int) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: profileIndex)
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func account(for profileIndex: Int) -> String {
        "profile-\(profileIndex)"
    }
}

final class BrowserProxyStore {
    static let shared = BrowserProxyStore()

    private let defaults: UserDefaults
    private let keychain: BrowserProxyKeychain

    private convenience init() {
        self.init(defaults: .standard, keychain: .shared)
    }

    init(defaults: UserDefaults, keychain: BrowserProxyKeychain) {
        self.defaults = defaults
        self.keychain = keychain
    }

    func route(for profileIndex: Int) -> BrowserProxyRoute? {
        guard (1...BrowserProfileStore.profileCount).contains(profileIndex),
              let data = defaults.data(forKey: routeKey(for: profileIndex)),
              let route = try? JSONDecoder().decode(BrowserProxyRoute.self, from: data),
              route.isValid else {
            return nil
        }
        return route
    }

    func password(for profileIndex: Int) -> String? {
        keychain.password(for: profileIndex)
    }

    func assignedProfileIndices() -> [Int] {
        (1...BrowserProfileStore.profileCount).filter { route(for: $0) != nil }
    }

    func setRoute(
        _ route: BrowserProxyRoute,
        password: String?,
        for profileIndex: Int,
        profileStore: BrowserProfileStore = .shared
    ) {
        guard route.isValid,
              (1...BrowserProfileStore.profileCount).contains(profileIndex),
              let data = try? JSONEncoder().encode(route) else {
            return
        }
        defaults.set(data, forKey: routeKey(for: profileIndex))
        keychain.setPassword(password, for: profileIndex)
        applyRoute(for: profileIndex, profileStore: profileStore)
        postRouteChanged(profileIndex)
    }

    func clearRoute(
        for profileIndex: Int,
        profileStore: BrowserProfileStore = .shared
    ) {
        guard (1...BrowserProfileStore.profileCount).contains(profileIndex) else { return }
        defaults.removeObject(forKey: routeKey(for: profileIndex))
        keychain.deletePassword(for: profileIndex)
        applyRoute(for: profileIndex, profileStore: profileStore)
        postRouteChanged(profileIndex)
    }

    func replaceAll(
        with parsedRoutes: [BrowserProxyParsedRoute],
        profileStore: BrowserProfileStore = .shared
    ) {
        let limited = Array(parsedRoutes.prefix(BrowserProfileStore.profileCount))
        for index in 1...BrowserProfileStore.profileCount {
            if index <= limited.count {
                let parsed = limited[index - 1]
                if let data = try? JSONEncoder().encode(parsed.route) {
                    defaults.set(data, forKey: routeKey(for: index))
                    keychain.setPassword(parsed.password, for: index)
                }
            } else {
                defaults.removeObject(forKey: routeKey(for: index))
                keychain.deletePassword(for: index)
            }
        }
        applyAllPersistedRoutes(profileStore: profileStore)
        NotificationCenter.default.post(
            name: .nextMultiBrowserProxyRouteDidChange,
            object: self,
            userInfo: ["profileIndex": 0]
        )
    }

    func clearAll(profileStore: BrowserProfileStore = .shared) {
        for index in 1...BrowserProfileStore.profileCount {
            defaults.removeObject(forKey: routeKey(for: index))
            keychain.deletePassword(for: index)
        }
        applyAllPersistedRoutes(profileStore: profileStore)
        NotificationCenter.default.post(
            name: .nextMultiBrowserProxyRouteDidChange,
            object: self,
            userInfo: ["profileIndex": 0]
        )
    }

    func applyAllPersistedRoutes(profileStore: BrowserProfileStore = .shared) {
        guard #available(iOS 17.0, *) else { return }
        for index in 1...BrowserProfileStore.profileCount where route(for: index) != nil || profileStore.existingSession(for: index) != nil {
            applyRoute(for: index, profileStore: profileStore)
        }
    }

    func applyRoute(for profileIndex: Int, profileStore: BrowserProfileStore = .shared) {
        guard #available(iOS 17.0, *) else { return }
        let session = profileStore.session(for: profileIndex)
        guard let route = route(for: profileIndex),
              let configuration = route.makeConfiguration(password: password(for: profileIndex)) else {
            session.dataStore.proxyConfigurations = []
            return
        }
        session.dataStore.proxyConfigurations = [configuration]
    }

    private func routeKey(for profileIndex: Int) -> String {
        "NextMultiBrowser.profile.\(profileIndex).proxyRoute"
    }

    private func postRouteChanged(_ profileIndex: Int) {
        let post = {
            NotificationCenter.default.post(
                name: .nextMultiBrowserProxyRouteDidChange,
                object: self,
                userInfo: ["profileIndex": profileIndex]
            )
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }
}
