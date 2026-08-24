import Foundation
import TunnelKit
import TunnelKitOpenVPN

let nextMultiBrowserVPNAppGroup = "group.com.nextsolution.multibrowser"
let nextMultiBrowserVPNTunnelIdentifier = "com.nextsolution.multibrowser.vpn"

struct VPNGateServer: Hashable, Codable {
    let hostName: String
    let ipAddress: String
    let score: Int
    let ping: Int?
    let speed: Int64
    let countryName: String
    let countryCode: String
    let sessions: Int
    let uptime: Int64
    let configBase64: String

    var speedMbps: Double {
        Double(speed) / 1_000_000.0
    }

    var decodedOpenVPNProfile: String? {
        guard let data = Data(base64Encoded: configBase64, options: [.ignoreUnknownCharacters]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum VPNGateError: LocalizedError {
    case invalidFeed
    case invalidProfile
    case noServers
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidFeed:
            return "The VPN Gate server list could not be read."
        case .invalidProfile:
            return "This VPN server has an invalid OpenVPN profile."
        case .noServers:
            return "No usable VPN Gate servers are available right now."
        case .unavailable:
            return "VPN Gate did not respond from the main server or available mirrors. Try Refresh again later."
        }
    }
}

final class VPNGateManager {
    static let shared = VPNGateManager()

    private let vpn = NetworkExtensionVPN()
    private let keychain = Keychain(group: nextMultiBrowserVPNAppGroup)
    private let defaults = UserDefaults.standard
    private let mirrorDefaultsKey = "NextMultiBrowser.VPNGateMirrors"
    private let cacheFileName = "vpngate-servers-v2.json"

    private let primaryFeedURL = URL(string: "https://www.vpngate.net/api/iphone/")!
    private let mirrorListURL = URL(string: "https://www.vpngate.net/EN/sites.aspx")!

    // These are only bootstrap fallbacks. VPN Gate rotates its public mirror list,
    // and discovered mirrors are persisted after the first successful discovery.
    private let bootstrapMirrorFeeds: [URL] = [
        URL(string: "http://121.141.108.75:12433/api/iphone/")!,
        URL(string: "http://211.196.188.156:65104/api/iphone/")!,
        URL(string: "http://183.99.115.118:31489/api/iphone/")!
    ]

    private(set) var connectedServer: VPNGateServer?
    private(set) var lastFetchUsedCache = false
    private(set) var lastSuccessfulFeedDescription: String?

    private init() {
        Task { await vpn.prepare() }
    }

    func fetchServers() async throws -> [VPNGateServer] {
        lastFetchUsedCache = false
        lastSuccessfulFeedDescription = nil

        var firstWave: [URL] = [primaryFeedURL]
        firstWave.append(contentsOf: savedMirrorFeeds())
        firstWave.append(contentsOf: bootstrapMirrorFeeds)
        firstWave = uniqueURLs(firstWave)

        if let result = await firstWorkingFeed(Array(firstWave.prefix(6))) {
            saveCache(result.servers)
            lastSuccessfulFeedDescription = result.url.host ?? result.url.absoluteString
            return result.servers
        }

        let discovered = await discoverMirrorFeeds()
        if !discovered.isEmpty {
            saveMirrorFeeds(discovered)
            if let result = await firstWorkingFeed(Array(discovered.prefix(10))) {
                saveCache(result.servers)
                lastSuccessfulFeedDescription = result.url.host ?? result.url.absoluteString
                return result.servers
            }
        }

        if let cached = loadCache(), !cached.isEmpty {
            lastFetchUsedCache = true
            lastSuccessfulFeedDescription = "cached list"
            return cached
        }

        throw VPNGateError.unavailable
    }

    func connect(to server: VPNGateServer) async throws {
        guard let profile = server.decodedOpenVPNProfile else {
            throw VPNGateError.invalidProfile
        }

        let result = try OpenVPN.ConfigurationParser.parsed(fromContents: profile)
        var provider = OpenVPN.ProviderConfiguration(
            "Next Multi Browser • \(server.countryName)",
            appGroup: nextMultiBrowserVPNAppGroup,
            configuration: result.configuration
        )
        provider.username = "vpn"
        provider.masksPrivateData = true

        let passwordReference = try keychain.set(
            password: "vpn",
            for: "vpn",
            context: nextMultiBrowserVPNTunnelIdentifier
        )
        var extra = NetworkExtensionExtra()
        extra.passwordReference = passwordReference

        await vpn.prepare()
        try await vpn.reconnect(
            nextMultiBrowserVPNTunnelIdentifier,
            configuration: provider,
            extra: extra,
            after: .seconds(1)
        )
        connectedServer = server
    }

    func disconnect() async {
        await vpn.disconnect()
        connectedServer = nil
    }

    private struct FeedResult {
        let url: URL
        let servers: [VPNGateServer]
    }

    private func firstWorkingFeed(_ urls: [URL]) async -> FeedResult? {
        guard !urls.isEmpty else { return nil }

        return await withTaskGroup(of: FeedResult?.self) { group in
            for url in urls {
                group.addTask {
                    await Self.fetchAndParseFeed(url)
                }
            }

            for await result in group {
                if let result, !result.servers.isEmpty {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    private static func fetchAndParseFeed(_ url: URL) async -> FeedResult? {
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 9)
            request.setValue("NextMultiBrowser/1.1.0 iOS", forHTTPHeaderField: "User-Agent")
            request.setValue("text/plain,text/csv,*/*", forHTTPHeaderField: "Accept")

            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 9
            configuration.timeoutIntervalForResource = 12
            configuration.waitsForConnectivity = false
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }

            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard data.count > 100 else { return nil }
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                return nil
            }
            let servers = parseServerFeed(text)
            guard !servers.isEmpty else { return nil }
            return FeedResult(url: url, servers: servers)
        } catch {
            return nil
        }
    }

    private func discoverMirrorFeeds() async -> [URL] {
        do {
            var request = URLRequest(url: mirrorListURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 7)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")

            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 7
            configuration.timeoutIntervalForResource = 9
            configuration.waitsForConnectivity = false
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }

            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return []
            }
            guard let html = String(data: data, encoding: .utf8) else { return [] }

            let pattern = #"https?://[0-9A-Za-z\.\-]+(?::[0-9]+)?/(?:en|EN)/"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            var feeds: [URL] = []

            for match in regex.matches(in: html, range: range) {
                guard let swiftRange = Range(match.range, in: html) else { continue }
                var base = String(html[swiftRange])
                if base.lowercased().hasSuffix("/en/") {
                    base.removeLast(4)
                }
                guard let url = URL(string: base + "/api/iphone/") else { continue }
                feeds.append(url)
            }
            return uniqueURLs(feeds)
        } catch {
            return []
        }
    }

    private static func parseServerFeed(_ text: String) -> [VPNGateServer] {
        var servers: [VPNGateServer] = []
        servers.reserveCapacity(512)

        for rawLine in text.split(whereSeparator: \Character.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("*") else { continue }
            let fields = parseCSVLine(line)
            guard fields.count >= 15 else { continue }

            let base64 = fields[14].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !base64.isEmpty,
                  Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) != nil else { continue }

            let server = VPNGateServer(
                hostName: fields[0],
                ipAddress: fields[1],
                score: Int(fields[2]) ?? 0,
                ping: Int(fields[3]),
                speed: Int64(fields[4]) ?? 0,
                countryName: fields[5].isEmpty ? fields[6] : fields[5],
                countryCode: fields[6].uppercased(),
                sessions: Int(fields[7]) ?? 0,
                uptime: Int64(fields[8]) ?? 0,
                configBase64: base64
            )
            servers.append(server)
        }

        let grouped = Dictionary(grouping: servers) { $0.countryCode.isEmpty ? $0.countryName : $0.countryCode }
        var trimmed: [VPNGateServer] = []
        for values in grouped.values {
            let best = values.sorted {
                if $0.score == $1.score { return $0.speed > $1.speed }
                return $0.score > $1.score
            }.prefix(20)
            trimmed.append(contentsOf: best)
        }

        return trimmed.sorted {
            if $0.countryName == $1.countryName {
                if $0.score == $1.score { return $0.speed > $1.speed }
                return $0.score > $1.score
            }
            return $0.countryName.localizedCaseInsensitiveCompare($1.countryName) == .orderedAscending
        }
    }

    private func cacheURL() -> URL? {
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return directory.appendingPathComponent(cacheFileName)
    }

    private func saveCache(_ servers: [VPNGateServer]) {
        guard let url = cacheURL(), let data = try? JSONEncoder().encode(servers) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadCache() -> [VPNGateServer]? {
        guard let url = cacheURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([VPNGateServer].self, from: data)
    }

    private func savedMirrorFeeds() -> [URL] {
        (defaults.stringArray(forKey: mirrorDefaultsKey) ?? []).compactMap(URL.init(string:))
    }

    private func saveMirrorFeeds(_ urls: [URL]) {
        defaults.set(urls.prefix(20).map(\.absoluteString), forKey: mirrorDefaultsKey)
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var insideQuotes = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if insideQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    index = line.index(after: next)
                    continue
                }
                insideQuotes.toggle()
            } else if character == ",", !insideQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        fields.append(current)
        return fields
    }
}
