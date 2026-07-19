import Combine
import SwiftUI

struct RootTabView: View {
    @ObservedObject var engine: PaperTradingEngine
    private let marketTimer = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(engine: engine)
            }
            .tabItem {
                Label("Trade", systemImage: "chart.xyaxis.line")
            }

            NavigationStack {
                TradeHistoryView(engine: engine)
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            NavigationStack {
                SettingsView(engine: engine)
            }
            .tabItem {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
        }
        .tint(.cyan)
        .onReceive(marketTimer) { _ in
            if engine.marketMode == .simulated {
                engine.advanceMarket()
            }
        }
        .task(id: engine.feedTaskID) {
            await engine.runMarketFeed()
        }
    }
}
