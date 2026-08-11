from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "DailyLedger/Views/FixedAccountingRegistersView.swift"
text = path.read_text(encoding="utf-8")
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
path.write_text(text, encoding="utf-8")
print("Simplified Next Ledger 1.3.68 Fixed Liabilities register for Swift 5.7 type checking.")
