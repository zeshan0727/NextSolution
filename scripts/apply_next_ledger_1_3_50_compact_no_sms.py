from __future__ import annotations

from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:80]!r}")
    write(path, text.replace(old, new, 1))


def replace_range(path: str, start_marker: str, end_marker: str, replacement: str) -> None:
    text = read(path)
    start = text.find(start_marker)
    if start < 0:
        raise RuntimeError(f"Start marker not found in {path}: {start_marker[:80]!r}")
    end_start = text.find(end_marker, start)
    if end_start < 0:
        raise RuntimeError(f"End marker not found in {path}: {end_marker[:80]!r}")
    end = end_start + len(end_marker)
    write(path, text[:start] + replacement + text[end:])


# Make Chart of Accounts rows more compact and hide balances that display as 0.00.
chart_path = "DailyLedger/Views/ChartOfAccountsView.swift"
replace_once(chart_path, "import SwiftUI\n", "import Foundation\nimport SwiftUI\n")
replace_once(
    chart_path,
    "            .filter { !hideZeroBalanceAccounts || store.balance(for: $0) != 0 }\n",
    "            .filter { !hideZeroBalanceAccounts || !isEffectivelyZeroBalance($0) }\n",
)
replace_once(
    chart_path,
    """    private func filteredCategories(_ type: TransactionType) -> [String] {
""",
    """    private func isEffectivelyZeroBalance(_ account: LedgerAccount) -> Bool {
        var balance = store.balance(for: account)
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &balance, 2, .plain)
        return rounded == 0
    }

    private func filteredCategories(_ type: TransactionType) -> [String] {
""",
)
replace_once(
    chart_path,
    """            VStack(alignment: .leading, spacing: 3) {
                Text(account.name).font(.body.weight(.semibold))
                Text("\\(account.group.title) · \\(account.currencyCode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(DisplayFormat.currency(store.balance(for: account), code: account.currencyCode))
                .font(.caption.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
""",
    """            Text(account.name)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(DisplayFormat.currency(store.balance(for: account), code: account.currencyCode))
                    .font(.caption.bold().monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(account.group.title.uppercased())
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
""",
)

# Remove the RootHide SMS importer UI while keeping vendor-category rules available.
settings_path = "DailyLedger/Views/SettingsView.swift"
replace_once(settings_path, "    @State private var showingSMSStatus = true\n", "")
settings_start = """                Section {
                    if showingSMSStatus, let result = store.settings.smsImporterLastResult, !result.isEmpty {
"""
settings_end = """                } footer: {
                    Text("Shows the latest importer result and lets you record the latest matching bank message or cancel the prompt.")
                }
"""
settings_replacement = """                Section {
                    NavigationLink {
                        VendorRulesView()
                    } label: {
                        SettingsRow(
                            title: "Vendor Category Rules",
                            subtitle: "Match vendor words to expense categories",
                            icon: "tag.fill",
                            color: AppTheme.purple
                        )
                    }
                } header: {
                    Label("Vendor Rules", systemImage: "tag.fill")
                } footer: {
                    Text("Vendor rules remain available for automatic transaction categorization.")
                }
"""
replace_range(settings_path, settings_start, settings_end, settings_replacement)

sms_view = ROOT / "DailyLedger/Views/SMSImportPreferencesView.swift"
if not sms_view.exists():
    raise RuntimeError("SMSImportPreferencesView.swift was already missing")
sms_view.unlink()

# Remove importer methods and serialized importer settings from the app model.
store_path = "DailyLedger/Services/LedgerStore.swift"
store_text = read(store_path)
method_pattern = re.compile(
    r"\n    func updateSMSAutoImport\(_ enabled: Bool\) \{.*?\n    \}\n\n"
    r"    func updateSMSPreferences\(matchText: String, destinationAccountID: UUID\?\) \{.*?\n    \}\n\n"
    r"    func requestSMSRescan\(\) \{.*?\n    \}\n",
    re.DOTALL,
)
store_text, count = method_pattern.subn("\n", store_text, count=1)
if count != 1:
    raise RuntimeError(f"Expected one SMS method block in {store_path}, found {count}")
write(store_path, store_text)

model_path = "DailyLedger/Models/LedgerTransaction.swift"
model_text = read(model_path)
sms_fields = (
    "smsAutoImportEnabled",
    "smsMatchText",
    "smsDestinationAccountID",
    "smsRescanRequestID",
    "smsImporterLastCheck",
    "smsImporterLastResult",
)
for field in sms_fields:
    if field not in model_text:
        raise RuntimeError(f"Expected {field} in {model_path}")
sms_normalize_block = """        if settings.smsDestinationAccountID == nil ||
            !activeAccounts.contains(where: { $0.id == settings.smsDestinationAccountID }) {
            settings.smsDestinationAccountID = activeAccounts.first(where: {
                $0.name.caseInsensitiveCompare(\"Credit Card\") == .orderedSame
            })?.id ?? fallbackID
        }
"""
if model_text.count(sms_normalize_block) != 1:
    raise RuntimeError("Expected one SMS destination normalization block")
model_text = model_text.replace(sms_normalize_block, "", 1)
model_lines = model_text.splitlines()
model_text = "\n".join(
    line for line in model_lines if not any(field in line for field in sms_fields)
) + "\n"
write(model_path, model_text)

replace_once(
    "DailyLedger/Services/LedgerDiskStore.swift",
    "                    ledger.settings.smsDestinationAccountID = nil\n",
    "",
)
replace_once(
    "DailyLedger/Views/InsightsView.swift",
    "without raw SMS text, account numbers, or individual vendor descriptions.",
    "without raw transaction descriptions, account numbers, or individual vendor descriptions.",
)

# Add a durable link between an original transaction and each reversing refund entry.
replace_once(
    model_path,
    """    var destinationAmount: Decimal?
    let createdAt: Date
""",
    """    var destinationAmount: Decimal?
    var refundOfTransactionID: UUID?
    let createdAt: Date
""",
)
replace_once(
    model_path,
    """        destinationAccountID: UUID? = nil,
        destinationAmount: Decimal? = nil,
        createdAt: Date = Date()
""",
    """        destinationAccountID: UUID? = nil,
        destinationAmount: Decimal? = nil,
        refundOfTransactionID: UUID? = nil,
        createdAt: Date = Date()
""",
)
replace_once(
    model_path,
    """        self.destinationAccountID = destinationAccountID
        self.destinationAmount = destinationAmount
        self.createdAt = createdAt
""",
    """        self.destinationAccountID = destinationAccountID
        self.destinationAmount = destinationAmount
        self.refundOfTransactionID = refundOfTransactionID
        self.createdAt = createdAt
""",
)

# Record refunds as new opposite transactions on the selected refund date.
refund_store_methods = r'''
    func refundedAmount(for transaction: LedgerTransaction) -> Decimal {
        transactions.reduce(Decimal.zero) { total, item in
            item.refundOfTransactionID == transaction.id ? total + item.amount : total
        }
    }

    func refundableAmount(for transaction: LedgerTransaction) -> Decimal {
        max(Decimal.zero, transaction.amount - refundedAmount(for: transaction))
    }

    @discardableResult
    func addRefund(
        for transaction: LedgerTransaction,
        amount: Decimal,
        date: Date,
        details: String
    ) -> Bool {
        guard transaction.type != .transfer, transaction.refundOfTransactionID == nil else {
            errorMessage = "This transaction cannot be refunded."
            return false
        }
        let remaining = refundableAmount(for: transaction)
        guard amount > 0, amount <= remaining else {
            errorMessage = "Refund amount must be greater than zero and no more than the remaining refundable amount."
            return false
        }

        let reverseType: TransactionType = transaction.type == .expense ? .income : .expense
        let cleanedNote = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalLabel: String
        if let vendor = transaction.vendor, !vendor.isEmpty {
            originalLabel = vendor
        } else if !transaction.details.isEmpty {
            originalLabel = transaction.details
        } else {
            originalLabel = transaction.category
        }
        let refundDetails = cleanedNote.isEmpty
            ? "Refund of \(originalLabel)"
            : "Refund of \(originalLabel) · \(cleanedNote)"
        let refund = LedgerTransaction(
            type: reverseType,
            amount: amount,
            date: date,
            category: transaction.category,
            vendor: transaction.vendor,
            details: refundDetails,
            accountID: transaction.accountID,
            refundOfTransactionID: transaction.id
        )

        do {
            let ledger = try LedgerDiskStore.shared.mutate { ledger in
                ledger.transactions.append(refund)
            }
            apply(ledger)
            return true
        } catch {
            errorMessage = "The refund could not be recorded."
            return false
        }
    }
'''
replace_once(
    store_path,
    """    func dismissRecordingCard(_ id: UUID) {
""",
    refund_store_methods + "\n    func dismissRecordingCard(_ id: UUID) {\n",
)

# Expose Refund from every non-transfer transaction review screen.
snapshot_path = "DailyLedger/Views/CategoryTransactionsView.swift"
replace_once(
    snapshot_path,
    """    @State private var editing = false
    @State private var splitting = false
    let transaction: LedgerTransaction
""",
    """    @State private var editing = false
    @State private var splitting = false
    @State private var refunding = false
    let transaction: LedgerTransaction
""",
)
replace_once(
    snapshot_path,
    """                if !transaction.details.isEmpty {
                    Section("Description") {
                        Text(transaction.details)
                            .textSelection(.enabled)
                    }
                }
            }
""",
    r'''                if !transaction.details.isEmpty {
                    Section("Description") {
                        Text(transaction.details)
                            .textSelection(.enabled)
                    }
                }

                if transaction.refundOfTransactionID != nil {
                    Section("Refund") {
                        Label("Refund transaction", systemImage: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(AppTheme.green)
                        Text("This entry reverses an earlier transaction on this refund date.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if transaction.type != .transfer {
                    Section("Refund") {
                        if refundedAmount > 0 {
                            LabeledContent(
                                "Refunded",
                                value: DisplayFormat.currency(refundedAmount, code: currencyCode)
                            )
                            LabeledContent(
                                "Remaining",
                                value: DisplayFormat.currency(refundableAmount, code: currencyCode)
                            )
                        }
                        Button {
                            refunding = true
                        } label: {
                            Label(
                                refundableAmount > 0 ? "Record Refund" : "Fully Refunded",
                                systemImage: "arrow.uturn.backward.circle.fill"
                            )
                        }
                        .disabled(refundableAmount <= 0)
                    } footer: {
                        Text("A refund creates a new opposite transaction using the refund amount and refund date. The original transaction and its original date remain unchanged.")
                    }
                }
            }
''',
)
replace_once(
    snapshot_path,
    """                        if transaction.type != .transfer {
""",
    """                        if transaction.type != .transfer &&
                            transaction.refundOfTransactionID == nil && refundedAmount == 0 {
""",
)
replace_once(
    snapshot_path,
    """            .sheet(isPresented: $splitting) {
                SplitTransactionView(transaction: transaction)
                    .environmentObject(store)
            }
            .sheet(isPresented: $editing) {
""",
    """            .sheet(isPresented: $splitting) {
                SplitTransactionView(transaction: transaction)
                    .environmentObject(store)
            }
            .sheet(isPresented: $refunding) {
                RefundTransactionView(transaction: transaction)
                    .environmentObject(store)
            }
            .sheet(isPresented: $editing) {
""",
)
replace_once(
    snapshot_path,
    """            }
        }
    }
}
""",
    r'''            }
        }
    }

    private var currencyCode: String {
        store.account(withID: transaction.accountID)?.currencyCode ?? store.currencyCode
    }

    private var refundedAmount: Decimal {
        store.refundedAmount(for: transaction)
    }

    private var refundableAmount: Decimal {
        store.refundableAmount(for: transaction)
    }
}
''',
)

refund_view_path = "DailyLedger/Views/RefundTransactionView.swift"
if (ROOT / refund_view_path).exists():
    raise RuntimeError("RefundTransactionView.swift already exists")
write(
    refund_view_path,
    r'''import SwiftUI

struct RefundTransactionView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let transaction: LedgerTransaction

    @State private var amountText = ""
    @State private var refundDate = Date()
    @State private var note = ""
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Original Transaction") {
                    LabeledContent("Type", value: transaction.type.title)
                    LabeledContent(
                        "Original Amount",
                        value: DisplayFormat.currency(transaction.amount, code: currencyCode)
                    )
                    if refundedAmount > 0 {
                        LabeledContent(
                            "Already Refunded",
                            value: DisplayFormat.currency(refundedAmount, code: currencyCode)
                        )
                    }
                    LabeledContent(
                        "Available to Refund",
                        value: DisplayFormat.currency(remainingAmount, code: currencyCode)
                    )
                    LabeledContent(
                        "Account",
                        value: store.account(withID: transaction.accountID)?.name ?? "Unknown"
                    )
                }

                Section {
                    TextField("Refund amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("Refund Date", selection: $refundDate, displayedComponents: .date)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Refund Details")
                } footer: {
                    Text("Next Ledger records a new \(reverseType.title.lowercased()) transaction for this amount on the selected refund date. The original transaction date is not changed.")
                }
            }
            .navigationTitle("Record Refund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRefund() }
                        .disabled(!isValidAmount)
                }
            }
            .onAppear {
                if amountText.isEmpty {
                    amountText = NSDecimalNumber(decimal: remainingAmount).stringValue
                }
            }
            .alert(
                "Refund Not Recorded",
                isPresented: Binding(
                    get: { localError != nil },
                    set: { if !$0 { localError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { localError = nil }
            } message: {
                Text(localError ?? "Please check the refund details.")
            }
        }
    }

    private var currencyCode: String {
        store.account(withID: transaction.accountID)?.currencyCode ?? store.currencyCode
    }

    private var refundedAmount: Decimal {
        store.refundedAmount(for: transaction)
    }

    private var remainingAmount: Decimal {
        store.refundableAmount(for: transaction)
    }

    private var reverseType: TransactionType {
        transaction.type == .expense ? .income : .expense
    }

    private var parsedAmount: Decimal? {
        let cleaned = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    private var isValidAmount: Bool {
        guard let amount = parsedAmount else { return false }
        return amount > 0 && amount <= remainingAmount
    }

    private func saveRefund() {
        guard let amount = parsedAmount else {
            localError = "Enter a valid refund amount."
            return
        }
        if store.addRefund(
            for: transaction,
            amount: amount,
            date: refundDate,
            details: note
        ) {
            dismiss()
        } else {
            localError = store.errorMessage ?? "The refund could not be recorded."
        }
    }
}
''',
)

# Ensure no RootHide importer source is present in the build workspace.
root_hide = ROOT / "RootHideSMSImport"
if root_hide.exists():
    shutil.rmtree(root_hide)

print("Applied compact accounts, removed RootHide SMS import, and added dated refunds.")
