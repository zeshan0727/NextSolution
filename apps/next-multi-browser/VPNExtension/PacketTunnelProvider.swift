import Foundation
import TunnelKitOpenVPNAppExtension

final class PacketTunnelProvider: OpenVPNTunnelProvider {
    override func startTunnel(options: [String: NSObject]? = nil) async throws {
        dataCountInterval = 3
        try await super.startTunnel(options: options)
    }
}
