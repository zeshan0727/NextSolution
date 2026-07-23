import SwiftUI

struct CategoryTransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var selectedTransaction: LedgerTransaction?
    @State private var searchText = ""
    let category: String
    let interval: DateInterval

    var body: some View {
        List {
            Section {
                ForEach(transactions) { transaction in
                    Button {
                        selectedTransaction = transaction
                    } label: {
                        TransactionRow(transaction: transaction)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                HStack {
                    Text("Total · \(transactions.count) transactions")
                    Spacer()
                    Text(DisplayFormat.currency(total, code: store.currencyCode)).bold()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(category)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search transactions")
        .overlay {
            if transactions.isEmpty {
                EmptyLedgerView(
                    title: "No transactions",
                    message: "No \(category) transactions are available in this report period."
                )
            }
        }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionSnapshotView(transaction: transaction)
                .environmentObject(store)
        }
    }

    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            interval.contains($0.date) &&
            $0.category.caseInsensitiveCompare(category) == .orderedSame &&
            store.account(withID: $0.accountID)?.currencyCode == store.currencyCode &&
            (searchText.isEmpty ||
                ($0.vendor?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.details.localizedCaseInsensitiveContains(searchText) ||
                NSDecimalNumber(decimal: $0.amount).stringValue.contains(searchText))
        }
        .sorted { $0.date > $1.date }
    }

    private var total: Decimal {
        transactions.reduce(Decimal.zero) { $0 + $1.amount }
    }
}

struct TransactionSnapshotView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var splitting = false
    let transaction: LedgerTransaction

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    LabeledContent("Type", value: transaction.type.title)
                    LabeledContent("Amount", value: DisplayFormat.currency(
                        transaction.amount,
                        code: store.account(withID: transaction.accountID)?.currencyCode ?? store.currencyCode
                    ))
                    LabeledContent("Date", value: transaction.date.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Category", value: transaction.category)
                    if let vendor = transaction.vendor, !vendor.isEmpty {
                        LabeledContent("Vendor", value: vendor)
                    }
                    LabeledContent("Account", value: store.account(withID: transaction.accountID)?.name ?? "Unknown")
                    if transaction.type == .transfer {
                        LabeledContent(
                            "Destination",
                            value: store.account(withID: transaction.destinationAccountID)?.name ?? "Unknown"
                        )
                    }
                }
                if !transaction.details.isEmpty {
                    Section("Description") {
                        Text(transaction.details)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Transaction Snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HStack {
                        if transaction.type != .transfer {
                            Button {
                                splitting = true
                            } label: {
                                Label("Split", systemImage: "rectangle.split.2x1")
                            }
                        }
                        Button("Edit") { editing = true }
                    }
                }
            }
            .sheet(isPresented: $splitting) {
                SplitTransactionView(transaction: transaction)
                    .environmentObject(store)
            }
            .sheet(isPresented: $editing) {
                if transaction.type == .transfer {
                    TransferView(transaction: transaction)
                        .environmentObject(store)
                } else {
                    AddTransactionView(transaction: transaction)
                        .environmentObject(store)
                }
            }
        }
    }
}
