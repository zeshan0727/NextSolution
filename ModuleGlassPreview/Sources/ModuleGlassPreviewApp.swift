import SwiftUI

@main
struct ModuleGlassPreviewApp: App {
    @StateObject private var store = ModuleGlassStore()
    @StateObject private var autoTester = ModuleGlassAutoTester()

    var body: some Scene {
        WindowGroup {
            TabView {
                CollectorView(store: store, tester: autoTester)
                    .tabItem { Label("Collector", systemImage: "waveform.path.ecg.rectangle.fill") }

                ModulesView(store: store)
                    .tabItem { Label("Modules", systemImage: "square.grid.3x3.fill") }

                LiveView(store: store)
                    .tabItem { Label("Live", systemImage: "bolt.fill") }

                PreviewView(store: store)
                    .tabItem { Label("Preview", systemImage: "rectangle.3.group.fill") }
            }
            .tint(.blue)
        }
    }
}
