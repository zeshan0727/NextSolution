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
# Next Ledger 1.3.69 / build 77. App-only update; SMS daemon remains 2.2.3.
# Linked fixed liabilities are ledger-only: no manual principal is added on top.
# Every summary/register pane drills into the real transactions behind it.
# ---------------------------------------------------------------------------
replace_once("project.yml", 'MARKETING_VERSION: "1.3.68"', 'MARKETING_VERSION: "1.3.69"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "76"', 'CURRENT_PROJECT_VERSION: "77"')


# ---------------------------------------------------------------------------
# LedgerStore: for linked liabilities, ignore FixedLiabilityRecord.originalPrincipal.
# The account opening liability is counted once; actual transfer movements then
# increase or reduce that liability. This matches the account ledger and removes
# the prior principal + ledger double count.
# ---------------------------------------------------------------------------
store_path = "DailyLedger/Services/LedgerStore.swift"
text = read(store_path)

pattern = r'''    func fixedLiabilitySnapshot\(\n        _ record: FixedLiabilityRecord,\n        asOf requestedDate: Date = Date\(\)\n    \) -> FixedLiabilityLedgerSnapshot \{.*?\n    \}\n\n    func fixedLiabilityRepaymentTransactions'''
replacement = r'''    func fixedLiabilitySnapshot(
        _ record: FixedLiabilityRecord,
        asOf requestedDate: Date = Date()
    ) -> FixedLiabilityLedgerSnapshot {
        let tolerance: Decimal = 0.01

        guard let liabilityID = record.linkedAccountID,
              let linkedAccount = account(withID: liabilityID) else {
            // Unlinked/manual register records keep their manually entered principal.
            let manualPrincipal = max(0, record.originalPrincipal)
            let manualOutstanding = record.status == .settled ? Decimal.zero : manualPrincipal
            return FixedLiabilityLedgerSnapshot(
                originalPrincipal: manualPrincipal,
                increases: 0,
                repayments: record.status == .settled ? manualPrincipal : 0,
                outstanding: manualOutstanding,
                status: record.status,
                settledDate: record.settledDate
            )
        }

        // For a linked liability the ledger is the only source of truth.
        // Do NOT add record.originalPrincipal on top of the account movements.
        let openingLiability: Decimal = linkedAccount.createdAt <= requestedDate
            ? abs(linkedAccount.openingBalance)
            : 0

        var increases: Decimal = 0
        var repayments: Decimal = 0
        var lastRepaymentDate: Date?

        for transaction in transactions where transaction.date <= requestedDate && transaction.type == .transfer {
            if transaction.accountID == liabilityID {
                let destination = account(withID: transaction.destinationAccountID)
                if isFinancialLiabilityAccount(destination) { continue }
                // Liability -> Bank/other account = loan drawdown / liability increase.
                increases += transaction.amount
            } else if transaction.destinationAccountID == liabilityID {
                let source = account(withID: transaction.accountID)
                if isFinancialLiabilityAccount(source) { continue }
                // Bank/other account -> Liability = installment / repayment.
                repayments += effectiveDestinationAmount(transaction)
                if lastRepaymentDate == nil || transaction.date > lastRepaymentDate! {
                    lastRepaymentDate = transaction.date
                }
            }
        }

        let totalLoanRecorded = openingLiability + increases
        let outstanding = max(0, totalLoanRecorded - repayments)
        let automaticallySettled = totalLoanRecorded > 0 && outstanding <= tolerance
        return FixedLiabilityLedgerSnapshot(
            originalPrincipal: openingLiability,
            increases: increases,
            repayments: repayments,
            outstanding: outstanding,
            status: automaticallySettled ? .settled : .active,
            settledDate: automaticallySettled ? (lastRepaymentDate ?? record.settledDate) : nil
        )
    }

    func fixedLiabilityRepaymentTransactions'''
text, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
if count != 1:
    raise RuntimeError(f"fixedLiabilitySnapshot replacement count: {count}")

increase_anchor = r'''    func fixedLiabilityIncreaseTransactions(
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
if text.count(increase_anchor) != 1:
    raise RuntimeError("fixedLiabilityIncreaseTransactions anchor missing")
all_helper = increase_anchor + r'''

    func fixedLiabilityAllTransactions(
        _ record: FixedLiabilityRecord,
        asOf requestedDate: Date = Date()
    ) -> [LedgerTransaction] {
        let combined = fixedLiabilityIncreaseTransactions(record, asOf: requestedDate)
            + fixedLiabilityRepaymentTransactions(record, asOf: requestedDate)
        var seen = Set<UUID>()
        return combined
            .sorted { $0.date > $1.date }
            .filter { seen.insert($0.id).inserted }
    }
'''
text = text.replace(increase_anchor, all_helper, 1)
write(store_path, text)


# ---------------------------------------------------------------------------
# Fixed Liabilities Register: tapping a liability opens its real ledger
# movements; Edit remains available through swipe action.
# Summary figures also open exact related transactions.
# ---------------------------------------------------------------------------
view_path = "DailyLedger/Views/FixedAccountingRegistersView.swift"
text = read(view_path)

old_footer = 'Text("Linked liabilities settle automatically from ledger transfers. Bank → Liability is a repayment. Liability → Bank is an increase. Liability → Liability is internal refinancing and does not count as cash repayment.")'
new_footer = 'Text("Linked liabilities use the account ledger only. No manual principal is added. Liability → Bank/Account records loan taken; Bank/Account → Liability records installments. Liability → Liability is internal refinancing.")'
if text.count(old_footer) != 1:
    raise RuntimeError("liability register footer anchor missing")
text = text.replace(old_footer, new_footer, 1)

old_summary_sections = r'''    @ViewBuilder
    private var summarySections: some View {
        ForEach(currencySummaries) { summary in
            FixedLiabilitySummarySectionView(summary: summary)
        }
    }
'''
new_summary_sections = r'''    @ViewBuilder
    private var summarySections: some View {
        ForEach(currencySummaries) { summary in
            FixedLiabilitySummarySectionView(
                summary: summary,
                loanTransactions: increaseTransactions(for: summary.currency),
                installmentTransactions: repaymentTransactions(for: summary.currency),
                allTransactions: allTransactions(for: summary.currency),
                liabilityAccountIDs: liabilityAccountIDs(for: summary.currency)
            )
            .environmentObject(store)
        }
    }
'''
if text.count(old_summary_sections) != 1:
    raise RuntimeError("summarySections anchor missing")
text = text.replace(old_summary_sections, new_summary_sections, 1)

old_liability_button = r'''    private func liabilityButton(_ item: FixedLiabilityRecord) -> some View {
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
'''
new_liability_button = r'''    private func liabilityButton(_ item: FixedLiabilityRecord) -> some View {
        NavigationLink {
            FixedLiabilityTransactionDrilldownView(
                title: item.name,
                transactions: store.fixedLiabilityAllTransactions(item),
                liabilityAccountIDs: Set(item.linkedAccountID.map { [$0] } ?? []),
                openingAmount: store.fixedLiabilitySnapshot(item).originalPrincipal,
                currencyCode: item.currencyCode
            )
            .environmentObject(store)
        } label: {
            FixedLiabilityRegisterRow(
                item: item,
                snapshot: store.fixedLiabilitySnapshot(item),
                needsDetails: needsDetails(item)
            )
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                editing = item
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(AppTheme.blue)
        }
    }
'''
if text.count(old_liability_button) != 1:
    raise RuntimeError("liabilityButton anchor missing")
text = text.replace(old_liability_button, new_liability_button, 1)

# Add aggregate transaction helpers before currencySummaries.
summary_anchor = r'''    private var currencySummaries: [FixedLiabilityCurrencySummary] {
'''
if text.count(summary_anchor) != 1:
    raise RuntimeError("currencySummaries anchor missing")
summary_helpers = r'''    private func records(for currency: String) -> [FixedLiabilityRecord] {
        filtered.filter { $0.currencyCode == currency }
    }

    private func increaseTransactions(for currency: String) -> [LedgerTransaction] {
        uniqueTransactions(records(for: currency).flatMap { store.fixedLiabilityIncreaseTransactions($0) })
    }

    private func repaymentTransactions(for currency: String) -> [LedgerTransaction] {
        uniqueTransactions(records(for: currency).flatMap { store.fixedLiabilityRepaymentTransactions($0) })
    }

    private func allTransactions(for currency: String) -> [LedgerTransaction] {
        uniqueTransactions(records(for: currency).flatMap { store.fixedLiabilityAllTransactions($0) })
    }

    private func liabilityAccountIDs(for currency: String) -> Set<UUID> {
        Set(records(for: currency).compactMap(\.linkedAccountID))
    }

    private func uniqueTransactions(_ values: [LedgerTransaction]) -> [LedgerTransaction] {
        var seen = Set<UUID>()
        return values
            .sorted { $0.date > $1.date }
            .filter { seen.insert($0.id).inserted }
    }

'''
text = text.replace(summary_anchor, summary_helpers + summary_anchor, 1)

# Replace the complete summary view with tappable ledger drill-down rows.
start = text.find("private struct FixedLiabilitySummarySectionView: View {")
end = text.find("private struct FixedLiabilityCurrencySummary", start)
if start < 0 or end < 0:
    raise RuntimeError("FixedLiabilitySummarySectionView markers missing")
summary_view = r'''private struct FixedLiabilitySummarySectionView: View {
    @EnvironmentObject private var store: LedgerStore
    let summary: FixedLiabilityCurrencySummary
    let loanTransactions: [LedgerTransaction]
    let installmentTransactions: [LedgerTransaction]
    let allTransactions: [LedgerTransaction]
    let liabilityAccountIDs: Set<UUID>

    var body: some View {
        Section {
            NavigationLink {
                drilldown(
                    title: "Loan Recorded · \(summary.currency)",
                    transactions: loanTransactions,
                    openingAmount: summary.originalPrincipal
                )
            } label: {
                valueRow("Loan Recorded", summary.originalPrincipal + summary.increases)
            }

            NavigationLink {
                drilldown(
                    title: "Installments Paid · \(summary.currency)",
                    transactions: installmentTransactions,
                    openingAmount: 0
                )
            } label: {
                valueRow("Installments Paid", summary.repayments, green: true)
            }

            NavigationLink {
                drilldown(
                    title: "Outstanding Liability · \(summary.currency)",
                    transactions: allTransactions,
                    openingAmount: summary.originalPrincipal
                )
            } label: {
                valueRow("Outstanding Liability", summary.outstanding, bold: true)
            }

            NavigationLink {
                drilldown(
                    title: "Current Portion · \(summary.currency)",
                    transactions: allTransactions,
                    openingAmount: summary.originalPrincipal
                )
            } label: {
                valueRow("Current Portion", summary.currentPortion)
            }

            NavigationLink {
                drilldown(
                    title: "Long-Term Portion · \(summary.currency)",
                    transactions: allTransactions,
                    openingAmount: summary.originalPrincipal
                )
            } label: {
                valueRow(
                    "Long-Term Portion",
                    max(0, summary.outstanding - summary.currentPortion)
                )
            }
        } header: {
            Text("\(summary.currency) Summary")
        } footer: {
            Text("Tap any figure to open the real liability-account transactions behind it.")
        }
    }

    private func drilldown(
        title: String,
        transactions: [LedgerTransaction],
        openingAmount: Decimal
    ) -> some View {
        FixedLiabilityTransactionDrilldownView(
            title: title,
            transactions: transactions,
            liabilityAccountIDs: liabilityAccountIDs,
            openingAmount: openingAmount,
            currencyCode: summary.currency
        )
        .environmentObject(store)
    }

    @ViewBuilder
    private func valueRow(
        _ title: String,
        _ value: Decimal,
        green: Bool = false,
        bold: Bool = false
    ) -> some View {
        LabeledContent(title, value: DisplayFormat.currency(value, code: summary.currency))
            .font(bold ? .body.bold() : .body)
            .foregroundStyle(green ? AppTheme.green : .primary)
    }
}

'''
text = text[:start] + summary_view + text[end:]

# Insert a reusable exact-transaction drilldown before the editor.
editor_marker = "private struct FixedLiabilityEditorView: View {"
if text.count(editor_marker) != 1:
    raise RuntimeError("FixedLiabilityEditorView marker missing")
drilldown_view = r'''private struct FixedLiabilityTransactionDrilldownView: View {
    @EnvironmentObject private var store: LedgerStore
    let title: String
    let transactions: [LedgerTransaction]
    let liabilityAccountIDs: Set<UUID>
    let openingAmount: Decimal
    let currencyCode: String

    var body: some View {
        List {
            if openingAmount > 0 {
                Section("Opening Liability") {
                    LabeledContent(
                        "Opening Balance",
                        value: DisplayFormat.currency(openingAmount, code: currencyCode)
                    )
                    Text("Opening balance is counted once. It is not a transaction and is never added again as manual principal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if transactions.isEmpty {
                    Text("No posted transaction is behind this amount yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(transactions) { transaction in
                        NavigationLink {
                            TransactionSnapshotView(transaction: transaction)
                                .environmentObject(store)
                        } label: {
                            TransactionRow(
                                transaction: transaction,
                                accountID: relevantLiabilityAccountID(transaction)
                            )
                        }
                    }
                }
            } header: {
                Text("Related Transactions")
            } footer: {
                Text("\(transactions.count) real transaction\(transactions.count == 1 ? "" : "s")")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func relevantLiabilityAccountID(_ transaction: LedgerTransaction) -> UUID? {
        if let source = transaction.accountID, liabilityAccountIDs.contains(source) {
            return source
        }
        if let destination = transaction.destinationAccountID,
           liabilityAccountIDs.contains(destination) {
            return destination
        }
        return transaction.accountID
    }
}

'''
text = text.replace(editor_marker, drilldown_view + editor_marker, 1)

# Register row: show one Loan Recorded total rather than principal + increases.
old_row = r'''            HStack {
                Text("Principal " + DisplayFormat.currency(snapshot.originalPrincipal, code: item.currencyCode))
                Spacer()
                if snapshot.increases > 0 {
                    Text("+ Drawdowns " + DisplayFormat.currency(snapshot.increases, code: item.currencyCode))
                }
            }
'''
new_row = r'''            HStack {
                Text("Loan Recorded " + DisplayFormat.currency(
                    snapshot.originalPrincipal + snapshot.increases,
                    code: item.currencyCode
                ))
                Spacer()
                Text("Installments " + DisplayFormat.currency(snapshot.repayments, code: item.currencyCode))
            }
'''
if text.count(old_row) != 1:
    raise RuntimeError(f"FixedLiabilityRegisterRow principal row count: {text.count(old_row)}")
text = text.replace(old_row, new_row, 1)

# Editor: linked liabilities no longer depend on a manually entered principal.
old_terms_call = r'''            maturityDate: maturityBinding,
            principalText: $principalText,
            rateText: $rateText,
'''
new_terms_call = r'''            maturityDate: maturityBinding,
            principalText: $principalText,
            usesLinkedLedger: draft.linkedAccountID != nil,
            rateText: $rateText,
'''
if text.count(old_terms_call) != 1:
    raise RuntimeError("terms call anchor missing")
text = text.replace(old_terms_call, new_terms_call, 1)

old_principal_prop = r'''    @Binding var principalText: String
    @Binding var rateText: String
'''
new_principal_prop = r'''    @Binding var principalText: String
    let usesLinkedLedger: Bool
    @Binding var rateText: String
'''
if text.count(old_principal_prop) != 1:
    raise RuntimeError("terms principal property anchor missing")
text = text.replace(old_principal_prop, new_principal_prop, 1)

old_principal_field = r'''            TextField("Original Principal", text: $principalText)
                .keyboardType(.numbersAndPunctuation)
'''
new_principal_field = r'''            if usesLinkedLedger {
                LabeledContent("Loan Amount", value: "From linked account ledger")
                Text("Manual Original Principal is not added for linked liabilities, preventing double counting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TextField("Original Principal", text: $principalText)
                    .keyboardType(.numbersAndPunctuation)
            }
'''
if text.count(old_principal_field) != 1:
    raise RuntimeError("Original Principal field anchor missing")
text = text.replace(old_principal_field, new_principal_field, 1)

old_linked_changed = r'''    private func linkedAccountChanged(_ value: UUID?) {
        guard let account = store.account(withID: value) else { return }
        draft.currencyCode = account.currencyCode
        if (decimal(principalText) ?? 0) <= 0 {
            let suggested = store.fixedLiabilitySuggestedPrincipal(for: account)
            principalText = NSDecimalNumber(decimal: suggested).stringValue
        }
    }
'''
new_linked_changed = r'''    private func linkedAccountChanged(_ value: UUID?) {
        guard let account = store.account(withID: value) else { return }
        draft.currencyCode = account.currencyCode
    }
'''
if text.count(old_linked_changed) != 1:
    raise RuntimeError("linkedAccountChanged anchor missing")
text = text.replace(old_linked_changed, new_linked_changed, 1)

old_can_save = r'''        let principalOK = (decimal(principalText) ?? 0) > 0
        return nameOK && categoryOK && principalOK
'''
new_can_save = r'''        let principalOK = draft.linkedAccountID != nil || (decimal(principalText) ?? 0) > 0
        return nameOK && categoryOK && principalOK
'''
if text.count(old_can_save) != 1:
    raise RuntimeError("canSave principal anchor missing")
text = text.replace(old_can_save, new_can_save, 1)

old_save_portion = r'''        draft.originalPrincipal = decimal(principalText) ?? 0
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
'''
new_save_portion = r'''        draft.originalPrincipal = decimal(principalText) ?? 0
        draft.annualInterestRate = decimal(rateText) ?? 0
        let enteredCurrentPortion = max(0, decimal(currentPortionText) ?? 0)
        draft.currentPortion = enteredCurrentPortion
        if !hasMaturity {
            draft.maturityDate = nil
        }
        if draft.linkedAccountID != nil {
            let calculated = store.fixedLiabilitySnapshot(draft)
            draft.currentPortion = min(enteredCurrentPortion, calculated.outstanding)
            draft.status = calculated.status
            draft.settledDate = calculated.settledDate
        } else {
            draft.currentPortion = min(enteredCurrentPortion, max(0, draft.originalPrincipal))
            if draft.status == .active {
                draft.settledDate = nil
            }
        }
'''
if text.count(old_save_portion) != 1:
    raise RuntimeError("save current portion anchor missing")
text = text.replace(old_save_portion, new_save_portion, 1)

# Linked settlement preview uses one Loan Recorded total and Installments terminology.
old_settlement_rows = r'''            valueRow("Original Principal", snapshot.originalPrincipal)
            valueRow("Additional Increases", snapshot.increases)
            valueRow("Repaid / Settled", snapshot.repayments, incoming: true)
            valueRow("Outstanding Liability", snapshot.outstanding, emphasized: true)
'''
new_settlement_rows = r'''            valueRow("Loan Recorded", snapshot.originalPrincipal + snapshot.increases)
            valueRow("Installments Paid", snapshot.repayments, incoming: true)
            valueRow("Outstanding Liability", snapshot.outstanding, emphasized: true)
'''
if text.count(old_settlement_rows) != 1:
    raise RuntimeError("settlement rows anchor missing")
text = text.replace(old_settlement_rows, new_settlement_rows, 1)

text = text.replace('Section("Recent Repayments") {', 'Section("Recent Installments") {', 1)
text = text.replace('Text("No Bank/Account → Liability repayments found yet.")', 'Text("No Bank/Account → Liability installments found yet.")', 1)
text = text.replace('Text(transaction.details.isEmpty ? "Liability repayment" : transaction.details)', 'Text(transaction.details.isEmpty ? "Liability installment" : transaction.details)', 1)
text = text.replace('Text("Status is automatic for linked liabilities. Bank → Liability reduces the outstanding amount. Liability → Bank increases it. Internal Liability → Liability transfers do not count as repayments.")', 'Text("Linked status comes only from the account ledger. No manual principal is added. Bank/Account → Liability is an installment; Liability → Bank/Account is loan taken/increase.")', 1)

write(view_path, text)


# Visible version.
replace_once(
    "DailyLedger/Views/SettingsView.swift",
    'LabeledContent("Version", value: "1.3.68")',
    'LabeledContent("Version", value: "1.3.69")'
)

print("Prepared Next Ledger 1.3.69 build 77: linked liabilities are ledger-only with tappable exact transaction drilldowns.")
