import Foundation
import NetworkExtension

@MainActor
final class TunnelManager: ObservableObject {
    static let shared = TunnelManager()

    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var isInstalled = false
    @Published var autoConnect = true

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    var isConnected: Bool {
        status == .connected || status == .connecting || status == .reasserting
    }

    var statusText: String {
        switch status {
        case .invalid: return "Not Installed"
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .reasserting: return "Reconnecting…"
        case .disconnecting: return "Disconnecting…"
        @unknown default: return "Unknown"
        }
    }

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let connection = note.object as? NEVPNConnection else { return }
            Task { @MainActor in self?.status = connection.status }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func load() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            if let existing = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == AppConfig.providerBundleIdentifier
            }) {
                manager = existing
                isInstalled = true
                autoConnect = existing.isOnDemandEnabled
                status = existing.connection.status
            } else {
                manager = nil
                isInstalled = false
                status = .invalid
            }
        } catch {
            manager = nil
            isInstalled = false
            status = .invalid
        }
    }

    func installAndConnect() async {
        do {
            let mgr = manager ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = AppConfig.providerBundleIdentifier
            proto.serverAddress = "Webshare Residential Proxy"
            proto.disconnectOnSleep = false

            mgr.protocolConfiguration = proto
            mgr.localizedDescription = "Next Proxy"
            mgr.isEnabled = true
            mgr.onDemandRules = [NEOnDemandRuleConnect()]
            mgr.isOnDemandEnabled = autoConnect

            try await mgr.saveToPreferences()
            try await mgr.loadFromPreferences()

            manager = mgr
            isInstalled = true
            status = mgr.connection.status

            try mgr.connection.startVPNTunnel()
        } catch {
            NSLog("NextProxy install/connect error: %@", error.localizedDescription)
        }
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
    }

    func setAutoConnect(_ enabled: Bool) async {
        autoConnect = enabled
        guard let mgr = manager else { return }
        do {
            mgr.onDemandRules = enabled ? [NEOnDemandRuleConnect()] : []
            mgr.isOnDemandEnabled = enabled
            try await mgr.saveToPreferences()
            try await mgr.loadFromPreferences()
        } catch {
            NSLog("NextProxy on-demand update error: %@", error.localizedDescription)
        }
    }
}

enum AppConfig {
    static let providerBundleIdentifier = "cc.nextsolution.NextProxy.PacketTunnel"
}
