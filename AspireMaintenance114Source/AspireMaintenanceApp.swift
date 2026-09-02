import SwiftUI

@main
struct AspireMaintenanceApp: App {
    @StateObject private var store = AspireStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
                .task {
                    await store.syncEmployeeVisitCloud()
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 20_000_000_000)
                        await store.syncEmployeeVisitCloud()
                    }
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task {
                    await store.refreshOverdueNotifications()
                    await store.syncEmployeeVisitCloud()
                }
            }
        }
    }
}
