import SwiftUI

struct TransferView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var sourceAccountID: UUID?
    @State private var destinationAccountID: UUID?
    @State private var amountText = ""
    @State private var destinationAmountText = ""
    @State private var date = Date()
    @State private var details = ""
    @FocusState private var focusedAmount: AmountField?
    private let editingTransaction: LedgerTransaction?
    private enum AmountField { case source, destination }

    init(sourceAccountID: UUID? = nil) {
        editingTransaction = nil
        _sourceAccountID = State(initialValue: sourceAccountID)
    }

    init(transaction: LedgerTransaction) {
        editingTransaction = transaction
        _sourceAccountID = State(initialValue: transaction.accountID)
        _destinationAccountID = State(initialValue: transaction.destinationAccountID)
        _amountText = State(initialValue: NSDecimalNumber(decimal: transaction.amount).stringValue)
        _destinationAmountText = State(initialValue: NSDecimalNumber(
            decimal: transaction.destinationAmount ?? transaction.amount
        ).stringValue)
        _date = State(initialValue: transaction.date)
        _details = State(initialValue: transaction.details)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("From") {
                    accountPicker("Source account", selection: $sourceAccountID)
                    amountField("Amount sent", text: $amountText, currency: sourceAccount?.currencyCode)
                }

                Section("To") {
                    accountPicker("Destination account", selection: $destinationAccountID)
                    if needsDestinationAmount {
                        amountField(
                            "Amount received",
                            text: $destinationAmountText,
                            currency: destinationAccount?.currencyCode
                        )
                    }
                }

                Section("Details") {
                    TextField("Description (optional)", text: $details)
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle(editingTransaction == nil ? "New Transfer" : "Edit Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingTransaction == nil ? "Transfer" : "Update", action: save)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    ForEach(["+", "−", "×", "÷"], id: \.self) { symbol in
                        Button(symbol) { appendOperator(symbol) }
                    }
                    Button("=", action: calculateFocusedAmount)
                }
            }
            .onAppear(perform: chooseDefaults)
            .onChange(of: sourceAccountID) { value in
                if destinationAccountID == value {
                    destinationAccountID = store.activeAccounts.first(where: { $0.id != value })?.id
                }
            }
        }
    }

    private func accountPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            ForEach(store.activeAccounts) { account in
                Text("\(account.name) · \(account.currencyCode)")
                    .tag(Optional(account.id))
            }
        }
    }

    private func amountField(_ title: String, text: Binding<String>, currency: String?) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(currency ?? "—")
                    .foregroundStyle(.secondary)
                TextField(title, text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedAmount, equals: title == "Amount received" ? .destination : .source)
            }
            HStack(spacing: 8) {
                ForEach(["+", "−", "×", "÷"], id: \.self) { symbol in
                    Button(symbol) {
                        focusedAmount = title == "Amount received" ? .destination : .source
                        appendOperator(symbol)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
                Button("=") {
                    focusedAmount = title == "Amount received" ? .destination : .source
                    calculateFocusedAmount()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    private var sourceAccount: LedgerAccount? { store.account(withID: sourceAccountID) }
    private var destinationAccount: LedgerAccount? { store.account(withID: destinationAccountID) }
    private var needsDestinationAmount: Bool {
        sourceAccount?.currencyCode != destinationAccount?.currencyCode
    }
    private var sourceAmount: Decimal? { positiveDecimal(amountText) }
    private var receivedAmount: Decimal? {
        needsDestinationAmount ? positiveDecimal(destinationAmountText) : sourceAmount
    }
    private var canSave: Bool {
        sourceAccountID != nil && destinationAccountID != nil &&
            sourceAccountID != destinationAccountID && sourceAmount != nil && receivedAmount != nil
    }

    private func positiveDecimal(_ text: String) -> Decimal? {
        guard let value = AmountExpression.evaluate(text), value > 0 else { return nil }
        return value
    }

    private func appendOperator(_ symbol: String) {
        if focusedAmount == .destination {
            destinationAmountText = AmountExpression.appending(symbol, to: destinationAmountText)
        } else {
            amountText = AmountExpression.appending(symbol, to: amountText)
        }
    }
    private func calculateFocusedAmount() {
        if focusedAmount == .destination {
            if let value = AmountExpression.evaluate(destinationAmountText) {
                destinationAmountText = NSDecimalNumber(decimal: value).stringValue
            }
        } else if let value = AmountExpression.evaluate(amountText) {
            amountText = NSDecimalNumber(decimal: value).stringValue
        }
    }

    private func chooseDefaults() {
        if sourceAccountID == nil { sourceAccountID = store.defaultAccountID }
        if destinationAccountID == nil || destinationAccountID == sourceAccountID {
            destinationAccountID = store.activeAccounts.first(where: { $0.id != sourceAccountID })?.id
        }
    }

    private func save() {
        guard let sourceAccountID, let destinationAccountID,
              let sourceAmount, let receivedAmount else { return }
        if var transaction = editingTransaction {
            transaction.type = .transfer
            transaction.amount = sourceAmount
            transaction.destinationAmount = receivedAmount
            transaction.accountID = sourceAccountID
            transaction.destinationAccountID = destinationAccountID
            transaction.category = "Transfer"
            transaction.vendor = nil
            transaction.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
            transaction.date = date
            store.update(transaction)
        } else {
            store.addTransfer(
                from: sourceAccountID,
                to: destinationAccountID,
                amount: sourceAmount,
                destinationAmount: receivedAmount,
                date: date,
                details: details
            )
        }
        dismiss()
    }
}
