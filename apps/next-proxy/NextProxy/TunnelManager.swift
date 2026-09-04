import Foundation
import NetworkExtension

@MainActor
final class TunnelManager: ObservableObject {
    static let shared = TunnelManager()

    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var isInstalled = false
    @Published var autoConnect = true
    @Published private(set) var healthText = "Not checked"
    @Published private(set) var exitIP = "—"

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?
    private var healthTask: Task<Void, Never>?

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
            Task { @MainActor in
                guard let self else { return }
                self.status = connection.status
                self.updateHealthMonitoring()
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        healthTask?.cancel()
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
                updateHealthMonitoring()
            } else {
                manager = nil
                isInstalled = false
                status = .invalid
                healthText = "Not installed"
                exitIP = "—"
            }
        } catch {
            manager = nil
            isInstalled = false
            status = .invalid
            healthText = "Unable to load VPN configuration"
            exitIP = "—"
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
            updateHealthMonitoring()
        } catch {
            healthText = "Connect failed: \(error.localizedDescription)"
            NSLog("NextProxy install/connect error: %@", error.localizedDescription)
        }
    }

    func disconnect() {
        healthTask?.cancel()
        healthTask = nil
        healthText = "Disconnected"
        exitIP = "—"
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
            healthText = "Auto Connect update failed"
            NSLog("NextProxy on-demand update error: %@", error.localizedDescription)
        }
    }

    func refreshHealth() async {
        guard status == .connected else {
            healthText = "Tunnel not connected"
            exitIP = "—"
            return
        }

        healthText = "Checking…"

        let providerOK = await pingProvider()
        guard providerOK else {
            healthText = "Tunnel provider not responding"
            exitIP = "—"
            return
        }

        if let ip = await fetchExitIP() {
            exitIP = ip
            healthText = "Healthy"
        } else {
            exitIP = "Unavailable"
            healthText = "Tunnel responding • IP check failed"
        }
    }

    private func updateHealthMonitoring() {
        healthTask?.cancel()
        healthTask = nil

        guard status == .connected else {
            if status == .connecting || status == .reasserting {
                healthText = "Connecting…"
            } else if status == .disconnected {
                healthText = "Disconnected"
                exitIP = "—"
            }
            return
        }

        healthTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.refreshHealth()

                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                } catch {
                    break
                }
            }
        }
    }

    private func pingProvider() async -> Bool {
        guard let session = manager?.connection as? NETunnelProviderSession else {
            return false
        }

        return await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(Data("health".utf8)) { data in
                    guard let data,
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          object["ok"] as? Bool == true else {
                        continuation.resume(returning: false)
                        return
                    }
                    continuation.resume(returning: true)
                }
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    private func fetchExitIP() async -> String? {
        guard let url = URL(string: "https://api.ipify.org?format=json") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ip = object["ip"] as? String,
                  !ip.isEmpty else {
                return nil
            }
            return ip
        } catch {
            return nil
        }
    }
}

enum AppConfig {
    static let providerBundleIdentifier = "cc.nextsolution.NextProxy.PacketTunnel"
}
