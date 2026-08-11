from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}, got {count}: {old[:180]!r}")
    write(path, text.replace(old, new, 1))


# ---------------------------------------------------------------------------
# Version: app-only update. SMS daemon remains 2.2.3.
# ---------------------------------------------------------------------------
replace_once("project.yml", 'MARKETING_VERSION: "1.3.63"', 'MARKETING_VERSION: "1.3.64"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "71"', 'CURRENT_PROJECT_VERSION: "72"')


# ---------------------------------------------------------------------------
# Balance integrity fixes.
# 1) Legacy cross-currency transfers without destinationAmount must not use 1:1.
# 2) Parent consolidated balances and account detail include archived children.
# ---------------------------------------------------------------------------
store_path = "DailyLedger/Services/LedgerStore.swift"
text = read(store_path)
old = '''        var accountBalances = Dictionary(uniqueKeysWithValues: ledger.accounts.map {
            ($0.id, $0.openingBalance)
        })
        var running: [UUID: Decimal] = [:]
        var accountRunning: [UUID: [UUID: Decimal]] = [:]
        for item in ordered {
'''
new = '''        var accountBalances = Dictionary(uniqueKeysWithValues: ledger.accounts.map {
            ($0.id, $0.openingBalance)
        })
        let ledgerAccountsByID = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0) })

        func legacyTransferDestinationAmount(_ item: LedgerTransaction) -> Decimal {
            if let stored = item.destinationAmount { return stored }
            guard item.type == .transfer,
                  let sourceID = item.accountID,
                  let destinationID = item.destinationAccountID,
                  let source = ledgerAccountsByID[sourceID],
                  let destination = ledgerAccountsByID[destinationID] else { return item.amount }
            let from = source.currencyCode.uppercased()
            let to = destination.currencyCode.uppercased()
            if from == to { return item.amount }
            let qarToPkr = Decimal(string: "77")!
            let usdToQar = Decimal(string: "3.65")!
            let usdToPkr = qarToPkr * usdToQar
            let rate: Decimal?
            switch (from, to) {
            case ("QAR", "PKR"): rate = qarToPkr
            case ("PKR", "QAR"): rate = Decimal(1) / qarToPkr
            case ("USD", "QAR"): rate = usdToQar
            case ("QAR", "USD"): rate = Decimal(1) / usdToQar
            case ("USD", "PKR"): rate = usdToPkr
            case ("PKR", "USD"): rate = Decimal(1) / usdToPkr
            default: rate = nil
            }
            guard let rate else { return item.amount }
            var raw = item.amount * rate
            var rounded = Decimal.zero
            NSDecimalRound(&rounded, &raw, 2, .plain)
            return rounded
        }

        var running: [UUID: Decimal] = [:]
        var accountRunning: [UUID: [UUID: Decimal]] = [:]
        for item in ordered {
'''
if text.count(old) != 1:
    raise RuntimeError("LedgerStore apply balance anchor not found")
text = text.replace(old, new, 1)
text = text.replace(
    'accountBalances[destinationID, default: 0] += item.destinationAmount ?? item.amount',
    'accountBalances[destinationID, default: 0] += legacyTransferDestinationAmount(item)',
    1,
)

balance_anchor = '''    func balance(for account: LedgerAccount) -> Decimal {
        currentBalances[account.id] ?? account.openingBalance
    }
'''
if text.count(balance_anchor) != 1:
    raise RuntimeError("balance(for:) anchor not found")
effective_helper = balance_anchor + '''
    /// Destination-side amount used for balance/report reconciliation. Older
    /// transfers may not contain destinationAmount, so known fixed-rate currency
    /// pairs are reconstructed instead of incorrectly assuming a 1:1 transfer.
    func effectiveDestinationAmount(_ transaction: LedgerTransaction) -> Decimal {
        if let stored = transaction.destinationAmount { return stored }
        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              let destination = account(withID: transaction.destinationAccountID) else {
            return transaction.amount
        }
        let from = source.currencyCode.uppercased()
        let to = destination.currencyCode.uppercased()
        if from == to { return transaction.amount }
        let qarToPkr = Decimal(string: "77")!
        let usdToQar = Decimal(string: "3.65")!
        let usdToPkr = qarToPkr * usdToQar
        let rate: Decimal?
        switch (from, to) {
        case ("QAR", "PKR"): rate = qarToPkr
        case ("PKR", "QAR"): rate = Decimal(1) / qarToPkr
        case ("USD", "QAR"): rate = usdToQar
        case ("QAR", "USD"): rate = Decimal(1) / usdToQar
        case ("USD", "PKR"): rate = usdToPkr
        case ("PKR", "USD"): rate = Decimal(1) / usdToPkr
        default: rate = nil
        }
        guard let rate else { return transaction.amount }
        var raw = transaction.amount * rate
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &raw, 2, .plain)
        return rounded
    }
'''
text = text.replace(balance_anchor, effective_helper, 1)
text = text.replace(
    'result += transaction.destinationAmount ?? transaction.amount',
    'result += effectiveDestinationAmount(transaction)',
    1,
)
text = text.replace(
    'ids.formUnion(subAccounts(of: accountID).map(\\.id))',
    'ids.formUnion(subAccounts(of: accountID, includeArchived: true).map(\\.id))',
    1,
)
text = text.replace(
    'for child in subAccounts(of: account.id) {',
    'for child in subAccounts(of: account.id, includeArchived: true) {',
    1,
)
write(store_path, text)

# Report aging/history movement uses the same destination-side balance rule.
export_service = "DailyLedger/Services/ProfessionalReportExportService.swift"
text = read(export_service)
text = text.replace(
    'movement += transaction.destinationAmount ?? transaction.amount',
    'movement += store.effectiveDestinationAmount(transaction)',
    1,
)
write(export_service, text)

# Account rows/details include archived child balances in parent consolidation.
accounts_view = "DailyLedger/Views/AccountsView.swift"
text = read(accounts_view)
text = text.replace(
    'subAccountCount: store.subAccounts(of: account.id).count',
    'subAccountCount: store.subAccounts(of: account.id, includeArchived: true).count',
    1,
)
text = text.replace(
    'store.subAccounts(of: accountID)\n    }',
    'store.subAccounts(of: accountID, includeArchived: true)\n    }',
    1,
)
write(accounts_view, text)


# ---------------------------------------------------------------------------
# Transaction nature conversion from every existing edit screen.
# Income/Expense editor can switch directly or open Transfer editor.
# Transfer editor can convert to Income or Expense.
# ---------------------------------------------------------------------------
add_view = "DailyLedger/Views/AddTransactionView.swift"
text = read(add_view)
text = text.replace(
    '@State private var categorySearch = ""\n    @FocusState private var focusedField: Field?\n    private let editingTransaction: LedgerTransaction?\n',
    '@State private var categorySearch = ""\n    @State private var showingTransferConversion = false\n    @FocusState private var focusedField: Field?\n    private let editingTransaction: LedgerTransaction?\n    private let onSaved: (() -> Void)?\n',
    1,
)
text = text.replace(
    '''    init(initialType: TransactionType, accountID: UUID? = nil) {
        editingTransaction = nil
        _type = State(initialValue: initialType)
        _category = State(initialValue: initialType == .expense ? "Food" : "Salary")
        _accountID = State(initialValue: accountID)
    }

    init(transaction: LedgerTransaction) {
        editingTransaction = transaction
        _type = State(initialValue: transaction.type)
''',
    '''    init(initialType: TransactionType, accountID: UUID? = nil, onSaved: (() -> Void)? = nil) {
        editingTransaction = nil
        self.onSaved = onSaved
        _type = State(initialValue: initialType)
        _category = State(initialValue: initialType == .expense ? "Food" : "Salary")
        _accountID = State(initialValue: accountID)
    }

    init(transaction: LedgerTransaction, convertTo: TransactionType? = nil, onSaved: (() -> Void)? = nil) {
        editingTransaction = transaction
        self.onSaved = onSaved
        let initialType = convertTo ?? (transaction.type == .transfer ? .expense : transaction.type)
        _type = State(initialValue: initialType)
''',
    1,
)
text = text.replace(
    '''                VStack(alignment: .leading, spacing: 24) {
                    typePicker
                    accountPicker
''',
    '''                VStack(alignment: .leading, spacing: 24) {
                    if editingTransaction != nil { transactionNatureEditor }
                    typePicker
                    accountPicker
''',
    1,
)
# Add conversion sheet before presentation detents.
text = text.replace(
    '''        }
        .presentationDetents([.large])
    }

    private var typePicker: some View {
''',
    '''        }
        .sheet(isPresented: $showingTransferConversion) {
            if let editingTransaction {
                TransferView(transaction: editingTransaction, onSaved: {
                    onSaved?()
                    dismiss()
                })
                .environmentObject(store)
            }
        }
        .presentationDetents([.large])
    }

    private var transactionNatureEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transaction Nature")
                .font(.headline)
            HStack(spacing: 8) {
                Button {
                    type = .expense
                } label: {
                    Label("Expense", systemImage: type == .expense ? "checkmark.circle.fill" : "minus.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    type = .income
                } label: {
                    Label("Income", systemImage: type == .income ? "checkmark.circle.fill" : "plus.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    showingTransferConversion = true
                } label: {
                    Label("Transfer", systemImage: "arrow.left.arrow.right.circle")
                }
                .buttonStyle(.bordered)
            }
            Text("Changing the nature recalculates the affected account balances after you save.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var typePicker: some View {
''',
    1,
)
# Correct category initialization when converting a transfer.
text = text.replace(
    '_category = State(initialValue: transaction.category)\n',
    '_category = State(initialValue: transaction.type == .transfer ? (initialType == .income ? "Salary" : "Other") : transaction.category)\n',
    1,
)
# Notify outer conversion editor after successful save.
text = text.replace(
    '''            store.update(transaction)
        } else {
''',
    '''            store.update(transaction)
        } else {
''',
    1,
)
text = text.replace(
    '''        }
        dismiss()
    }
}''',
    '''        }
        onSaved?()
        dismiss()
    }
}''',
    1,
)
write(add_view, text)

transfer_view = "DailyLedger/Views/TransferView.swift"
text = read(transfer_view)
text = text.replace(
    '@State private var addingAccountFor: TransferAccountRole?\n    @FocusState private var focusedAmount: AmountField?\n    private let editingTransaction: LedgerTransaction?\n',
    '@State private var addingAccountFor: TransferAccountRole?\n    @State private var convertingTo: TransactionType?\n    @FocusState private var focusedAmount: AmountField?\n    private let editingTransaction: LedgerTransaction?\n    private let onSaved: (() -> Void)?\n',
    1,
)
text = text.replace(
    '''    init(sourceAccountID: UUID? = nil) {
        editingTransaction = nil
        _sourceAccountID = State(initialValue: sourceAccountID)
    }

    init(transaction: LedgerTransaction) {
        editingTransaction = transaction
''',
    '''    init(sourceAccountID: UUID? = nil, onSaved: (() -> Void)? = nil) {
        editingTransaction = nil
        self.onSaved = onSaved
        _sourceAccountID = State(initialValue: sourceAccountID)
    }

    init(transaction: LedgerTransaction, onSaved: (() -> Void)? = nil) {
        editingTransaction = transaction
        self.onSaved = onSaved
''',
    1,
)
text = text.replace(
    '''            Form {
                Section("From") {
''',
    '''            Form {
                if editingTransaction != nil {
                    Section("Transaction Nature") {
                        LabeledContent("Current", value: "Transfer")
                        HStack(spacing: 12) {
                            Button("Income") { convertingTo = .income }
                            Button("Expense") { convertingTo = .expense }
                        }
                        Text("Choose Income or Expense to convert this existing transfer. Account balances are recalculated when the converted transaction is saved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("From") {
''',
    1,
)
# Add conversion sheet after the existing account sheet modifier.
text = text.replace(
    '''            .sheet(item: $addingAccountFor) { role in
                AccountEditorView(
                    initialGroup: .other,
                    initialCurrency: role == .source
                        ? normalizedCurrency(sourceCurrencySelection)
                        : normalizedCurrency(destinationCurrencySelection)
                ) { account in
                    selectNewAccount(account, for: role)
                }
                .environmentObject(store)
            }
        }
    }
''',
    '''            .sheet(item: $addingAccountFor) { role in
                AccountEditorView(
                    initialGroup: .other,
                    initialCurrency: role == .source
                        ? normalizedCurrency(sourceCurrencySelection)
                        : normalizedCurrency(destinationCurrencySelection)
                ) { account in
                    selectNewAccount(account, for: role)
                }
                .environmentObject(store)
            }
            .sheet(item: $convertingTo) { newType in
                if let editingTransaction, newType != .transfer {
                    AddTransactionView(transaction: editingTransaction, convertTo: newType, onSaved: {
                        onSaved?()
                        dismiss()
                    })
                    .environmentObject(store)
                }
            }
        }
    }
''',
    1,
)
text = text.replace(
    '''        }
        dismiss()
    }
}''',
    '''        }
        onSaved?()
        dismiss()
    }
}''',
    1,
)
write(transfer_view, text)


# ---------------------------------------------------------------------------
# Account Statement report builder: full history, expense summary and details.
# ---------------------------------------------------------------------------
text = read(export_service)
anchor = '\nenum ProfessionalReportExporter {'
if text.count(anchor) != 1:
    raise RuntimeError("ProfessionalReportExporter anchor not found")
account_builder = r'''

@MainActor
extension ProfessionalReportBuilder {
    static func accountStatement(
        accountID: UUID,
        startDate: Date,
        endDate: Date,
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(startDate, endDate))
        let endDay = calendar.startOfDay(for: max(startDate, endDate))
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        let ids = store.relatedAccountIDs(for: accountID)
        let selectedAccounts = store.accounts.filter { ids.contains($0.id) }
        let accountName = store.account(withID: accountID)?.name ?? "Account"
        let currencies = Array(Set(selectedAccounts.map { $0.currencyCode.uppercased() })).sorted()
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "dd-MMM-yyyy"
            return formatter
        }()
        let period = "\(dateFormatter.string(from: start)) – \(dateFormatter.string(from: endDay))"
        var tables: [ProfessionalReportTable] = []

        for currency in currencies {
            let currencyAccounts = selectedAccounts.filter { $0.currencyCode.uppercased() == currency }
            let currencyIDs = Set(currencyAccounts.map(\.id))
            let opening = store.combinedBalance(for: currencyAccounts, before: start)
            let relevant = store.transactions.filter { tx in
                guard tx.date >= start && tx.date < endExclusive else { return false }
                return tx.accountID.map(currencyIDs.contains) == true ||
                    tx.destinationAccountID.map(currencyIDs.contains) == true
            }.sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                return $0.createdAt < $1.createdAt
            }

            func movement(_ tx: LedgerTransaction) -> Decimal {
                var result: Decimal = 0
                if tx.accountID.map(currencyIDs.contains) == true {
                    switch tx.type {
                    case .income: result += tx.amount
                    case .expense, .transfer: result -= tx.amount
                    }
                }
                if tx.type == .transfer,
                   tx.destinationAccountID.map(currencyIDs.contains) == true {
                    result += store.effectiveDestinationAmount(tx)
                }
                return result
            }

            let income = relevant.reduce(Decimal.zero) { total, tx in
                guard tx.type == .income, tx.accountID.map(currencyIDs.contains) == true else { return total }
                return total + tx.amount
            }
            let expenses = relevant.reduce(Decimal.zero) { total, tx in
                guard tx.type == .expense, tx.accountID.map(currencyIDs.contains) == true else { return total }
                return total + tx.amount
            }
            let transfersIn = relevant.reduce(Decimal.zero) { total, tx in
                guard tx.type == .transfer, tx.destinationAccountID.map(currencyIDs.contains) == true else { return total }
                return total + store.effectiveDestinationAmount(tx)
            }
            let transfersOut = relevant.reduce(Decimal.zero) { total, tx in
                guard tx.type == .transfer, tx.accountID.map(currencyIDs.contains) == true else { return total }
                return total + tx.amount
            }
            let closing = relevant.reduce(opening) { $0 + movement($1) }

            tables.append(ProfessionalReportTable(
                title: "Account Summary — \(currency)",
                subtitle: accountName,
                columns: ["Measure", "Amount"],
                rows: [
                    ProfessionalReportRow([.text("Opening Balance"), .number(opening)]),
                    ProfessionalReportRow([.text("Income / Refunds"), .number(income)]),
                    ProfessionalReportRow([.text("Expenses"), .number(expenses)]),
                    ProfessionalReportRow([.text("Transfers In"), .number(transfersIn)]),
                    ProfessionalReportRow([.text("Transfers Out"), .number(transfersOut)]),
                    ProfessionalReportRow([.text("Closing Balance"), .number(closing)], emphasis: .total)
                ]
            ))

            let expenseGroups = Dictionary(grouping: relevant.filter {
                $0.type == .expense && $0.accountID.map(currencyIDs.contains) == true
            }, by: { $0.category })
            let expenseRows = expenseGroups.keys.sorted().map { category in
                ProfessionalReportRow([
                    .text(category),
                    .number(expenseGroups[category, default: []].reduce(Decimal.zero) { $0 + $1.amount })
                ])
            }
            tables.append(ProfessionalReportTable(
                title: "Expense Summary — \(currency)",
                subtitle: "Expenses by category",
                columns: ["Category", "Amount"],
                rows: expenseRows.isEmpty
                    ? [ProfessionalReportRow([.text("No expenses"), .number(0)])]
                    : expenseRows + [ProfessionalReportRow([.text("Total Expenses"), .number(expenses)], emphasis: .total)]
            ))

            var running = opening
            var detailRows: [ProfessionalReportRow] = []
            for tx in relevant {
                let delta = movement(tx)
                running += delta
                let description: String = {
                    if let vendor = tx.vendor?.trimmingCharacters(in: .whitespacesAndNewlines), !vendor.isEmpty {
                        return tx.details.isEmpty ? vendor : "\(vendor) · \(tx.details)"
                    }
                    return tx.details.isEmpty ? tx.category : tx.details
                }()
                detailRows.append(ProfessionalReportRow([
                    .text(dateFormatter.string(from: tx.date)),
                    .text(tx.type.title),
                    .text(tx.category),
                    .text(description),
                    .number(delta < 0 ? -delta : 0),
                    .number(delta > 0 ? delta : 0),
                    .number(running)
                ]))
            }
            tables.append(ProfessionalReportTable(
                title: "Transaction Details — \(currency)",
                subtitle: "Complete account activity",
                columns: ["Date", "Nature", "Category", "Description", "Money Out", "Money In", "Balance"],
                rows: detailRows.isEmpty
                    ? [ProfessionalReportRow([.text("No transactions"), .text("—"), .text("—"), .text("—"), .number(0), .number(0), .number(opening)])]
                    : detailRows
            ))
        }

        return ProfessionalReportDocument(
            title: "\(accountName) Account Statement",
            subtitle: "Summary, expense analysis and full transaction detail",
            periodText: period,
            generatedAt: Date(),
            tables: tables,
            notes: [
                "Balances are rebuilt from opening balances and saved ledger transactions.",
                "Legacy QAR/PKR/USD transfers without a stored destination amount use the app's fixed conversion rates.",
                "Main-account statements include direct sub-accounts, including archived sub-accounts with historical balances."
            ]
        )
    }
}
'''
text = text.replace(anchor, account_builder + anchor, 1)
write(export_service, text)


# ---------------------------------------------------------------------------
# Shared report snapshot UI. Every quick report now previews before sharing.
# Account detail gets an All-History Account Statement PDF/Excel button.
# ---------------------------------------------------------------------------
report_button = r'''import PDFKit
import SwiftUI
import UIKit

struct ReportSnapshotPayload: Identifiable {
    let id = UUID()
    let document: ProfessionalReportDocument
    let url: URL
    let format: ProfessionalExportFormat
}

struct ReportSnapshotCard: View {
    let document: ProfessionalReportDocument
    let url: URL
    let format: ProfessionalExportFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Report Snapshot", systemImage: "doc.text.image.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.purple)
                Spacer()
                Text(format.rawValue.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }

            if format == .pdf, let thumbnail = pdfThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.18)))
            } else {
                documentSnapshot
            }

            Text(document.title)
                .font(.subheadline.bold())
            Text(document.periodText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var pdfThumbnail: UIImage? {
        guard let pdf = PDFDocument(url: url), let page = pdf.page(at: 0) else { return nil }
        return page.thumbnail(of: CGSize(width: 760, height: 980), for: .mediaBox)
    }

    private var documentSnapshot: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(document.tables.prefix(2).enumerated()), id: \.offset) { _, table in
                VStack(alignment: .leading, spacing: 5) {
                    Text(table.title)
                        .font(.caption.bold())
                    ForEach(Array(table.rows.prefix(5).enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(Array(row.cells.prefix(3).enumerated()), id: \.offset) { _, cell in
                                Text(snapshotText(cell))
                                    .font(.system(size: 10, design: .rounded))
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(9)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func snapshotText(_ cell: ProfessionalReportCell) -> String {
        switch cell {
        case .text(let value): return value
        case .number(let value): return NSDecimalNumber(decimal: value).stringValue
        }
    }
}

struct ReportGeneratedSnapshotSheet: View {
    @Environment(\.dismiss) private var dismiss
    let payload: ReportSnapshotPayload
    @State private var shareFile: QuickReportShareFile?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ReportSnapshotCard(document: payload.document, url: payload.url, format: payload.format)
                    Button {
                        shareFile = QuickReportShareFile(url: payload.url)
                    } label: {
                        Label("Share / Save \(payload.format.rawValue)", systemImage: "square.and.arrow.up.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.purple)
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Generated Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $shareFile) { file in
                QuickReportActivityView(items: [file.url])
                    .ignoresSafeArea()
            }
        }
    }
}

struct ReportDownloadButton: View {
    @EnvironmentObject private var store: LedgerStore

    let type: ProfessionalReportType
    let startDate: Date
    let endDate: Date
    var scope = ProfessionalReportScope()

    @State private var isGenerating = false
    @State private var snapshot: ReportSnapshotPayload?
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            Button { generate(.pdf) } label: {
                Label("PDF", systemImage: "doc.richtext.fill")
            }
            Button { generate(.excel) } label: {
                Label("Excel", systemImage: "tablecells.fill")
            }
        } label: {
            Group {
                if isGenerating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.purple)
                }
            }
            .frame(width: 36, height: 36)
            .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .disabled(isGenerating)
        .accessibilityLabel("Download \(type.rawValue)")
        .sheet(item: $snapshot) { payload in
            ReportGeneratedSnapshotSheet(payload: payload)
        }
        .alert("Report Export", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The report could not be generated.")
        }
    }

    private func generate(_ format: ProfessionalExportFormat) {
        isGenerating = true
        defer { isGenerating = false }
        let document = ProfessionalReportBuilder.build(
            type: type,
            startDate: startDate,
            endDate: endDate,
            store: store,
            scope: scope
        )
        do {
            let url = try ProfessionalReportExporter.export(document, format: format)
            snapshot = ReportSnapshotPayload(document: document, url: url, format: format)
        } catch {
            errorMessage = "The \(format.rawValue) report could not be generated. \(error.localizedDescription)"
        }
    }
}

struct AccountStatementDownloadButton: View {
    @EnvironmentObject private var store: LedgerStore
    let accountID: UUID
    @State private var isGenerating = false
    @State private var snapshot: ReportSnapshotPayload?
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            Button { generate(.pdf) } label: {
                Label("Account Statement PDF", systemImage: "doc.richtext.fill")
            }
            Button { generate(.excel) } label: {
                Label("Account Statement Excel", systemImage: "tablecells.fill")
            }
        } label: {
            if isGenerating {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "square.and.arrow.down.fill")
                    .foregroundStyle(AppTheme.purple)
            }
        }
        .disabled(isGenerating)
        .accessibilityLabel("Download account statement")
        .sheet(item: $snapshot) { payload in
            ReportGeneratedSnapshotSheet(payload: payload)
        }
        .alert("Account Export", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The account statement could not be generated.")
        }
    }

    private func generate(_ format: ProfessionalExportFormat) {
        guard let account = store.account(withID: accountID) else { return }
        isGenerating = true
        defer { isGenerating = false }
        let ids = store.relatedAccountIDs(for: accountID)
        let dates = store.transactions.compactMap { tx -> Date? in
            let belongs = tx.accountID.map(ids.contains) == true || tx.destinationAccountID.map(ids.contains) == true
            return belongs ? tx.date : nil
        }
        let start = dates.min() ?? account.createdAt
        let end = Date()
        let document = ProfessionalReportBuilder.accountStatement(
            accountID: accountID,
            startDate: start,
            endDate: end,
            store: store
        )
        do {
            let url = try ProfessionalReportExporter.export(document, format: format)
            snapshot = ReportSnapshotPayload(document: document, url: url, format: format)
        } catch {
            errorMessage = "The \(format.rawValue) account statement could not be generated. \(error.localizedDescription)"
        }
    }
}

struct ProfessionalReportTypeView: View {
    let type: ProfessionalReportType

    @AppStorage("ProfessionalReportStartDateV1") private var storedStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
    @AppStorage("ProfessionalReportEndDateV1") private var storedEndDate = Date().timeIntervalSince1970

    private var startDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: storedStartDate) },
            set: { value in
                storedStartDate = Calendar.current.startOfDay(for: value).timeIntervalSince1970
                if storedStartDate > storedEndDate { storedEndDate = storedStartDate }
            }
        )
    }

    private var endDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: storedEndDate) },
            set: { value in
                storedEndDate = Calendar.current.startOfDay(for: value).timeIntervalSince1970
                if storedEndDate < storedStartDate { storedStartDate = storedEndDate }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: type.icon)
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.purple)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.purple.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(type.rawValue).font(.headline)
                        Text(type.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 5)
            }
            Section(type.usesAsOfDateOnly ? "Report Date" : "Period") {
                if type.usesAsOfDateOnly {
                    DatePicker("As of", selection: endDate, displayedComponents: .date)
                } else {
                    DatePicker("From", selection: startDate, displayedComponents: .date)
                    DatePicker("To", selection: endDate, in: startDate.wrappedValue..., displayedComponents: .date)
                }
            }
            Section {
                Label("Generate PDF or Excel from the download button. A snapshot is shown before sharing.", systemImage: "doc.text.image.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(type.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ReportDownloadButton(type: type, startDate: startDate.wrappedValue, endDate: endDate.wrappedValue)
            }
        }
    }
}

struct QuickReportShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct QuickReportActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
'''
write("DailyLedger/Views/ReportDownloadButton.swift", report_button)

# Account detail toolbar download button.
text = read(accounts_view)
text = text.replace(
    '''        .navigationTitle(account?.name ?? "Account")
        .searchable(text: $searchText, prompt: "Search transactions")
''',
    '''        .navigationTitle(account?.name ?? "Account")
        .searchable(text: $searchText, prompt: "Search transactions")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                AccountStatementDownloadButton(accountID: accountID)
            }
        }
''',
    1,
)
write(accounts_view, text)

# Professional Report Center shows the generated snapshot in-app and does not
# immediately jump to the share sheet.
prof_view = "DailyLedger/Views/ProfessionalReportExportView.swift"
text = read(prof_view)
text = text.replace(
    '@State private var lastGeneratedFormat: ProfessionalExportFormat?\n    @State private var errorMessage: String?\n',
    '@State private var lastGeneratedFormat: ProfessionalExportFormat?\n    @State private var lastGeneratedDocument: ProfessionalReportDocument?\n    @State private var errorMessage: String?\n',
    1,
)
text = text.replace(
    '''                if let lastGeneratedURL, let lastGeneratedFormat {
                    generatedFileCard(url: lastGeneratedURL, format: lastGeneratedFormat)
                }
                methodologyCard
''',
    '''                if let lastGeneratedURL, let lastGeneratedFormat {
                    generatedFileCard(url: lastGeneratedURL, format: lastGeneratedFormat)
                    if let lastGeneratedDocument {
                        ReportSnapshotCard(
                            document: lastGeneratedDocument,
                            url: lastGeneratedURL,
                            format: lastGeneratedFormat
                        )
                    }
                }
                methodologyCard
''',
    1,
)
text = text.replace(
    '''            let url = try ProfessionalReportExporter.export(document, format: format)
            lastGeneratedURL = url
            lastGeneratedFormat = format
            shareFile = ReportShareFile(url: url)
''',
    '''            let url = try ProfessionalReportExporter.export(document, format: format)
            lastGeneratedURL = url
            lastGeneratedFormat = format
            lastGeneratedDocument = document
''',
    1,
)
write(prof_view, text)

# Visible app version.
settings = "DailyLedger/Views/SettingsView.swift"
text = read(settings)
text = re.sub(r'LabeledContent\("Version", value: "[^"]+"\)', 'LabeledContent("Version", value: "1.3.64")', text, count=1)
write(settings, text)

print("Prepared Next Ledger 1.3.64 build 72: balance reconciliation, transaction nature conversion, report snapshots and per-account PDF/Excel statement export.")
