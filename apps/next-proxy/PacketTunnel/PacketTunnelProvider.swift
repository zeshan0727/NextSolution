import Foundation
import NetworkExtension
import Tun2SocksKit

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var startedAt = Date()

    override func startTunnel(
        options: [String : NSObject]? = nil,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard ProxySecrets.isConfigured else {
            completionHandler(TunnelError.credentialsNotConfigured)
            return
        }

        startedAt = Date()

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: ProxySecrets.host)
        settings.mtu = 1400

        // Capture all IPv4 traffic.
        let ipv4 = NEIPv4Settings(
            addresses: ["198.18.0.1"],
            subnetMasks: ["255.255.255.255"]
        )
        ipv4.includedRoutes = [NEIPv4Route.default()]
        ipv4.excludedRoutes = []
        settings.ipv4Settings = ipv4

        // Capture IPv6 as well instead of allowing a direct IPv6 path.
        // If the upstream SOCKS proxy can't service a destination, it fails closed.
        let ipv6 = NEIPv6Settings(
            addresses: ["fd00:198:18::1"],
            networkPrefixLengths: [128]
        )
        ipv6.includedRoutes = [NEIPv6Route.default()]
        ipv6.excludedRoutes = []
        settings.ipv6Settings = ipv6

        // Resolve DNS through encrypted DNS while the default route is captured.
        if #available(iOS 14.0, *) {
            let doh = NEDNSOverHTTPSSettings(servers: ["1.1.1.1", "1.0.0.1"])
            doh.serverURL = URL(string: "https://cloudflare-dns.com/dns-query")
            doh.matchDomains = [""]
            settings.dnsSettings = doh
        }

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else {
                completionHandler(TunnelError.providerUnavailable)
                return
            }

            if let error {
                completionHandler(error)
                return
            }

            let config = self.makeTun2SocksConfig()
            Socks5Tunnel.run(withConfig: .string(content: config)) { code in
                if code != 0 {
                    NSLog("NextProxy tun2socks exited with code %d", code)
                    self.cancelTunnelWithError(TunnelError.tun2socksExited(code))
                }
            }

            completionHandler(nil)
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func wake() {}

    override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)? = nil
    ) {
        guard let request = String(data: messageData, encoding: .utf8),
              request == "health" else {
            completionHandler?(nil)
            return
        }

        let uptime = max(0, Int(Date().timeIntervalSince(startedAt)))
        let payload: [String: Any] = [
            "ok": true,
            "uptime": uptime,
            "proxyHost": ProxySecrets.host,
            "strictRouting": true
        ]

        let response = try? JSONSerialization.data(withJSONObject: payload)
        completionHandler?(response)
    }

    private func makeTun2SocksConfig() -> String {
        """
        tunnel:
          mtu: 1400

        socks5:
          port: \(ProxySecrets.port)
          address: \(ProxySecrets.host)
          udp: 'tcp'
          username: '\(yamlEscape(ProxySecrets.username))'
          password: '\(yamlEscape(ProxySecrets.password))'

        misc:
          task-stack-size: 24576
          tcp-buffer-size: 4096
          max-session-count: 512
          connect-timeout: 8000
          read-write-timeout: 60000
          log-file: stderr
          log-level: error
          limit-nofile: 4096
        """
    }

    private func yamlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}

enum TunnelError: LocalizedError {
    case credentialsNotConfigured
    case providerUnavailable
    case tun2socksExited(Int32)

    var errorDescription: String? {
        switch self {
        case .credentialsNotConfigured:
            return "Proxy credentials are not configured."
        case .providerUnavailable:
            return "Packet tunnel provider became unavailable."
        case .tun2socksExited(let code):
            return "tun2socks exited with code \(code)."
        }
    }
}
