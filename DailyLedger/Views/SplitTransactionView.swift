import SwiftUI

struct SplitTransactionView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let transaction: LedgerTransaction
    @State private var firstAccountID: UUID?
    @State private var secondAccountID: UUID?
    @State private var firstAmount = ""
    @State private var secondAmount = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Original Transaction") {
                    LabeledContent("Total", value: DisplayFormat.currency(transaction.amount, code: currencyCode))
                    LabeledContent("Date & Time", value: transaction.date.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Category", value: transaction.category)
                }
                splitSection(title: "First Part", accountID: $firstAccountID, amount: $firstAmount)
                splitSection(title: "Second Part", accountID: $secondAccountID, amount: $secondAmount)
                Section {
                    LabeledContent("Split Total", value: DisplayFormat.currency(splitTotal, code: currencyCode))
                    if splitTotal != transaction.amount {
                        Text("The two amounts must equal the original transaction total.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.red)
                    }
                }
            }
            .navigationTitle("Split Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear {
                firstAccountID = transaction.accountID ?? store.defaultAccountID
                secondAccountID = store.activeAccounts.first { $0.id != firstAccountID }?.id
                firstAmount = NSDecimalNumber(decimal: transaction.amount / 2).stringValue
                secondAmount = NSDecimalNumber(decimal: transaction.amount - (transaction.amount / 2)).stringValue
            }
        }
    }

    private func splitSection(
        title: String,
        accountID: Binding<UUID?>,
        amount: Binding<String>
    ) -> some View {
        Section(title) {
            Picker("Account", selection: accountID) {
                ForEach(store.activeAccounts) { account in
                    Text(account.name).tag(Optional(account.id))
                }
            }
            TextField("Amount", text: amount)
                .keyboardType(.decimalPad)
        }
    }

    private var firstValue: Decimal { decimal(firstAmount) ?? 0 }
    private var secondValue: Decimal { decimal(secondAmount) ?? 0 }
    private var splitTotal: Decimal { firstValue + secondValue }
    private var currencyCode: String {
        store.account(withID: transaction.accountID)?.currencyCode ?? store.currencyCode
    }
    private var isValid: Bool {
        firstAccountID != nil && secondAccountID != nil && firstAccountID != secondAccountID &&
        firstValue > 0 && secondValue > 0 && splitTotal == transaction.amount
    }
    private func decimal(_ text: String) -> Decimal? {
        Decimal(string: text.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
    }
    private func save() {
        guard let firstAccountID, let secondAccountID else { return }
        store.split(
            transaction, firstAccountID: firstAccountID, firstAmount: firstValue,
            secondAccountID: secondAccountID, secondAmount: secondValue
        )
        dismiss()
    }
}
