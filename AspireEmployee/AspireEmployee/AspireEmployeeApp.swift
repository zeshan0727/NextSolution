import SwiftUI

@main
struct AspireEmployeeApp: App {
    @StateObject private var store = EmployeeVisitStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            EmployeeRootView()
                .environmentObject(store)
                .task {
                    await store.refresh()
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 20_000_000_000)
                        await store.refresh()
                    }
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await store.refresh() }
            }
        }
    }
}
