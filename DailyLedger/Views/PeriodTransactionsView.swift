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
            switch kind {
            case .income:
                return transaction.type == .income
            case .expenses:
                return transaction.type == .expense
            case .loans:
                return transaction.type == .transfer &&
                    store.account(withID: transaction.destinationAccountID)?.group == .payments
            }
        }
        .sorted { $0.date > $1.date }
    }
}
