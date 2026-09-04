import SwiftUI
import NetworkExtension

struct ContentView: View {
    @EnvironmentObject private var tunnel: TunnelManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: tunnel.isConnected ? "lock.shield.fill" : "lock.shield")
                        .font(.system(size: 64))

                    Text("Next Proxy")
                        .font(.largeTitle.bold())

                    Text(tunnel.statusText)
                        .font(.headline)

                    Text("Fixed Webshare tunnel • iOS 16+")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        statusRow("Tunnel Health", tunnel.healthText)
                        statusRow("Observed Exit IP", tunnel.exitIP)
                        statusRow("DNS Protection", "Encrypted DoH")
                        statusRow("IPv6 Protection", "Captured / fail closed")
                        statusRow("Routing", "Strict while connected")
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                    Button {
                        Task {
                            if tunnel.isConnected {
                                tunnel.disconnect()
                            } else {
                                await tunnel.installAndConnect()
                            }
                        }
                    } label: {
                        Text(tunnel.isConnected ? "Disconnect" : "Install & Connect")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Refresh Health") {
                        Task { await tunnel.refreshHealth() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(tunnel.status != .connected)

                    Toggle("Auto Connect", isOn: Binding(
                        get: { tunnel.autoConnect },
                        set: { newValue in Task { await tunnel.setAutoConnect(newValue) } }
                    ))
                    .disabled(!tunnel.isInstalled)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Fail-closed IPv4/IPv6 routes", systemImage: "checkmark.shield")
                        Label("DNS-over-HTTPS", systemImage: "checkmark.shield")
                        Label("Connect On Demand", systemImage: "checkmark.shield")
                        Label("Automatic tunnel health check", systemImage: "checkmark.shield")
                        Label("No intentional direct proxy fallback", systemImage: "checkmark.shield")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Strict routing applies while the tunnel is active. iOS always reserves some system/control-plane traffic, and true supervised Always-On VPN is not available on a normal personal iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Next Proxy")
        }
    }

    @ViewBuilder
    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }
}
