from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def write(relative: str, content: str) -> None:
    (ROOT / relative).write_text(content, encoding="utf-8")


def replace_once(relative: str, old: str, new: str) -> None:
    text = read(relative)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {relative}, found {count}: {old[:120]!r}")
    write(relative, text.replace(old, new, 1))


# Replace the transfer form with explicit currency selectors. The selectors filter
# account choices so a selected currency can never disagree with the account ledger.
write(
    "DailyLedger/Views/TransferView.swift",
    r'''import Foundation
import SwiftUI

struct TransferView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var sourceAccountID: UUID?
    @State private var destinationAccountID: UUID?
    @State private var sourceCurrencySelection = ""
    @State private var destinationCurrencySelection = ""
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
                    currencyPicker("From Currency", selection: $sourceCurrencySelection)
                    accountPicker(
                        "Source Account",
                        selection: $sourceAccountID,
                        currency: sourceCurrencySelection
                    )
                    amountField("Amount Sent", text: $amountText, currency: sourceCurrency)
                }

                Section("To") {
                    currencyPicker("To Currency", selection: $destinationCurrencySelection)
                    accountPicker(
                        "Destination Account",
                        selection: $destinationAccountID,
                        currency: destinationCurrencySelection
                    )
                    if !isCrossCurrency, let receivedAmount {
                        LabeledContent(
                            "Amount Received",
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

                        LabeledContent("Amount Sent") {
                            Text(sourceAmount.map {
                                DisplayFormat.currency($0, code: sourceCurrency)
                            } ?? "—")
                        }
                        LabeledContent("Amount Received") {
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

                if let editingTransaction {
                    Section {
                        Button("Delete Transfer", role: .destructive) {
                            store.delete(editingTransaction)
                            dismiss()
                        }
                    } footer: {
                        Text("Deleting reverses this transfer’s effect on both account balances.")
                    }
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
                if let account = store.account(withID: value),
                   sourceCurrencySelection != account.currencyCode.uppercased() {
                    sourceCurrencySelection = account.currencyCode.uppercased()
                }
                if destinationAccountID == value {
                    destinationAccountID = filteredAccounts(currency: destinationCurrencySelection)
                        .first(where: { $0.id != value })?.id
                }
                configureConversion(preserveEditingRate: false)
            }
            .onChange(of: destinationAccountID) { value in
                if let account = store.account(withID: value),
                   destinationCurrencySelection != account.currencyCode.uppercased() {
                    destinationCurrencySelection = account.currencyCode.uppercased()
                }
                configureConversion(preserveEditingRate: false)
            }
            .onChange(of: sourceCurrencySelection) { value in
                selectSourceAccount(for: value)
                configureConversion(preserveEditingRate: false)
            }
            .onChange(of: destinationCurrencySelection) { value in
                selectDestinationAccount(for: value)
                configureConversion(preserveEditingRate: false)
            }
        }
    }

    private func currencyPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(availableCurrencies, id: \.self) { currency in
                Text(currency).tag(currency)
            }
        }
        .pickerStyle(.menu)
    }

    private func accountPicker(
        _ title: String,
        selection: Binding<UUID?>,
        currency: String
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(filteredAccounts(currency: currency)) { account in
                Text(account.name)
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

    private var availableCurrencies: [String] {
        Array(Set(store.activeAccounts.map { $0.currencyCode.uppercased() })).sorted()
    }

    private func filteredAccounts(currency: String) -> [LedgerAccount] {
        store.activeAccounts
            .filter { currency.isEmpty || $0.currencyCode.caseInsensitiveCompare(currency) == .orderedSame }
            .sorted {
                if $0.group != $1.group { return $0.group.title < $1.group.title }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private var sourceAccount: LedgerAccount? {
        store.account(withID: sourceAccountID)
    }

    private var destinationAccount: LedgerAccount? {
        store.account(withID: destinationAccountID)
    }

    private var sourceCurrency: String {
        sourceCurrencySelection.isEmpty
            ? (sourceAccount?.currencyCode.uppercased() ?? "—")
            : sourceCurrencySelection
    }

    private var destinationCurrency: String {
        destinationCurrencySelection.isEmpty
            ? (destinationAccount?.currencyCode.uppercased() ?? "—")
            : destinationCurrencySelection
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
            sourceAccount?.currencyCode.caseInsensitiveCompare(sourceCurrency) == .orderedSame &&
            destinationAccount?.currencyCode.caseInsensitiveCompare(destinationCurrency) == .orderedSame &&
            sourceAmount != nil &&
            receivedAmount != nil
    }

    private var conversionFooter: String {
        if fixedRate == nil {
            return "Enter how much \(destinationCurrency) equals 1 \(sourceCurrency). The source account is reduced in \(sourceCurrency), and the destination account is increased in \(destinationCurrency)."
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
            sourceAccountID = store.defaultAccountID ?? store.activeAccounts.first?.id
        }
        if let sourceAccount {
            sourceCurrencySelection = sourceAccount.currencyCode.uppercased()
        } else if let first = availableCurrencies.first {
            sourceCurrencySelection = first
            sourceAccountID = filteredAccounts(currency: first).first?.id
        }

        if destinationAccountID == nil || destinationAccountID == sourceAccountID {
            destinationAccountID = store.activeAccounts.first(where: { $0.id != sourceAccountID })?.id
        }
        if let destinationAccount {
            destinationCurrencySelection = destinationAccount.currencyCode.uppercased()
        } else if let first = availableCurrencies.first {
            destinationCurrencySelection = first
            destinationAccountID = filteredAccounts(currency: first)
                .first(where: { $0.id != sourceAccountID })?.id
        }
    }

    private func selectSourceAccount(for currency: String) {
        guard !currency.isEmpty else { return }
        if sourceAccount?.currencyCode.caseInsensitiveCompare(currency) != .orderedSame {
            sourceAccountID = filteredAccounts(currency: currency)
                .first(where: { $0.id != destinationAccountID })?.id
                ?? filteredAccounts(currency: currency).first?.id
        }
    }

    private func selectDestinationAccount(for currency: String) {
        guard !currency.isEmpty else { return }
        if destinationAccount?.currencyCode.caseInsensitiveCompare(currency) != .orderedSame ||
            destinationAccountID == sourceAccountID {
            destinationAccountID = filteredAccounts(currency: currency)
                .first(where: { $0.id != sourceAccountID })?.id
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
''',
)

# Deleting an original transaction also deletes its linked refund entries.
replace_once(
    "DailyLedger/Services/LedgerStore.swift",
    """            let ledger = try LedgerDiskStore.shared.mutate { ledger in
                ledger.transactions.removeAll { $0.id == transaction.id }
            }
""",
    """            let ledger = try LedgerDiskStore.shared.mutate { ledger in
                ledger.transactions.removeAll {
                    $0.id == transaction.id || $0.refundOfTransactionID == transaction.id
                }
            }
""",
)

# Account detail transaction list.
replace_once(
    "DailyLedger/Views/AccountsView.swift",
    """                        Button { editingTransaction = transaction } label: {
                            TransactionRow(transaction: transaction, accountID: accountID)
                        }
                        .buttonStyle(.plain)
""",
    """                        Button { editingTransaction = transaction } label: {
                            TransactionRow(transaction: transaction, accountID: accountID)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                store.delete(transaction)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                store.delete(transaction)
                            } label: {
                                Label("Delete Transaction", systemImage: "trash")
                            }
                        }
""",
)

# Period report transaction list.
replace_once(
    "DailyLedger/Views/PeriodTransactionsView.swift",
    """                    .buttonStyle(.plain)
""",
    """                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            store.delete(transaction)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            store.delete(transaction)
                        } label: {
                            Label("Delete Transaction", systemImage: "trash")
                        }
                    }
""",
)

# Chart of Accounts linked transaction list.
replace_once(
    "DailyLedger/Views/ChartLinkedTransactionsView.swift",
    """                    .buttonStyle(.plain)
""",
    """                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            store.delete(transaction)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            store.delete(transaction)
                        } label: {
                            Label("Delete Transaction", systemImage: "trash")
                        }
                    }
""",
)

# Category transaction list (after the refund patch has generated its review screen).
replace_once(
    "DailyLedger/Views/CategoryTransactionsView.swift",
    """                    .buttonStyle(.plain)
""",
    """                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            store.delete(transaction)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            store.delete(transaction)
                        } label: {
                            Label("Delete Transaction", systemImage: "trash")
                        }
                    }
""",
)
replace_once(
    "DailyLedger/Views/CategoryTransactionsView.swift",
    """            }
            .navigationTitle("Transaction Snapshot")
""",
    """                Section {
                    Button("Delete Transaction", role: .destructive) {
                        store.delete(transaction)
                        dismiss()
                    }
                } footer: {
                    Text("Deleting removes this entry from all reports and account balances. Linked refunds are also removed when deleting the original transaction.")
                }
            }
            .navigationTitle("Transaction Snapshot")
""",
)

# Add/delete transaction editor.
replace_once(
    "DailyLedger/Views/AddTransactionView.swift",
    """                    dateEditor
""",
    """                    dateEditor
                    if let editingTransaction {
                        deleteEditor(editingTransaction)
                    }
""",
)
replace_once(
    "DailyLedger/Views/AddTransactionView.swift",
    """    private var saveButton: some View {
""",
    """    private func deleteEditor(_ transaction: LedgerTransaction) -> some View {
        Button(role: .destructive) {
            store.delete(transaction)
            dismiss()
        } label: {
            Label("Delete Transaction", systemImage: "trash.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .buttonStyle(.bordered)
        .tint(AppTheme.red)
    }

    private var saveButton: some View {
""",
)

# Uncategorized review is also a transaction review surface.
replace_once(
    "DailyLedger/Views/UncategorizedReviewView.swift",
    """                        Button {
                            splittingTransaction = transaction
                        } label: {
                            Label("Split Between Two Accounts", systemImage: "rectangle.split.2x1")
                                .font(.caption.weight(.semibold))
                        }
""",
    """                        Button {
                            splittingTransaction = transaction
                        } label: {
                            Label("Split Between Two Accounts", systemImage: "rectangle.split.2x1")
                                .font(.caption.weight(.semibold))
                        }
                        Button(role: .destructive) {
                            store.delete(transaction)
                            skippedIDs.remove(transaction.id)
                        } label: {
                            Label("Delete Transaction", systemImage: "trash")
                        }
""",
)

# Dashboard recent transactions open the review screen and provide a delete menu.
replace_once(
    "DailyLedger/Views/DashboardView.swift",
    """    @State private var transactionSearch = ""
""",
    """    @State private var transactionSearch = ""
    @State private var selectedTransaction: LedgerTransaction?
""",
)
replace_once(
    "DailyLedger/Views/DashboardView.swift",
    """            .onChange(of: transactionSearch) { _ in refreshDashboardSnapshot() }
            .sheet(isPresented: $showingCustomDates) {
""",
    """            .onChange(of: transactionSearch) { _ in refreshDashboardSnapshot() }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionSnapshotView(transaction: transaction)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingCustomDates) {
""",
)
replace_once(
    "DailyLedger/Views/DashboardView.swift",
    """                        TransactionRow(transaction: transaction)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
""",
    """                        Button {
                            selectedTransaction = transaction
                        } label: {
                            TransactionRow(transaction: transaction)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.delete(transaction)
                            } label: {
                                Label("Delete Transaction", systemImage: "trash")
                            }
                        }
""",
)

# Report detail transaction cards.
replace_once(
    "DailyLedger/Views/ReportsView.swift",
    """                    .buttonStyle(.plain)
                    if transaction.id != selectedTransactions.last?.id { Divider() }
""",
    """                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            store.delete(transaction)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            store.delete(transaction)
                        } label: {
                            Label("Delete Transaction", systemImage: "trash")
                        }
                    }
                    if transaction.id != selectedTransactions.last?.id { Divider() }
""",
)

# Compared Transactions: make every row reviewable and swipe-deletable.
replace_once(
    "DailyLedger/Views/ReportsView.swift",
    r'''private struct ComparisonTransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    let interval: DateInterval
    var body: some View {
        List {
            Section("Income") { rows(for: .income) }
            Section("Expenses") { rows(for: .expense) }
        }
        .navigationTitle("Compared Transactions")
        .navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func rows(for type: TransactionType) -> some View {
        let items = transactions.filter { type == .income ? store.isReportIncome($0) : $0.type == type }
        if items.isEmpty {
            Text("No \(type.title.lowercased()) transactions.").foregroundStyle(.secondary)
        } else {
            ForEach(items) {
                TransactionRow(
                    transaction: $0,
                    accountID: type == .income ? store.reportIncomeAccountID($0) : nil
                )
            }
            LabeledContent("Total", value: DisplayFormat.currency(items.reduce(0) {
                $0 + (type == .income ? store.reportIncomeAmount($1) : $1.amount)
            }, code: store.currencyCode))
        }
    }
    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            guard interval.contains($0.date) else { return false }
            if store.isReportIncome($0) {
                return store.account(withID: store.reportIncomeAccountID($0))?.currencyCode == store.currencyCode
            }
            return $0.type == .expense &&
                store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }.sorted { $0.date > $1.date }
    }
}
''',
    r'''private struct ComparisonTransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var selectedTransaction: LedgerTransaction?
    let interval: DateInterval

    var body: some View {
        List {
            Section("Income") { rows(for: .income) }
            Section("Expenses") { rows(for: .expense) }
        }
        .navigationTitle("Compared Transactions")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedTransaction) { transaction in
            TransactionSnapshotView(transaction: transaction)
                .environmentObject(store)
        }
    }

    @ViewBuilder private func rows(for type: TransactionType) -> some View {
        let items = transactions.filter { type == .income ? store.isReportIncome($0) : $0.type == type }
        if items.isEmpty {
            Text("No \(type.title.lowercased()) transactions.").foregroundStyle(.secondary)
        } else {
            ForEach(items) { transaction in
                Button {
                    selectedTransaction = transaction
                } label: {
                    TransactionRow(
                        transaction: transaction,
                        accountID: type == .income ? store.reportIncomeAccountID(transaction) : nil
                    )
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        store.delete(transaction)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        store.delete(transaction)
                    } label: {
                        Label("Delete Transaction", systemImage: "trash")
                    }
                }
            }
            LabeledContent("Total", value: DisplayFormat.currency(items.reduce(0) {
                $0 + (type == .income ? store.reportIncomeAmount($1) : $1.amount)
            }, code: store.currencyCode))
        }
    }

    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            guard interval.contains($0.date) else { return false }
            if store.isReportIncome($0) {
                return store.account(withID: store.reportIncomeAccountID($0))?.currencyCode == store.currencyCode
            }
            return $0.type == .expense &&
                store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }.sorted { $0.date > $1.date }
    }
}
''',
)

# Account, loan and nature report lists.
replace_once(
    "DailyLedger/Views/ReportsView.swift",
    """                }.buttonStyle(.plain)
            }
            Section {
""",
    """                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        store.delete(transaction)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        store.delete(transaction)
                    } label: {
                        Label("Delete Transaction", systemImage: "trash")
                    }
                }
            }
            Section {
""",
)
replace_once(
    "DailyLedger/Views/ReportsView.swift",
    """                }.buttonStyle(.plain)
            }
            LabeledContent("Total", value: DisplayFormat.currency(total, code: currency))
""",
    """                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        store.delete(transaction)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        store.delete(transaction)
                    } label: {
                        Label("Delete Transaction", systemImage: "trash")
                    }
                }
            }
            LabeledContent("Total", value: DisplayFormat.currency(total, code: currency))
""",
)
replace_once(
    "DailyLedger/Views/ReportsView.swift",
    """                }
                    .buttonStyle(.plain)
            }
        }
        .navigationTitle("\\(nature.title) \\(type.title)")
""",
    """                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        store.delete(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        store.delete(item)
                    } label: {
                        Label("Delete Transaction", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("\\(nature.title) \\(type.title)")
""",
)

print("Added explicit transfer currency selectors and delete actions across transaction surfaces.")
