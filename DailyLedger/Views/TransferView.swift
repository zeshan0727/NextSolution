import Foundation
import SwiftUI

struct TransferView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var sourceAccountID: UUID?
    @State private var destinationAccountID: UUID?
    @State private var amountText = ""
    @State private var exchangeRateText = ""
    @State private var useCustomRate = false
    @State private var date = Date()
    @State private var details = ""
    @FocusState private var focusedAmount: AmountField?
    private let editingTransaction: LedgerTransaction?

    private enum AmountField {
        case source
        case rate
    }

    init(sourceAccountID: UUID? = nil) {
        editingTransaction = nil
        _sourceAccountID = State(initialValue: sourceAccountID)
    }

    init(transaction: LedgerTransaction) {
        editingTransaction = transaction
        _sourceAccountID = State(initialValue: transaction.accountID)
        _destinationAccountID = State(initialValue: transaction.destinationAccountID)
        _amountText = State(initialValue: NSDecimalNumber(decimal: transaction.amount).stringValue)
        _date = State(initialValue: transaction.date)
        _details = State(initialValue: transaction.details)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("From") {
                    accountPicker("Source account", selection: $sourceAccountID)
                    amountField("Amount sent", text: $amountText, currency: sourceCurrency)
                }

                Section("To") {
                    accountPicker("Destination account", selection: $destinationAccountID)
                    if !isCrossCurrency, let receivedAmount {
                        LabeledContent(
                            "Amount received",
                            value: DisplayFormat.currency(receivedAmount, code: destinationCurrency)
                        )
                    }
                }

                if isCrossCurrency {
                    Section {
                        if let fixedRate {
                            Toggle("Use Custom Rate", isOn: $useCustomRate)
                            if !useCustomRate {
                                LabeledContent(
                                    "Fixed Rate",
                                    value: "1 \(sourceCurrency) = \(rateString(fixedRate)) \(destinationCurrency)"
                                )
                            }
                        } else {
                            Label("Custom rate required", systemImage: "exclamationmark.circle")
                                .foregroundStyle(.secondary)
                        }

                        if useCustomRate || fixedRate == nil {
                            rateField
                        }

                        LabeledContent("Amount sent") {
                            Text(sourceAmount.map {
                                DisplayFormat.currency($0, code: sourceCurrency)
                            } ?? "—")
                        }
                        LabeledContent("Amount received") {
                            Text(receivedAmount.map {
                                DisplayFormat.currency($0, code: destinationCurrency)
                            } ?? "—")
                                .fontWeight(.semibold)
                        }
                    } header: {
                        Text("Currency Conversion")
                    } footer: {
                        Text(conversionFooter)
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
            .onAppear {
                chooseDefaults()
                configureConversion(preserveEditingRate: true)
            }
            .onChange(of: sourceAccountID) { value in
                if destinationAccountID == value {
                    destinationAccountID = store.activeAccounts.first(where: { $0.id != value })?.id
                }
                configureConversion(preserveEditingRate: false)
            }
            .onChange(of: destinationAccountID) { _ in
                configureConversion(preserveEditingRate: false)
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

    private func amountField(_ title: String, text: Binding<String>, currency: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(currency)
                    .foregroundStyle(.secondary)
                TextField(title, text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedAmount, equals: .source)
            }
            calculatorButtons(for: .source)
        }
    }

    private var rateField: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("1 \(sourceCurrency) =")
                    .foregroundStyle(.secondary)
                TextField("Rate", text: $exchangeRateText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedAmount, equals: .rate)
                Text(destinationCurrency)
                    .foregroundStyle(.secondary)
            }
            calculatorButtons(for: .rate)
        }
    }

    private func calculatorButtons(for field: AmountField) -> some View {
        HStack(spacing: 8) {
            ForEach(["+", "−", "×", "÷"], id: \.self) { symbol in
                Button(symbol) {
                    focusedAmount = field
                    appendOperator(symbol)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            Button("=") {
                focusedAmount = field
                calculateFocusedAmount()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .font(.subheadline.weight(.semibold))
    }

    private var sourceAccount: LedgerAccount? {
        store.account(withID: sourceAccountID)
    }

    private var destinationAccount: LedgerAccount? {
        store.account(withID: destinationAccountID)
    }

    private var sourceCurrency: String {
        sourceAccount?.currencyCode.uppercased() ?? "—"
    }

    private var destinationCurrency: String {
        destinationAccount?.currencyCode.uppercased() ?? "—"
    }

    private var isCrossCurrency: Bool {
        guard sourceAccount != nil, destinationAccount != nil else { return false }
        return sourceCurrency != destinationCurrency
    }

    private var sourceAmount: Decimal? {
        positiveDecimal(amountText)
    }

    private var fixedRate: Decimal? {
        guard isCrossCurrency else { return Decimal(1) }
        return defaultRate(from: sourceCurrency, to: destinationCurrency)
    }

    private var selectedRate: Decimal? {
        guard isCrossCurrency else { return Decimal(1) }
        if useCustomRate || fixedRate == nil {
            return positiveDecimal(exchangeRateText)
        }
        return fixedRate
    }

    private var receivedAmount: Decimal? {
        guard let sourceAmount else { return nil }
        guard isCrossCurrency else { return sourceAmount }
        guard let selectedRate else { return nil }
        return rounded(sourceAmount * selectedRate, scale: 2)
    }

    private var canSave: Bool {
        sourceAccountID != nil &&
            destinationAccountID != nil &&
            sourceAccountID != destinationAccountID &&
            sourceAmount != nil &&
            receivedAmount != nil
    }

    private var conversionFooter: String {
        if fixedRate == nil {
            return "Enter how much \(destinationCurrency) equals 1 \(sourceCurrency). The source balance is reduced by the sent amount and the destination balance is increased by the converted amount."
        }
        return "Fixed rates: 1 QAR = 77 PKR and 1 USD = 3.65 QAR. Reverse and USD↔PKR rates are calculated automatically. Enable Custom Rate to override the fixed rate for this transfer."
    }

    private func positiveDecimal(_ text: String) -> Decimal? {
        guard let value = AmountExpression.evaluate(text), value > 0 else { return nil }
        return value
    }

    private func appendOperator(_ symbol: String) {
        if focusedAmount == .rate {
            exchangeRateText = AmountExpression.appending(symbol, to: exchangeRateText)
        } else {
            amountText = AmountExpression.appending(symbol, to: amountText)
        }
    }

    private func calculateFocusedAmount() {
        if focusedAmount == .rate {
            if let value = AmountExpression.evaluate(exchangeRateText) {
                exchangeRateText = NSDecimalNumber(decimal: value).stringValue
            }
        } else if let value = AmountExpression.evaluate(amountText) {
            amountText = NSDecimalNumber(decimal: value).stringValue
        }
    }

    private func chooseDefaults() {
        if sourceAccountID == nil {
            sourceAccountID = store.defaultAccountID
        }
        if destinationAccountID == nil || destinationAccountID == sourceAccountID {
            destinationAccountID = store.activeAccounts.first(where: { $0.id != sourceAccountID })?.id
        }
    }

    private func configureConversion(preserveEditingRate: Bool) {
        guard let sourceAccount, let destinationAccount else { return }
        guard sourceAccount.currencyCode.caseInsensitiveCompare(destinationAccount.currencyCode) != .orderedSame else {
            useCustomRate = false
            exchangeRateText = "1"
            return
        }

        if preserveEditingRate,
           let transaction = editingTransaction,
           transaction.accountID == sourceAccount.id,
           transaction.destinationAccountID == destinationAccount.id,
           transaction.amount > 0,
           let destinationAmount = transaction.destinationAmount,
           destinationAmount > 0 {
            let storedRate = destinationAmount / transaction.amount
            if let fixedRate, approximatelyEqual(storedRate, fixedRate) {
                useCustomRate = false
                exchangeRateText = rateString(fixedRate)
            } else {
                useCustomRate = true
                exchangeRateText = rateString(storedRate)
            }
            return
        }

        if let fixedRate {
            useCustomRate = false
            exchangeRateText = rateString(fixedRate)
        } else {
            useCustomRate = true
            exchangeRateText = ""
        }
    }

    private func defaultRate(from source: String, to destination: String) -> Decimal? {
        let qarToPkr = Decimal(string: "77")!
        let usdToQar = Decimal(string: "3.65")!
        let usdToPkr = usdToQar * qarToPkr

        switch (source.uppercased(), destination.uppercased()) {
        case ("QAR", "PKR"):
            return qarToPkr
        case ("PKR", "QAR"):
            return Decimal(1) / qarToPkr
        case ("USD", "QAR"):
            return usdToQar
        case ("QAR", "USD"):
            return Decimal(1) / usdToQar
        case ("USD", "PKR"):
            return usdToPkr
        case ("PKR", "USD"):
            return Decimal(1) / usdToPkr
        default:
            return nil
        }
    }

    private func rounded(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var output = Decimal.zero
        NSDecimalRound(&output, &input, scale, .plain)
        return output
    }

    private func rateString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: rounded(value, scale: 6)).stringValue
    }

    private func approximatelyEqual(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
        let tolerance = Decimal(string: "0.000001")!
        let difference = lhs >= rhs ? lhs - rhs : rhs - lhs
        return difference <= tolerance
    }

    private func save() {
        guard let sourceAccountID,
              let destinationAccountID,
              let sourceAmount,
              let receivedAmount else { return }

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
