import SwiftUI
import NetworkExtension

struct ContentView: View {
    @EnvironmentObject private var tunnel: TunnelManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: tunnel.isConnected ? "lock.shield.fill" : "lock.shield")
                    .font(.system(size: 64))

                Text("Next Proxy")
                    .font(.largeTitle.bold())

                Text(tunnel.statusText)
                    .font(.headline)

                Text("Fixed Webshare tunnel • iOS 16+")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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

                Toggle("Auto Connect", isOn: Binding(
                    get: { tunnel.autoConnect },
                    set: { newValue in Task { await tunnel.setAutoConnect(newValue) } }
                ))
                .disabled(!tunnel.isInstalled)

                Spacer()

                Text("Uses Apple's Network Extension framework with fail-closed routing for unsupported traffic.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Next Proxy")
        }
    }
}
