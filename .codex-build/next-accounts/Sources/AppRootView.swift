import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $router.selectedTab) {
            CredentialListView()
                .tabItem {
                    Label("Accounts", systemImage: "person.crop.rectangle.stack.fill")
                }
                .tag(AppTab.accounts)

            BrowserView()
                .tabItem {
                    Label("Browser", systemImage: "globe")
                }
                .tag(AppTab.browser)
        }
        .tint(AppTheme.accent)
        .overlay {
            if scenePhase != .active {
                PrivacyCoverView()
            }
        }
    }
}
