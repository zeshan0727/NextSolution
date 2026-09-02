import SwiftUI

@main
struct AspireMaintenanceApp: App {
    @StateObject private var store = AspireStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await store.refreshOverdueNotifications() }
            }
        }
    }
}
