import SwiftUI

struct RootView: View {
    @EnvironmentObject private var player: PlayerManager

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "rectangle.stack.fill") }
            BrowserView()
                .tabItem { Label("Browser", systemImage: "safari.fill") }
            DownloadsView()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle.fill") }
            ConverterView()
                .tabItem { Label("Convert", systemImage: "arrow.triangle.2.circlepath") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerView()
        }
        .sheet(isPresented: $player.isFullPlayerPresented) {
            NowPlayingView()
        }
    }
}
