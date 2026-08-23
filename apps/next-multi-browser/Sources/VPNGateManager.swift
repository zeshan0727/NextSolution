import Foundation
import TunnelKit
import TunnelKitOpenVPN

let nextMultiBrowserVPNAppGroup = "group.com.nextsolution.multibrowser"
let nextMultiBrowserVPNTunnelIdentifier = "com.nextsolution.multibrowser.vpn"

struct VPNGateServer: Hashable {
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

    var errorDescription: String? {
        switch self {
        case .invalidFeed:
            return "The VPN Gate server list could not be read."
        case .invalidProfile:
            return "This VPN server has an invalid OpenVPN profile."
        case .noServers:
            return "No usable VPN Gate servers are available right now."
        }
    }
}

final class VPNGateManager {
    static let shared = VPNGateManager()

    private let vpn = NetworkExtensionVPN()
    private let keychain = Keychain(group: nextMultiBrowserVPNAppGroup)
    private let feedURL = URL(string: "https://www.vpngate.net/api/iphone/")!

    private(set) var connectedServer: VPNGateServer?

    private init() {
        Task { await vpn.prepare() }
    }

    func fetchServers() async throws -> [VPNGateServer] {
        var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("NextMultiBrowser/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw VPNGateError.invalidFeed
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw VPNGateError.invalidFeed
        }

        var servers: [VPNGateServer] = []
        servers.reserveCapacity(512)

        for rawLine in text.split(whereSeparator: \Character.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("*") else { continue }
            let fields = Self.parseCSVLine(line)
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

        guard !servers.isEmpty else { throw VPNGateError.noServers }

        // Keep a useful number of fast choices per country instead of thousands of rows.
        let grouped = Dictionary(grouping: servers) { $0.countryCode }
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
