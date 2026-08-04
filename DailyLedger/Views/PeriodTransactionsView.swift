import SwiftUI

enum PeriodTransactionKind {
    case income
    case expenses
    case loans
    case loanIncrease
    case loanDecrease

    var title: String {
        switch self {
        case .income: return "Income"
        case .expenses: return "Expenses"
        case .loans: return "Loans Paid"
        case .loanIncrease: return "Loan Increase"
        case .loanDecrease: return "Loan Decrease"
        }
    }
}

struct PeriodTransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var selectedTransaction: LedgerTransaction?
    @State private var searchText = ""
    let kind: PeriodTransactionKind
    let interval: DateInterval
    var accountIDs: Set<UUID>? = nil

    var body: some View {
        List {
            Section {
                ForEach(transactions) { transaction in
                    Button {
                        selectedTransaction = transaction
                    } label: {
                        TransactionRow(
                            transaction: transaction,
                            accountID: kind == .income ? store.reportIncomeAccountID(transaction) : nil
                        )
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
            guard interval.contains(transaction.date) else { return false }
            let kindMatches: Bool
            switch kind {
            case .income:
                kindMatches = store.isReportIncome(transaction) &&
                    store.account(withID: store.reportIncomeAccountID(transaction))?.currencyCode == store.currencyCode &&
                    (accountIDs == nil || accountIDs?.contains(
                        store.reportIncomeAccountID(transaction) ?? LedgerAccount.legacyMainID
                    ) == true)
            case .expenses:
                kindMatches = transaction.type == .expense &&
                    store.account(withID: transaction.accountID)?.currencyCode == store.currencyCode
            case .loans:
                kindMatches = transaction.type == .transfer &&
                    store.account(withID: transaction.destinationAccountID)?.group == .payments
            case .loanIncrease:
                let source = store.account(withID: transaction.accountID)
                kindMatches = (transaction.type == .expense || transaction.type == .transfer) &&
                    (source?.group == .payments || source?.nature == .loan)
            case .loanDecrease:
                let destination = store.account(withID: transaction.destinationAccountID)
                kindMatches = transaction.type == .transfer &&
                    (destination?.group == .payments || destination?.nature == .loan)
            }
            guard kindMatches, !searchText.isEmpty else { return kindMatches }
            return transaction.category.localizedCaseInsensitiveContains(searchText) ||
                (transaction.vendor?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                transaction.details.localizedCaseInsensitiveContains(searchText)
        }
        .sorted { $0.date > $1.date }
    }

    private var total: Decimal {
        transactions.reduce(Decimal.zero) {
            if kind == .income { return $0 + store.reportIncomeAmount($1) }
            if kind == .loanDecrease { return $0 + ($1.destinationAmount ?? $1.amount) }
            return $0 + $1.amount
        }
    }
}
