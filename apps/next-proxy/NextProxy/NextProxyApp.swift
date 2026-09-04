import SwiftUI

@main
struct NextProxyApp: App {
    @StateObject private var tunnel = TunnelManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tunnel)
                .task {
                    await tunnel.load()
                }
        }
    }
}
