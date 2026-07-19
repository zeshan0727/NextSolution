import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: LedgerStore
    let onAdd: (TransactionType) -> Void
    let onTransfer: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    BalanceCard(
                        balance: allTimeBalance,
                        income: monthTotals.income,
                        expense: monthTotals.expense,
                        currencyCode: store.currencyCode
                    )
                    quickActions
                    recentTransactions
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(AppTheme.page)
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        HStack {
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

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick add")
                .font(.headline)
            HStack(spacing: 12) {
                QuickActionButton(
                    title: "Income",
                    subtitle: "Money received",
                    icon: "plus",
                    colors: [AppTheme.green, AppTheme.teal]
                ) { onAdd(.income) }

                QuickActionButton(
                    title: "Expense",
                    subtitle: "Money spent",
                    icon: "minus",
                    colors: [AppTheme.orange, AppTheme.red]
                ) { onAdd(.expense) }
            }
            QuickActionButton(
                title: "Transfer",
                subtitle: "Move money between accounts",
                icon: "arrow.left.arrow.right",
                colors: [AppTheme.purple, AppTheme.blue]
            ) { onTransfer() }
        }
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent transactions")
                    .font(.headline)
                Spacer()
                Text("This month: \(monthTotals.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if store.transactions.isEmpty {
                EmptyLedgerView(
                    title: "No transactions yet",
                    message: "Use one of the colorful buttons above to add your first entry."
                )
                .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.transactions.prefix(6).enumerated()), id: \.element.id) { index, transaction in
                        TransactionRow(transaction: transaction)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                        if index < min(store.transactions.count, 6) - 1 {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .padding(.vertical, 6)
                .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private var monthTotals: LedgerTotals {
        guard let interval = Calendar.current.dateInterval(of: .month, for: Date()) else {
            return LedgerTotals(income: 0, expense: 0, count: 0)
        }
        return store.totals(in: interval)
    }

    private var allTimeBalance: Decimal {
        store.activeAccounts
            .filter { $0.currencyCode == store.currencyCode }
            .reduce(Decimal.zero) { result, account in
                result + store.balance(for: account)
        }
    }
}

private struct QuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.20), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
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
}
