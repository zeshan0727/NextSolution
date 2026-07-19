import SwiftUI

private enum AppTab: Hashable, CaseIterable {
    case home, accounts, transactions, insights, reports, settings

    var title: String {
        switch self {
        case .home: return "Home"
        case .accounts: return "Accounts"
        case .transactions: return "Transactions"
        case .insights: return "AI"
        case .reports: return "Reports"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .accounts: return "creditcard.fill"
        case .transactions: return "list.bullet.rectangle.fill"
        case .insights: return "sparkles"
        case .reports: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }
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
    @State private var tabRootID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            activeTab
                .id(tabRootID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button {
                        select(tab)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18, weight: .semibold))
                            Text(tab.title)
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(selectedTab == tab ? AppTheme.purple : .secondary)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 5)
            .background(.ultraThinMaterial)
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

    @ViewBuilder
    private var activeTab: some View {
        switch selectedTab {
        case .home:
            DashboardView(onAdd: presentAdd, onTransfer: { showingTransfer = true })
        case .accounts:
            AccountsView()
        case .transactions:
            TransactionsView(onAdd: presentAdd, onTransfer: { showingTransfer = true })
        case .insights:
            InsightsView()
        case .reports:
            ReportsView()
        case .settings:
            SettingsView()
        }
    }

    private func select(_ tab: AppTab) {
        if selectedTab == tab {
            tabRootID = UUID()
        } else {
            selectedTab = tab
            tabRootID = UUID()
        }
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
