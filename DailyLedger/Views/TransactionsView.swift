import SwiftUI

private enum TransactionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case income = "Income"
    case expense = "Expenses"
    var id: String { rawValue }
}

private struct TransactionDayGroup: Identifiable {
    let date: Date
    let title: String
    let transactions: [LedgerTransaction]
    var id: Date { date }
}

struct TransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var filter: TransactionFilter = .all
    @State private var searchText = ""
    @State private var editingTransaction: LedgerTransaction?
    let onAdd: (TransactionType) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Transaction type", selection: $filter) {
                    ForEach(TransactionFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if filteredTransactions.isEmpty {
                    Spacer()
                    EmptyLedgerView(
                        title: searchText.isEmpty ? "No transactions" : "No matching transactions",
                        message: searchText.isEmpty
                            ? "Tap + to record income or an expense."
                            : "Try a different category, amount, or description."
                    )
                    Spacer()
                } else {
                    List {
                        ForEach(groupedDays) { group in
                            Section(group.title) {
                                ForEach(group.transactions) { transaction in
                                    Button {
                                        editingTransaction = transaction
                                    } label: {
                                        TransactionRow(
                                            transaction: transaction,
                                            currencyCode: store.currencyCode
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            store.delete(transaction)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .contextMenu {
                                        Button {
                                            editingTransaction = transaction
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            store.delete(transaction)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppTheme.page)
            .navigationTitle("Transactions")
            .searchable(text: $searchText, prompt: "Search transactions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { onAdd(.expense) } label: {
                            Label("Add Expense", systemImage: "minus.circle.fill")
                        }
                        Button { onAdd(.income) } label: {
                            Label("Add Income", systemImage: "plus.circle.fill")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Add transaction")
                }
            }
            .sheet(item: $editingTransaction) { transaction in
                AddTransactionView(transaction: transaction)
                    .environmentObject(store)
            }
        }
    }

    private var filteredTransactions: [LedgerTransaction] {
        store.transactions.filter { transaction in
            let typeMatches: Bool
            switch filter {
            case .all: typeMatches = true
            case .income: typeMatches = transaction.type == .income
            case .expense: typeMatches = transaction.type == .expense
            }
            guard typeMatches else { return false }
            guard !searchText.isEmpty else { return true }
            let query = searchText.lowercased()
            return transaction.category.lowercased().contains(query)
                || transaction.details.lowercased().contains(query)
                || NSDecimalNumber(decimal: transaction.amount).stringValue.contains(query)
        }
    }

    private var groupedDays: [TransactionDayGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredTransactions) {
            calendar.startOfDay(for: $0.date)
        }
        return groups.keys.sorted(by: >).map { date in
            let title: String
            if calendar.isDateInToday(date) {
                title = "Today"
            } else if calendar.isDateInYesterday(date) {
                title = "Yesterday"
            } else {
                title = DisplayFormat.day.string(from: date)
            }
            return TransactionDayGroup(
                date: date,
                title: title,
                transactions: groups[date, default: []].sorted { $0.date > $1.date }
            )
        }
    }
}
