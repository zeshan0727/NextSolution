import SwiftUI

@main
struct ModuleGlassPreviewApp: App {
    @StateObject private var store = ModuleGlassStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                PreviewView(store: store)
                    .tabItem { Label("Preview", systemImage: "rectangle.3.group.fill") }

                ModulesView(store: store)
                    .tabItem { Label("Modules", systemImage: "square.grid.3x3.fill") }

                LiveView(store: store)
                    .tabItem { Label("Live", systemImage: "bolt.fill") }

                DiagnosticsView(store: store)
                    .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            }
            .tint(.blue)
        }
    }
}
