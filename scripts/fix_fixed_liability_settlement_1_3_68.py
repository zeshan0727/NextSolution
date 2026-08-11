from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one match, got {count}: {old[:180]!r}")
    write(path, text.replace(old, new, 1))


# ---------------------------------------------------------------------------
# Next Ledger 1.3.68 / build 76. App-only update; SMS daemon remains 2.2.3.
# Fixed liabilities now derive repayments/outstanding/settlement from ledger.
# ---------------------------------------------------------------------------
replace_once("project.yml", 'MARKETING_VERSION: "1.3.67"', 'MARKETING_VERSION: "1.3.68"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "75"', 'CURRENT_PROJECT_VERSION: "76"')


# ---------------------------------------------------------------------------
# LedgerStore: real liability settlement accounting.
# In Next Ledger's transfer convention:
#   Liability -> Bank = drawdown / liability increase
#   Bank -> Liability = repayment / settlement
# Liability -> Liability is internal refinancing and does not count as cashflow.
# ---------------------------------------------------------------------------
store_path = "DailyLedger/Services/LedgerStore.swift"
text = read(store_path)

class_anchor = "@MainActor\nfinal class LedgerStore: ObservableObject {\n"
if text.count(class_anchor) != 1:
    raise RuntimeError("LedgerStore class anchor missing")

snapshot_model = r'''struct FixedLiabilityLedgerSnapshot {
    let originalPrincipal: Decimal
    let increases: Decimal
    let repayments: Decimal
    let outstanding: Decimal
    let status: FixedLiabilityStatus
    let settledDate: Date?

    var repaymentProgress: Double {
        let total = originalPrincipal + increases
        guard total > 0 else { return status == .settled ? 1 : 0 }
        let ratio = NSDecimalNumber(decimal: min(total, repayments) / total).doubleValue
        return min(max(ratio, 0), 1)
    }
}

'''
text = text.replace(class_anchor, snapshot_model + class_anchor, 1)

# Add helpers after account lookup, which already exists in every generated build.
account_anchor = '''    func account(withID id: UUID?) -> LedgerAccount? {
        guard let id else { return nil }
        return accountsByID[id]
    }
'''
if text.count(account_anchor) != 1:
    raise RuntimeError("account(withID:) anchor missing")

helpers = account_anchor + r'''

    func isFinancialLiabilityAccount(_ account: LedgerAccount?) -> Bool {
        guard let nature = account?.nature else { return false }
        return nature == .loan || nature == .fixedLiability
    }

    func fixedLiabilitySuggestedPrincipal(for account: LedgerAccount, asOf date: Date = Date()) -> Decimal {
        var drawdowns: Decimal = 0
        for transaction in transactions where transaction.date <= date && transaction.type == .transfer {
            guard transaction.accountID == account.id else { continue }
            let destination = self.account(withID: transaction.destinationAccountID)
            if isFinancialLiabilityAccount(destination) { continue }
            drawdowns += transaction.amount
        }
        let opening = abs(account.openingBalance)
        let current = abs(balance(for: account))
        return max(opening, max(drawdowns, current))
    }

    func fixedLiabilitySnapshot(
        _ record: FixedLiabilityRecord,
        asOf requestedDate: Date = Date()
    ) -> FixedLiabilityLedgerSnapshot {
        let tolerance: Decimal = 0.01
        let principal = max(0, record.originalPrincipal)
        guard let liabilityID = record.linkedAccountID else {
            let manualOutstanding = record.status == .settled ? Decimal.zero : principal
            return FixedLiabilityLedgerSnapshot(
                originalPrincipal: principal,
                increases: 0,
                repayments: record.status == .settled ? principal : 0,
                outstanding: manualOutstanding,
                status: record.status,
                settledDate: record.settledDate
            )
        }

        var increases: Decimal = 0
        var repayments: Decimal = 0
        var lastRepaymentDate: Date?
        let calendar = Calendar.current

        for transaction in transactions where transaction.date <= requestedDate && transaction.type == .transfer {
            if transaction.accountID == liabilityID {
                let destination = account(withID: transaction.destinationAccountID)
                if isFinancialLiabilityAccount(destination) { continue }

                // The original drawdown is represented by Original Principal.
                // Avoid counting an equal opening-day drawdown twice.
                let amount = transaction.amount
                let isOpeningDrawdown = calendar.isDate(transaction.date, inSameDayAs: record.startDate)
                    && principal > 0
                    && abs(amount - principal) <= tolerance
                if !isOpeningDrawdown {
                    increases += amount
                }
            } else if transaction.destinationAccountID == liabilityID {
                let source = account(withID: transaction.accountID)
                if isFinancialLiabilityAccount(source) { continue }
                repayments += effectiveDestinationAmount(transaction)
                if lastRepaymentDate == nil || transaction.date > lastRepaymentDate! {
                    lastRepaymentDate = transaction.date
                }
            }
        }

        let outstanding = max(0, principal + increases - repayments)
        let automaticallySettled = principal > 0 && outstanding <= tolerance
        return FixedLiabilityLedgerSnapshot(
            originalPrincipal: principal,
            increases: increases,
            repayments: repayments,
            outstanding: outstanding,
            status: automaticallySettled ? .settled : .active,
            settledDate: automaticallySettled ? (lastRepaymentDate ?? record.settledDate) : nil
        )
    }

    func fixedLiabilityRepaymentTransactions(
        _ record: FixedLiabilityRecord,
        asOf requestedDate: Date = Date()
    ) -> [LedgerTransaction] {
        guard let liabilityID = record.linkedAccountID else { return [] }
        return transactions.filter { transaction in
            guard transaction.type == .transfer,
                  transaction.date <= requestedDate,
                  transaction.destinationAccountID == liabilityID else { return false }
            return !isFinancialLiabilityAccount(account(withID: transaction.accountID))
        }.sorted { $0.date > $1.date }
    }

    func fixedLiabilityIncreaseTransactions(
        _ record: FixedLiabilityRecord,
        asOf requestedDate: Date = Date()
    ) -> [LedgerTransaction] {
        guard let liabilityID = record.linkedAccountID else { return [] }
        return transactions.filter { transaction in
            guard transaction.type == .transfer,
                  transaction.date <= requestedDate,
                  transaction.accountID == liabilityID else { return false }
            return !isFinancialLiabilityAccount(account(withID: transaction.destinationAccountID))
        }.sorted { $0.date > $1.date }
    }
'''
text = text.replace(account_anchor, helpers, 1)

# Financial Summary must continue treating Fixed Liability as a loan cash-flow
# account after its Chart-of-Accounts nature is changed from .loan.
old_increase = '''        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              let destination = account(withID: transaction.destinationAccountID),
              source.nature == .loan,
              destination.nature == .bank else { return 0 }
'''
new_increase = '''        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              let destination = account(withID: transaction.destinationAccountID),
              isFinancialLiabilityAccount(source),
              destination.nature == .bank else { return 0 }
'''
if text.count(old_increase) != 1:
    raise RuntimeError(f"financialSummaryLoanIncrease guard count: {text.count(old_increase)}")
text = text.replace(old_increase, new_increase, 1)

old_paid = '''        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              let destination = account(withID: transaction.destinationAccountID),
              source.nature == .bank,
              destination.nature == .loan else { return 0 }
'''
new_paid = '''        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              let destination = account(withID: transaction.destinationAccountID),
              source.nature == .bank,
              isFinancialLiabilityAccount(destination) else { return 0 }
'''
if text.count(old_paid) != 1:
    raise RuntimeError(f"financialSummaryLoanPaid guard count: {text.count(old_paid)}")
text = text.replace(old_paid, new_paid, 1)
write(store_path, text)


# ---------------------------------------------------------------------------
# Fixed Liabilities Register: replace manual-status-only screen with a ledger-
# driven register showing principal, increases, repayments and outstanding.
# ---------------------------------------------------------------------------
view_path = "DailyLedger/Views/FixedAccountingRegistersView.swift"
text = read(view_path)
start = text.find("struct FixedLiabilityRegisterView: View {")
end = text.find("private struct FixedLiabilityEditorView: View {", start)
if start < 0 or end < 0:
    raise RuntimeError("FixedLiabilityRegisterView markers missing")

new_register = r'''struct FixedLiabilityRegisterView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var filter: FixedLiabilityFilter = .active
    @State private var showingNew = false
    @State private var editing: FixedLiabilityRecord?
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                Picker("Register", selection: $filter) {
                    ForEach(FixedLiabilityFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Linked liabilities settle automatically from ledger transfers. Bank → Liability is a repayment. Liability → Bank is an increase. Liability → Liability is internal refinancing and does not count as cash repayment.")
            }

            ForEach(currencySummaries) { summary in
                Section("\(summary.currency) Summary") {
                    LabeledContent("Original Principal", value: DisplayFormat.currency(summary.originalPrincipal, code: summary.currency))
                    LabeledContent("Additional Increases", value: DisplayFormat.currency(summary.increases, code: summary.currency))
                    LabeledContent("Repaid / Settled", value: DisplayFormat.currency(summary.repayments, code: summary.currency))
                        .foregroundStyle(AppTheme.green)
                    LabeledContent("Outstanding Liability", value: DisplayFormat.currency(summary.outstanding, code: summary.currency))
                        .font(.body.bold())
                    LabeledContent("Current Portion", value: DisplayFormat.currency(summary.currentPortion, code: summary.currency))
                    LabeledContent("Long-Term Portion", value: DisplayFormat.currency(max(0, summary.outstanding - summary.currentPortion), code: summary.currency))
                }
            }

            if filtered.isEmpty {
                Section {
                    EmptyLedgerView(
                        title: filter == .settled ? "No settled liabilities" : "No fixed liabilities",
                        message: filter == .settled
                            ? "A linked liability moves here automatically when repayments reduce its outstanding amount to zero."
                            : "Register long-term loans, lease liabilities and other fixed liabilities here."
                    )
                }
            } else {
                ForEach(groupedCategories, id: \.0) { category, items in
                    Section(category) {
                        ForEach(items) { item in
                            let ledger = store.fixedLiabilitySnapshot(item)
                            Button { editing = item } label: {
                                FixedLiabilityRegisterRow(
                                    item: item,
                                    snapshot: ledger,
                                    needsDetails: needsDetails(item)
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button { editing = item } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(AppTheme.blue)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Fixed Liabilities")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Liability, lender, category")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: { Image(systemName: "plus.circle.fill") }
            }
        }
        .sheet(isPresented: $showingNew) {
            FixedLiabilityEditorView(record: nil).environmentObject(store)
        }
        .sheet(item: $editing) {
            FixedLiabilityEditorView(record: $0).environmentObject(store)
        }
    }

    private var allRegisterLiabilities: [FixedLiabilityRecord] {
        var records = store.fixedLiabilityRecords
        let linked = Set(records.compactMap(\.linkedAccountID))
        for account in store.accounts where !account.isArchived && account.nature == .fixedLiability && !linked.contains(account.id) {
            records.append(FixedLiabilityRecord(
                id: account.id,
                reference: account.chartCode ?? "",
                name: account.name,
                category: "Needs Details",
                lender: "",
                currencyCode: account.currencyCode,
                linkedAccountID: account.id,
                startDate: account.createdAt,
                originalPrincipal: store.fixedLiabilitySuggestedPrincipal(for: account),
                notes: "Created automatically from Chart of Accounts. Complete the liability register details."
            ))
        }
        return records
    }

    private func needsDetails(_ item: FixedLiabilityRecord) -> Bool {
        !store.fixedLiabilityRecords.contains(where: { $0.id == item.id })
    }

    private var filtered: [FixedLiabilityRecord] {
        allRegisterLiabilities.filter { item in
            let effective = store.fixedLiabilitySnapshot(item).status
            let statusMatches: Bool
            switch filter {
            case .active: statusMatches = effective == .active
            case .settled: statusMatches = effective == .settled
            case .all: statusMatches = true
            }
            guard statusMatches else { return false }
            guard !searchText.isEmpty else { return true }
            return item.name.localizedCaseInsensitiveContains(searchText)
                || item.lender.localizedCaseInsensitiveContains(searchText)
                || item.category.localizedCaseInsensitiveContains(searchText)
                || item.reference.localizedCaseInsensitiveContains(searchText)
        }
        .sorted { $0.startDate > $1.startDate }
    }

    private var groupedCategories: [(String, [FixedLiabilityRecord])] {
        Dictionary(grouping: filtered, by: \.category)
            .map { ($0.key, $0.value) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    private var currencySummaries: [FixedLiabilityCurrencySummary] {
        let grouped = Dictionary(grouping: filtered, by: \.currencyCode)
        var output: [FixedLiabilityCurrencySummary] = []
        for currency in grouped.keys.sorted() {
            let values = grouped[currency] ?? []
            var original: Decimal = 0
            var increases: Decimal = 0
            var repayments: Decimal = 0
            var outstanding: Decimal = 0
            var currentPortion: Decimal = 0
            for item in values {
                let ledger = store.fixedLiabilitySnapshot(item)
                original += ledger.originalPrincipal
                increases += ledger.increases
                repayments += ledger.repayments
                outstanding += ledger.outstanding
                currentPortion += min(max(0, item.currentPortion), ledger.outstanding)
            }
            output.append(FixedLiabilityCurrencySummary(
                currency: currency,
                originalPrincipal: original,
                increases: increases,
                repayments: repayments,
                outstanding: outstanding,
                currentPortion: currentPortion
            ))
        }
        return output
    }
}

private struct FixedLiabilityCurrencySummary: Identifiable {
    let currency: String
    let originalPrincipal: Decimal
    let increases: Decimal
    let repayments: Decimal
    let outstanding: Decimal
    let currentPortion: Decimal
    var id: String { currency }
}

private struct FixedLiabilityRegisterRow: View {
    let item: FixedLiabilityRecord
    let snapshot: FixedLiabilityLedgerSnapshot
    let needsDetails: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: snapshot.status == .settled ? "checkmark.seal.fill" : "calendar.badge.clock")
                    .foregroundStyle(snapshot.status == .settled ? AppTheme.green : AppTheme.orange)
                    .frame(width: 38, height: 38)
                    .background(
                        (snapshot.status == .settled ? AppTheme.green : AppTheme.orange).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 11)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.body.weight(.semibold))
                    Text([item.reference, item.lender].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(snapshot.status.title.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(snapshot.status == .settled ? AppTheme.green : AppTheme.orange)
                        if needsDetails {
                            Text("NEEDS DETAILS")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.orange)
                        }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Outstanding " + DisplayFormat.currency(snapshot.outstanding, code: item.currencyCode))
                        .font(.caption.bold())
                    Text("Repaid " + DisplayFormat.currency(snapshot.repayments, code: item.currencyCode))
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.green)
                    if let date = snapshot.settledDate, snapshot.status == .settled {
                        Text("Settled " + date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ProgressView(value: snapshot.repaymentProgress)
                .tint(snapshot.status == .settled ? AppTheme.green : AppTheme.blue)
            HStack {
                Text("Principal " + DisplayFormat.currency(snapshot.originalPrincipal, code: item.currencyCode))
                Spacer()
                if snapshot.increases > 0 {
                    Text("+ Drawdowns " + DisplayFormat.currency(snapshot.increases, code: item.currencyCode))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

'''
text = text[:start] + new_register + text[end:]

# Replace the editor entirely so linked liabilities show automatic settlement
# and real repayment activity rather than a misleading manual status switch.
start = text.find("private struct FixedLiabilityEditorView: View {")
if start < 0:
    raise RuntimeError("FixedLiabilityEditorView start missing")
# This is the final Swift type in this generated file.
end = len(text)

new_editor = r'''private struct FixedLiabilityEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FixedLiabilityRecord
    @State private var principalText: String
    @State private var rateText: String
    @State private var currentPortionText: String
    @State private var hasMaturity: Bool
    private let isNew: Bool
    private let currencies = ["QAR", "PKR", "USD", "GBP", "EUR", "AED", "SAR", "INR"]

    init(record: FixedLiabilityRecord?) {
        let value = record ?? FixedLiabilityRecord()
        _draft = State(initialValue: value)
        _principalText = State(initialValue: NSDecimalNumber(decimal: value.originalPrincipal).stringValue)
        _rateText = State(initialValue: NSDecimalNumber(decimal: value.annualInterestRate).stringValue)
        _currentPortionText = State(initialValue: NSDecimalNumber(decimal: value.currentPortion).stringValue)
        _hasMaturity = State(initialValue: value.maturityDate != nil)
        isNew = record == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Liability") {
                    TextField("Reference", text: $draft.reference)
                    TextField("Name", text: $draft.name)
                    TextField("Lender / Counterparty", text: $draft.lender)
                    Menu {
                        ForEach(store.fixedLiabilityCategories, id: \.self) { category in
                            Button(category) { draft.category = category }
                        }
                    } label: {
                        LabeledContent("Choose Category", value: draft.category)
                    }
                    TextField("Category", text: $draft.category)
                    Picker("Currency", selection: $draft.currencyCode) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Linked Liability Account", selection: $draft.linkedAccountID) {
                        Text("Not Linked").tag(Optional<UUID>.none)
                        ForEach(linkableAccounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                }

                Section("Terms") {
                    DatePicker("Start Date", selection: $draft.startDate, displayedComponents: .date)
                    Toggle("Has Maturity Date", isOn: $hasMaturity)
                    if hasMaturity {
                        DatePicker("Maturity", selection: Binding(
                            get: { draft.maturityDate ?? Date() },
                            set: { draft.maturityDate = $0 }
                        ), displayedComponents: .date)
                    }
                    TextField("Original Principal", text: $principalText)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Annual Interest %", text: $rateText)
                        .keyboardType(.decimalPad)
                    TextField("Current Portion (Next 12 Months)", text: $currentPortionText)
                        .keyboardType(.numbersAndPunctuation)
                }

                if draft.linkedAccountID != nil {
                    Section("Ledger Settlement") {
                        LabeledContent("Original Principal", value: DisplayFormat.currency(ledgerPreview.originalPrincipal, code: draft.currencyCode))
                        LabeledContent("Additional Increases", value: DisplayFormat.currency(ledgerPreview.increases, code: draft.currencyCode))
                        LabeledContent("Repaid / Settled", value: DisplayFormat.currency(ledgerPreview.repayments, code: draft.currencyCode))
                            .foregroundStyle(AppTheme.green)
                        LabeledContent("Outstanding", value: DisplayFormat.currency(ledgerPreview.outstanding, code: draft.currencyCode))
                            .font(.body.bold())
                        LabeledContent("Status", value: ledgerPreview.status.title)
                            .foregroundStyle(ledgerPreview.status == .settled ? AppTheme.green : AppTheme.orange)
                        ProgressView(value: ledgerPreview.repaymentProgress)
                            .tint(ledgerPreview.status == .settled ? AppTheme.green : AppTheme.blue)
                        if let settledDate = ledgerPreview.settledDate, ledgerPreview.status == .settled {
                            LabeledContent("Settled Date", value: settledDate.formatted(date: .long, time: .omitted))
                        }
                    } footer: {
                        Text("Status is automatic for linked liabilities. Bank → Liability reduces the outstanding amount. Liability → Bank increases it. Internal Liability → Liability transfers do not count as repayments.")
                    }

                    Section("Recent Repayments") {
                        if repaymentTransactions.isEmpty {
                            Text("No Bank/Account → Liability repayments found yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(repaymentTransactions.prefix(15)) { transaction in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(transaction.details.isEmpty ? "Liability repayment" : transaction.details)
                                            .font(.caption)
                                            .lineLimit(2)
                                        Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("−" + DisplayFormat.currency(store.effectiveDestinationAmount(transaction), code: draft.currencyCode))
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.green)
                                }
                            }
                        }
                    }
                } else {
                    Section("Status") {
                        Picker("Status", selection: $draft.status) {
                            ForEach(FixedLiabilityStatus.allCases) { Text($0.title).tag($0) }
                        }
                        if draft.status == .settled {
                            DatePicker("Settled Date", selection: Binding(
                                get: { draft.settledDate ?? Date() },
                                set: { draft.settledDate = $0 }
                            ), displayedComponents: .date)
                        }
                    } footer: {
                        Text("Link a liability account to calculate repayment and settlement automatically from ledger transactions.")
                    }
                }

                Section("Notes") {
                    TextEditor(text: $draft.notes).frame(minHeight: 90)
                }

                if !isNew {
                    Section {
                        Button("Delete Register Record", role: .destructive) {
                            store.deleteFixedLiabilityRecord(draft.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Register Fixed Liability" : "Edit Fixed Liability")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onChange(of: draft.linkedAccountID) { value in
                guard let account = store.account(withID: value) else { return }
                draft.currencyCode = account.currencyCode
                if (decimal(principalText) ?? 0) <= 0 {
                    principalText = NSDecimalNumber(decimal: store.fixedLiabilitySuggestedPrincipal(for: account)).stringValue
                }
            }
        }
    }

    private var linkableAccounts: [LedgerAccount] {
        store.activeAccounts.filter {
            $0.nature == .loan || $0.nature == .fixedLiability || $0.group == .payments
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func decimal(_ text: String) -> Decimal? {
        Decimal(
            string: text.replacingOccurrences(of: ",", with: ""),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private var previewRecord: FixedLiabilityRecord {
        var value = draft
        value.originalPrincipal = decimal(principalText) ?? 0
        value.annualInterestRate = decimal(rateText) ?? 0
        value.currentPortion = decimal(currentPortionText) ?? 0
        return value
    }

    private var ledgerPreview: FixedLiabilityLedgerSnapshot {
        store.fixedLiabilitySnapshot(previewRecord)
    }

    private var repaymentTransactions: [LedgerTransaction] {
        store.fixedLiabilityRepaymentTransactions(previewRecord)
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (decimal(principalText) ?? 0) > 0
    }

    private func save() {
        draft.originalPrincipal = decimal(principalText) ?? 0
        draft.annualInterestRate = decimal(rateText) ?? 0
        draft.currentPortion = min(decimal(currentPortionText) ?? 0, max(0, draft.originalPrincipal))
        if !hasMaturity { draft.maturityDate = nil }
        if draft.linkedAccountID != nil {
            let calculated = store.fixedLiabilitySnapshot(draft)
            draft.status = calculated.status
            draft.settledDate = calculated.settledDate
        } else if draft.status == .active {
            draft.settledDate = nil
        }
        if draft.reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.reference = String(format: "FL-%04d", store.fixedLiabilityRecords.count + 1)
        }
        store.saveFixedLiabilityRecord(draft)
        dismiss()
    }
}
'''
text = text[:start] + new_editor
write(view_path, text)


# Settings version label.
settings_path = "DailyLedger/Views/SettingsView.swift"
settings = read(settings_path)
settings, count = re.subn(
    r'LabeledContent\("Version", value: "[^"]+"\)',
    'LabeledContent("Version", value: "1.3.68")',
    settings,
    count=1,
)
if count != 1:
    raise RuntimeError("Settings version label not found")
write(settings_path, settings)

print("Prepared Next Ledger 1.3.68 build 76: ledger-driven fixed liability repayments, outstanding balances and automatic settlement; Fixed Liability retained in loan cash-flow reporting.")
