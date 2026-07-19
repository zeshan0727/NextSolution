import SwiftUI

enum PeriodTransactionKind {
    case income
    case expenses
    case loans

    var title: String {
        switch self {
        case .income: return "Income"
        case .expenses: return "Expenses"
        case .loans: return "Loans Paid"
        }
    }
}

struct PeriodTransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var selectedTransaction: LedgerTransaction?
    @State private var searchText = ""
    let kind: PeriodTransactionKind
    let interval: DateInterval

    var body: some View {
        List(transactions) { transaction in
            Button {
                selectedTransaction = transaction
            } label: {
                TransactionRow(transaction: transaction)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search transactions")
        .overlay {
            if transactions.isEmpty {
                EmptyLedgerView(
                    title: "No \(kind.title.lowercased())",
                    message: "No matching transactions are available for this period."
                )
            }
        }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionSnapshotView(transaction: transaction)
                .environmentObject(store)
        }
    }

    private var transactions: [LedgerTransaction] {
        store.transactions.filter { transaction in
            guard interval.contains(transaction.date),
                  store.account(withID: transaction.accountID)?.currencyCode == store.currencyCode else {
                return false
            }
            let kindMatches: Bool
            switch kind {
            case .income:
                kindMatches = transaction.type == .income
            case .expenses:
                kindMatches = transaction.type == .expense
            case .loans:
                kindMatches = transaction.type == .transfer &&
                    store.account(withID: transaction.destinationAccountID)?.group == .payments
            }
            guard kindMatches, !searchText.isEmpty else { return kindMatches }
            return transaction.category.localizedCaseInsensitiveContains(searchText) ||
                (transaction.vendor?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                transaction.details.localizedCaseInsensitiveContains(searchText)
        }
        .sorted { $0.date > $1.date }
    }
}
