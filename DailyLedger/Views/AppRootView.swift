import SwiftUI

private enum AppTab: Hashable {
    case home
    case accounts
    case transactions
    case reports
    case settings
}

private struct AddSheet: Identifiable {
    let id = UUID()
    let type: TransactionType
}

struct AppRootView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .home
    @State private var addSheet: AddSheet?
    @State private var showingTransfer = false
    @State private var tabResetIDs: [AppTab: UUID] = [
        .home: UUID(), .accounts: UUID(), .transactions: UUID(),
        .reports: UUID(), .settings: UUID()
    ]

    var body: some View {
        TabView(selection: tabSelection) {
            DashboardView(onAdd: presentAdd, onTransfer: { showingTransfer = true })
                .id(tabResetIDs[.home])
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            AccountsView()
                .id(tabResetIDs[.accounts])
                .tabItem { Label("Accounts", systemImage: "creditcard.fill") }
                .tag(AppTab.accounts)

            TransactionsView(onAdd: presentAdd, onTransfer: { showingTransfer = true })
                .id(tabResetIDs[.transactions])
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle.fill") }
                .tag(AppTab.transactions)

            ReportsView()
                .id(tabResetIDs[.reports])
                .tabItem { Label("Reports", systemImage: "chart.bar.fill") }
                .tag(AppTab.reports)

            SettingsView()
                .id(tabResetIDs[.settings])
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .sheet(item: $addSheet) { sheet in
            AddTransactionView(initialType: sheet.type)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingTransfer) {
            TransferView()
                .environmentObject(store)
        }
        .onAppear(perform: consumeShortcutRequest)
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            store.reload()
            consumeShortcutRequest()
        }
        .alert("Daily Ledger", isPresented: errorBinding) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == selectedTab {
                    tabResetIDs[newTab] = UUID()
                } else {
                    selectedTab = newTab
                }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }

    private func presentAdd(_ type: TransactionType) {
        addSheet = AddSheet(type: type)
    }

    private func consumeShortcutRequest() {
        guard let type = ShortcutRouter.consumePendingType() else { return }
        selectedTab = .home
        addSheet = AddSheet(type: type)
    }
}
