import SwiftUI

@main
@MainActor
struct NextAccountsApp: App {
    @StateObject private var store = CredentialStore()

    var body: some Scene {
        WindowGroup {
            CredentialListView()
                .environmentObject(store)
        }
    }
}
