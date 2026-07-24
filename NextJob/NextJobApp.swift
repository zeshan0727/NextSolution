import SwiftUI

@main
struct NextJobApp: App {
    @StateObject private var store = JobStore.shared

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
        }
    }
}
