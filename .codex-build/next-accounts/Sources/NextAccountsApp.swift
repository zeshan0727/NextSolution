import SwiftUI

@main
@MainActor
struct NextAccountsApp: App {
    @StateObject private var store = CredentialStore()
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
                .environmentObject(router)
        }
    }
}
