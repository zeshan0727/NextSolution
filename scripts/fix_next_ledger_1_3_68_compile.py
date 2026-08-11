from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "DailyLedger/Views/FixedAccountingRegistersView.swift"
text = path.read_text(encoding="utf-8")

# ---------------------------------------------------------------------------
# Simplify the register itself for Swift 5.7 whole-module type checking.
# ---------------------------------------------------------------------------
start = text.find("struct FixedLiabilityRegisterView: View {")
end = text.find("private struct FixedLiabilityCurrencySummary", start)
if start < 0 or end < 0:
    raise RuntimeError("FixedLiabilityRegisterView / summary markers not found")

replacement = r'''struct FixedLiabilityRegisterView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var filter: FixedLiabilityFilter = .active
    @State private var showingNew = false
    @State private var editing: FixedLiabilityRecord?
    @State private var searchText = ""

    var body: some View {
        List {
            filterSection
            summarySections
            liabilitySections
        }
        .navigationTitle("Fixed Liabilities")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Liability, lender, category")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Register fixed liability")
            }
        }
        .sheet(isPresented: $showingNew) {
            FixedLiabilityEditorView(record: nil)
                .environmentObject(store)
        }
        .sheet(item: $editing) { record in
            FixedLiabilityEditorView(record: record)
                .environmentObject(store)
        }
    }

    private var filterSection: some View {
        Section {
            Picker("Register", selection: $filter) {
                ForEach(FixedLiabilityFilter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("Linked liabilities settle automatically from ledger transfers. Bank → Liability is a repayment. Liability → Bank is an increase. Liability → Liability is internal refinancing and does not count as cash repayment.")
        }
    }

    @ViewBuilder
    private var summarySections: some View {
        ForEach(currencySummaries) { summary in
            FixedLiabilitySummarySectionView(summary: summary)
        }
    }

    @ViewBuilder
    private var liabilitySections: some View {
        if filtered.isEmpty {
            Section {
                EmptyLedgerView(title: emptyTitle, message: emptyMessage)
            }
        } else {
            ForEach(groupedCategories, id: \.0) { category, items in
                Section(category) {
                    ForEach(items) { item in
                        liabilityButton(item)
                    }
                }
            }
        }
    }

    private func liabilityButton(_ item: FixedLiabilityRecord) -> some View {
        Button {
            editing = item
        } label: {
            FixedLiabilityRegisterRow(
                item: item,
                snapshot: store.fixedLiabilitySnapshot(item),
                needsDetails: needsDetails(item)
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                editing = item
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(AppTheme.blue)
        }
    }

    private var emptyTitle: String {
        filter == .settled ? "No settled liabilities" : "No fixed liabilities"
    }

    private var emptyMessage: String {
        if filter == .settled {
            return "A linked liability moves here automatically when repayments reduce its outstanding amount to zero."
        }
        return "Register long-term loans, lease liabilities and other fixed liabilities here."
    }

    private var allRegisterLiabilities: [FixedLiabilityRecord] {
        var records = store.fixedLiabilityRecords
        let linked = Set(records.compactMap(\.linkedAccountID))
        let accounts = store.accounts.filter {
            !$0.isArchived && $0.nature == .fixedLiability && !linked.contains($0.id)
        }
        for account in accounts {
            let principal = store.fixedLiabilitySuggestedPrincipal(for: account)
            records.append(FixedLiabilityRecord(
                id: account.id,
                reference: account.chartCode ?? "",
                name: account.name,
                category: "Needs Details",
                lender: "",
                currencyCode: account.currencyCode,
                linkedAccountID: account.id,
                startDate: account.createdAt,
                originalPrincipal: principal,
                notes: "Created automatically from Chart of Accounts. Complete the liability register details."
            ))
        }
        return records
    }

    private func needsDetails(_ item: FixedLiabilityRecord) -> Bool {
        !store.fixedLiabilityRecords.contains { $0.id == item.id }
    }

    private var filtered: [FixedLiabilityRecord] {
        allRegisterLiabilities.filter { item in
            let effectiveStatus = store.fixedLiabilitySnapshot(item).status
            let statusMatches: Bool
            switch filter {
            case .active:
                statusMatches = effectiveStatus == .active
            case .settled:
                statusMatches = effectiveStatus == .settled
            case .all:
                statusMatches = true
            }
            guard statusMatches else { return false }
            if searchText.isEmpty { return true }
            return item.name.localizedCaseInsensitiveContains(searchText)
                || item.lender.localizedCaseInsensitiveContains(searchText)
                || item.category.localizedCaseInsensitiveContains(searchText)
                || item.reference.localizedCaseInsensitiveContains(searchText)
        }
        .sorted { $0.startDate > $1.startDate }
    }

    private var groupedCategories: [(String, [FixedLiabilityRecord])] {
        let grouped = Dictionary(grouping: filtered, by: \.category)
        return grouped.map { ($0.key, $0.value) }
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

private struct FixedLiabilitySummarySectionView: View {
    let summary: FixedLiabilityCurrencySummary

    var body: some View {
        Section("\(summary.currency) Summary") {
            LabeledContent(
                "Original Principal",
                value: DisplayFormat.currency(summary.originalPrincipal, code: summary.currency)
            )
            LabeledContent(
                "Additional Increases",
                value: DisplayFormat.currency(summary.increases, code: summary.currency)
            )
            LabeledContent(
                "Repaid / Settled",
                value: DisplayFormat.currency(summary.repayments, code: summary.currency)
            )
            .foregroundStyle(AppTheme.green)
            LabeledContent(
                "Outstanding Liability",
                value: DisplayFormat.currency(summary.outstanding, code: summary.currency)
            )
            .font(.body.bold())
            LabeledContent(
                "Current Portion",
                value: DisplayFormat.currency(summary.currentPortion, code: summary.currency)
            )
            LabeledContent(
                "Long-Term Portion",
                value: DisplayFormat.currency(
                    max(0, summary.outstanding - summary.currentPortion),
                    code: summary.currency
                )
            )
        }
    }
}

'''
text = text[:start] + replacement + text[end:]

# ---------------------------------------------------------------------------
# The liability editor was still too large for Swift 5.7 WMO. Replace it with
# a small coordinator view plus dedicated section views. Accounting behavior is
# unchanged; only the SwiftUI expression graph is simplified.
# ---------------------------------------------------------------------------
start = text.find("private struct FixedLiabilityEditorView: View {")
end = text.find("private struct FixedAssetRegisterExportView: View {", start)
if start < 0 or end < 0:
    raise RuntimeError("FixedLiabilityEditorView / FixedAssetRegisterExportView markers not found")

editor = r'''private struct FixedLiabilityEditorView: View {
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
                liabilitySection
                termsSection
                settlementContent
                notesSection
                deleteContent
            }
            .navigationTitle(isNew ? "Register Fixed Liability" : "Edit Fixed Liability")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editorToolbar }
            .onChange(of: draft.linkedAccountID) { value in
                linkedAccountChanged(value)
            }
        }
    }

    private var liabilitySection: some View {
        FixedLiabilityIdentityEditorSection(
            reference: $draft.reference,
            name: $draft.name,
            lender: $draft.lender,
            category: $draft.category,
            currencyCode: $draft.currencyCode,
            linkedAccountID: $draft.linkedAccountID,
            categories: store.fixedLiabilityCategories,
            currencies: currencies,
            accounts: linkableAccounts
        )
    }

    private var termsSection: some View {
        FixedLiabilityTermsEditorSection(
            startDate: $draft.startDate,
            hasMaturity: $hasMaturity,
            maturityDate: maturityBinding,
            principalText: $principalText,
            rateText: $rateText,
            currentPortionText: $currentPortionText
        )
    }

    @ViewBuilder
    private var settlementContent: some View {
        if draft.linkedAccountID != nil {
            FixedLiabilitySettlementEditorSection(
                snapshot: ledgerPreview,
                currencyCode: draft.currencyCode
            )
            FixedLiabilityRepaymentsEditorSection(
                transactions: recentRepayments,
                currencyCode: draft.currencyCode
            )
            .environmentObject(store)
        } else {
            FixedLiabilityManualStatusEditorSection(
                status: $draft.status,
                settledDate: settledDateBinding
            )
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $draft.notes)
                .frame(minHeight: 90)
        }
    }

    @ViewBuilder
    private var deleteContent: some View {
        if !isNew {
            Section {
                Button("Delete Register Record", role: .destructive) {
                    store.deleteFixedLiabilityRecord(draft.id)
                    dismiss()
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", action: save)
                .disabled(!canSave)
        }
    }

    private var linkableAccounts: [LedgerAccount] {
        store.activeAccounts.filter { account in
            account.nature == .loan || account.nature == .fixedLiability || account.group == .payments
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var maturityBinding: Binding<Date> {
        Binding(
            get: { draft.maturityDate ?? Date() },
            set: { draft.maturityDate = $0 }
        )
    }

    private var settledDateBinding: Binding<Date> {
        Binding(
            get: { draft.settledDate ?? Date() },
            set: { draft.settledDate = $0 }
        )
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

    private var recentRepayments: [LedgerTransaction] {
        Array(store.fixedLiabilityRepaymentTransactions(previewRecord).prefix(15))
    }

    private var canSave: Bool {
        let nameOK = !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let categoryOK = !draft.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let principalOK = (decimal(principalText) ?? 0) > 0
        return nameOK && categoryOK && principalOK
    }

    private func linkedAccountChanged(_ value: UUID?) {
        guard let account = store.account(withID: value) else { return }
        draft.currencyCode = account.currencyCode
        if (decimal(principalText) ?? 0) <= 0 {
            let suggested = store.fixedLiabilitySuggestedPrincipal(for: account)
            principalText = NSDecimalNumber(decimal: suggested).stringValue
        }
    }

    private func save() {
        draft.originalPrincipal = decimal(principalText) ?? 0
        draft.annualInterestRate = decimal(rateText) ?? 0
        draft.currentPortion = min(
            decimal(currentPortionText) ?? 0,
            max(0, draft.originalPrincipal)
        )
        if !hasMaturity {
            draft.maturityDate = nil
        }
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

private struct FixedLiabilityIdentityEditorSection: View {
    @Binding var reference: String
    @Binding var name: String
    @Binding var lender: String
    @Binding var category: String
    @Binding var currencyCode: String
    @Binding var linkedAccountID: UUID?
    let categories: [String]
    let currencies: [String]
    let accounts: [LedgerAccount]

    var body: some View {
        Section("Liability") {
            TextField("Reference", text: $reference)
            TextField("Name", text: $name)
            TextField("Lender / Counterparty", text: $lender)
            Picker("Category", selection: $category) {
                if !categories.contains(category) && !category.isEmpty {
                    Text(category).tag(category)
                }
                ForEach(categories, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            TextField("Custom Category", text: $category)
            Picker("Currency", selection: $currencyCode) {
                ForEach(currencies, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            Picker("Linked Liability Account", selection: $linkedAccountID) {
                Text("Not Linked").tag(Optional<UUID>.none)
                ForEach(accounts) { account in
                    Text(account.name).tag(Optional(account.id))
                }
            }
        }
    }
}

private struct FixedLiabilityTermsEditorSection: View {
    @Binding var startDate: Date
    @Binding var hasMaturity: Bool
    let maturityDate: Binding<Date>
    @Binding var principalText: String
    @Binding var rateText: String
    @Binding var currentPortionText: String

    var body: some View {
        Section("Terms") {
            DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
            Toggle("Has Maturity Date", isOn: $hasMaturity)
            if hasMaturity {
                DatePicker("Maturity", selection: maturityDate, displayedComponents: .date)
            }
            TextField("Original Principal", text: $principalText)
                .keyboardType(.numbersAndPunctuation)
            TextField("Annual Interest %", text: $rateText)
                .keyboardType(.decimalPad)
            TextField("Current Portion (Next 12 Months)", text: $currentPortionText)
                .keyboardType(.numbersAndPunctuation)
        }
    }
}

private struct FixedLiabilitySettlementEditorSection: View {
    let snapshot: FixedLiabilityLedgerSnapshot
    let currencyCode: String

    var body: some View {
        Section("Ledger Settlement") {
            valueRow("Original Principal", snapshot.originalPrincipal)
            valueRow("Additional Increases", snapshot.increases)
            valueRow("Repaid / Settled", snapshot.repayments, incoming: true)
            valueRow("Outstanding Liability", snapshot.outstanding, emphasized: true)
            LabeledContent("Status", value: snapshot.status.title)
                .foregroundStyle(snapshot.status == .settled ? AppTheme.green : AppTheme.orange)
            ProgressView(value: snapshot.repaymentProgress)
                .tint(snapshot.status == .settled ? AppTheme.green : AppTheme.blue)
            if let date = snapshot.settledDate, snapshot.status == .settled {
                LabeledContent(
                    "Settled Date",
                    value: date.formatted(date: .long, time: .omitted)
                )
            }
        } footer: {
            Text("Status is automatic for linked liabilities. Bank → Liability reduces the outstanding amount. Liability → Bank increases it. Internal Liability → Liability transfers do not count as repayments.")
        }
    }

    @ViewBuilder
    private func valueRow(
        _ title: String,
        _ value: Decimal,
        incoming: Bool = false,
        emphasized: Bool = false
    ) -> some View {
        LabeledContent(title, value: DisplayFormat.currency(value, code: currencyCode))
            .font(emphasized ? .body.bold() : .body)
            .foregroundStyle(incoming ? AppTheme.green : .primary)
    }
}

private struct FixedLiabilityRepaymentsEditorSection: View {
    @EnvironmentObject private var store: LedgerStore
    let transactions: [LedgerTransaction]
    let currencyCode: String

    var body: some View {
        Section("Recent Repayments") {
            if transactions.isEmpty {
                Text("No Bank/Account → Liability repayments found yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(transactions) { transaction in
                    repaymentRow(transaction)
                }
            }
        }
    }

    private func repaymentRow(_ transaction: LedgerTransaction) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.details.isEmpty ? "Liability repayment" : transaction.details)
                    .font(.caption)
                    .lineLimit(2)
                Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("−" + DisplayFormat.currency(
                store.effectiveDestinationAmount(transaction),
                code: currencyCode
            ))
            .font(.caption.bold())
            .foregroundStyle(AppTheme.green)
        }
    }
}

private struct FixedLiabilityManualStatusEditorSection: View {
    @Binding var status: FixedLiabilityStatus
    let settledDate: Binding<Date>

    var body: some View {
        Section("Status") {
            Picker("Status", selection: $status) {
                ForEach(FixedLiabilityStatus.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            if status == .settled {
                DatePicker("Settled Date", selection: settledDate, displayedComponents: .date)
            }
        } footer: {
            Text("Link a liability account to calculate repayment and settlement automatically from ledger transactions.")
        }
    }
}

'''
text = text[:start] + editor + "\n" + text[end:]

path.write_text(text, encoding="utf-8")
print("Simplified Next Ledger 1.3.68 Fixed Liabilities register and editor for Swift 5.7 type checking.")
