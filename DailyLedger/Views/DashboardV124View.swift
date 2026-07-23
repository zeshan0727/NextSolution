import SwiftUI
import UniformTypeIdentifiers

private enum RecoveredSpendCard: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case thisWeek = "This Week"
    case lastWeek = "Last Week"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: return "clock.fill"
        case .yesterday: return "sun.haze.fill"
        case .thisWeek: return "calendar.badge.clock"
        case .lastWeek: return "calendar"
        }
    }

    var colors: [Color] {
        switch self {
        case .today: return [AppTheme.orange, AppTheme.red]
        case .yesterday: return [AppTheme.purple, AppTheme.blue]
        case .thisWeek: return [AppTheme.teal, AppTheme.green]
        case .lastWeek: return [AppTheme.blue, AppTheme.purple]
        }
    }
}

private struct RecoveredSpendSelection: Identifiable {
    let id = UUID()
    let title: String
    let interval: DateInterval
}

struct DashboardV124View: View {
    @EnvironmentObject private var store: LedgerStore
    let onAdd: (TransactionType) -> Void
    let onTransfer: () -> Void

    @AppStorage("DashboardSpendCardOrderV124") private var storedOrder = ""
    @State private var cardOrder = RecoveredSpendCard.allCases
    @State private var draggingCard: RecoveredSpendCard?
    @State private var editingCards = false
    @State private var selectedPeriod: RecoveredSpendSelection?

    private let grid = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    header
                    spendCards
                    balanceSection
                    quickActions
                    recentTransactions
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(AppTheme.page)
            .navigationBarHidden(true)
            .onAppear {
                loadOrder()
            }
            .onChange(of: cardOrder) { _ in
                saveOrder()
            }
            .sheet(item: $selectedPeriod) { selection in
                NavigationStack {
                    PeriodTransactionsView(kind: .expenses, interval: selection.interval)
                        .navigationTitle(selection.title)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { selectedPeriod = nil }
                            }
                        }
                }
                .environmentObject(store)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Daily Ledger")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text("Your money at a glance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(AppTheme.balanceGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.top, 16)
    }

    private var spendCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spending pulse")
                        .font(.headline)
                    Text(editingCards ? "Drag cards to rearrange" : "Tap any card to open its transactions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(editingCards ? "Done" : "Edit") {
                    withAnimation(.snappy) { editingCards.toggle() }
                }
                .font(.subheadline.weight(.semibold))
            }

            LazyVGrid(columns: grid, spacing: 12) {
                ForEach(cardOrder) { card in
                    spendCard(card)
                        .onDrag {
                            draggingCard = card
                            return NSItemProvider(object: card.rawValue as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: RecoveredSpendDropDelegate(
                                item: card,
                                items: $cardOrder,
                                dragging: $draggingCard,
                                enabled: editingCards
                            )
                        )
                        .scaleEffect(draggingCard == card ? 1.03 : 1)
                        .animation(.easeInOut(duration: 0.16), value: draggingCard)
                }
            }
        }
    }

    private func spendCard(_ card: RecoveredSpendCard) -> some View {
        Button {
            guard !editingCards, let interval = interval(for: card) else { return }
            selectedPeriod = RecoveredSpendSelection(title: "\(card.rawValue) Expenses", interval: interval)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: card.icon)
                        .font(.headline)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.18), in: Circle())
                    Spacer()
                    if editingCards {
                        Image(systemName: "line.3.horizontal")
                            .font(.caption.bold())
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.rawValue)
                        .font(.caption.weight(.semibold))
                    Text(DisplayFormat.currency(expense(for: card), code: store.currencyCode))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .padding(14)
            .background(
                LinearGradient(colors: card.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(alignment: .topTrailing) {
                if editingCards {
                    Image(systemName: "hand.draw.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var balanceSection: some View {
        let interval = Calendar.current.dateInterval(of: .month, for: Date())!
        let totals = store.totals(in: interval)
        return BalanceCard(
            balance: store.remainingBalance(),
            income: totals.income,
            expense: totals.expense,
            loan: totals.loan,
            currencyCode: store.currencyCode,
            accountSummary: "All \(store.currencyCode) accounts",
            action: {}
        )
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick add")
                .font(.headline)
            HStack(spacing: 12) {
                recoveredAction(
                    title: "Income",
                    subtitle: "Money received",
                    icon: "plus",
                    colors: [AppTheme.green, AppTheme.teal]
                ) { onAdd(.income) }

                recoveredAction(
                    title: "Expense",
                    subtitle: "Money spent",
                    icon: "minus",
                    colors: [AppTheme.orange, AppTheme.red]
                ) { onAdd(.expense) }
            }

            recoveredAction(
                title: "Transfer",
                subtitle: "Move money between accounts",
                icon: "arrow.left.arrow.right",
                colors: [AppTheme.purple, AppTheme.blue]
            ) { onTransfer() }
        }
    }

    private func recoveredAction(
        title: String,
        subtitle: String,
        icon: String,
        colors: [Color],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.20), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent transactions")
                    .font(.headline)
                Spacer()
                Text("Latest 8")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if visibleTransactions.isEmpty {
                EmptyLedgerView(
                    title: "No transactions yet",
                    message: "Use the quick-add buttons to record your first entry."
                )
                .padding(12)
                .recoveredSurface(tint: AppTheme.purple)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleTransactions.prefix(8).enumerated()), id: \.element.id) { index, transaction in
                        TransactionRow(transaction: transaction)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                        if index < min(visibleTransactions.count, 8) - 1 {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .padding(.vertical, 6)
                .recoveredSurface(tint: AppTheme.blue)
            }
        }
    }

    private var visibleTransactions: [LedgerTransaction] {
        store.transactions.filter {
            guard let account = store.account(withID: $0.accountID) else { return true }
            return account.currencyCode == store.currencyCode
        }
    }

    private func interval(for card: RecoveredSpendCard) -> DateInterval? {
        let calendar = Calendar.current
        switch card {
        case .today:
            return calendar.dateInterval(of: .day, for: Date())
        case .yesterday:
            let date = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            return calendar.dateInterval(of: .day, for: date)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: Date())
        case .lastWeek:
            let date = calendar.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
            return calendar.dateInterval(of: .weekOfYear, for: date)
        }
    }

    private func expense(for card: RecoveredSpendCard) -> Decimal {
        guard let interval = interval(for: card) else { return 0 }
        return store.transactions.lazy.filter {
            $0.type == .expense &&
            interval.contains($0.date) &&
            (store.account(withID: $0.accountID)?.currencyCode ?? store.currencyCode) == store.currencyCode
        }.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private func loadOrder() {
        let decoded = storedOrder
            .split(separator: ",")
            .compactMap { RecoveredSpendCard(rawValue: String($0)) }
        let missing = RecoveredSpendCard.allCases.filter { !decoded.contains($0) }
        cardOrder = decoded.isEmpty ? RecoveredSpendCard.allCases : decoded + missing
    }

    private func saveOrder() {
        storedOrder = cardOrder.map(\.rawValue).joined(separator: ",")
    }
}

private struct RecoveredSpendDropDelegate: DropDelegate {
    let item: RecoveredSpendCard
    @Binding var items: [RecoveredSpendCard]
    @Binding var dragging: RecoveredSpendCard?
    let enabled: Bool

    func dropEntered(info: DropInfo) {
        guard enabled,
              let dragging,
              dragging != item,
              let from = items.firstIndex(of: dragging),
              let to = items.firstIndex(of: item) else { return }

        withAnimation(.snappy) {
            items.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: to > from ? to + 1 : to
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: enabled ? .move : .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return enabled
    }
}
