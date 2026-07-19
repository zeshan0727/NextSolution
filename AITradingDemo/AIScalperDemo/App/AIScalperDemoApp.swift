import SwiftUI

@main
struct AIScalperDemoApp: App {
    @StateObject private var engine = PaperTradingEngine()

    var body: some Scene {
        WindowGroup {
            RootTabView(engine: engine)
                .preferredColorScheme(.dark)
        }
    }
}

