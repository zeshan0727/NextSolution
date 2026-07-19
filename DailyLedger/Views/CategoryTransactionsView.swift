import SwiftUI

struct CategoryTransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    let category: String
    let interval: DateInterval

    var body: some View {
        List(transactions) { transaction in
            TransactionRow(transaction: transaction)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(category)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if transactions.isEmpty {
                EmptyLedgerView(
                    title: "No transactions",
                    message: "No \(category) transactions are available in this report period."
                )
            }
        }
    }

    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            interval.contains($0.date) &&
            $0.category.caseInsensitiveCompare(category) == .orderedSame &&
            store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }
        .sorted { $0.date > $1.date }
    }
}
