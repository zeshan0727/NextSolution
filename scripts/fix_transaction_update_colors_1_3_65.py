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
        raise RuntimeError(f"{path}: expected one match, got {count}: {old[:160]!r}")
    write(path, text.replace(old, new, 1))


# ---------------------------------------------------------------------------
# Next Ledger 1.3.65 / build 73. App-only update; SMS daemon remains 2.2.3.
# ---------------------------------------------------------------------------
replace_once("project.yml", 'MARKETING_VERSION: "1.3.64"', 'MARKETING_VERSION: "1.3.65"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "72"', 'CURRENT_PROJECT_VERSION: "73"')


# ---------------------------------------------------------------------------
# Fix Transfer editor Update button after account changes.
# The selected accounts are the source of truth for currency. Previously the
# button also depended on transient currency-picker state, which could leave
# Update disabled after choosing a perfectly valid account.
# ---------------------------------------------------------------------------
transfer_path = "DailyLedger/Views/TransferView.swift"
text = read(transfer_path)

old_source_currency = '''    private var sourceCurrency: String {
        sourceCurrencySelection.isEmpty
            ? (sourceAccount?.currencyCode.uppercased() ?? "—")
            : sourceCurrencySelection
    }

    private var destinationCurrency: String {
        destinationCurrencySelection.isEmpty
            ? (destinationAccount?.currencyCode.uppercased() ?? "—")
            : destinationCurrencySelection
    }
'''
new_source_currency = '''    private var sourceCurrency: String {
        if let sourceAccount { return sourceAccount.currencyCode.uppercased() }
        return sourceCurrencySelection.isEmpty ? "—" : sourceCurrencySelection.uppercased()
    }

    private var destinationCurrency: String {
        if let destinationAccount { return destinationAccount.currencyCode.uppercased() }
        return destinationCurrencySelection.isEmpty ? "—" : destinationCurrencySelection.uppercased()
    }
'''
if text.count(old_source_currency) != 1:
    raise RuntimeError(f"TransferView currency source anchor count: {text.count(old_source_currency)}")
text = text.replace(old_source_currency, new_source_currency, 1)

old_can_save = '''    private var canSave: Bool {
        sourceAccountID != nil &&
            destinationAccountID != nil &&
            sourceAccountID != destinationAccountID &&
            sourceAccount?.currencyCode.caseInsensitiveCompare(sourceCurrency) == .orderedSame &&
            destinationAccount?.currencyCode.caseInsensitiveCompare(destinationCurrency) == .orderedSame &&
            sourceAmount != nil &&
            receivedAmount != nil
    }
'''
new_can_save = '''    private var canSave: Bool {
        guard let sourceAccountID,
              let destinationAccountID,
              sourceAccountID != destinationAccountID,
              sourceAccount != nil,
              destinationAccount != nil,
              sourceAmount != nil else { return false }
        return receivedAmount != nil
    }

    private var saveValidationMessage: String? {
        if sourceAccountID == nil { return "Select a source account." }
        if destinationAccountID == nil { return "Select a destination account." }
        if sourceAccountID == destinationAccountID { return "Source and destination accounts must be different." }
        if sourceAmount == nil { return "Enter a valid amount greater than zero." }
        if isCrossCurrency && receivedAmount == nil {
            return "Enter a conversion rate for this currency pair."
        }
        return nil
    }
'''
if text.count(old_can_save) != 1:
    raise RuntimeError(f"TransferView canSave anchor count: {text.count(old_can_save)}")
text = text.replace(old_can_save, new_can_save, 1)

# Keep account/currency state synchronized immediately when selecting an account.
old_source_change = '''            .onChange(of: sourceAccountID) { value in
                if let account = store.account(withID: value),
                   sourceCurrencySelection != account.currencyCode.uppercased() {
                    sourceCurrencySelection = account.currencyCode.uppercased()
                }
'''
new_source_change = '''            .onChange(of: sourceAccountID) { value in
                if let account = store.account(withID: value) {
                    sourceCurrencySelection = account.currencyCode.uppercased()
                }
'''
if text.count(old_source_change) != 1:
    raise RuntimeError(f"TransferView source onChange anchor count: {text.count(old_source_change)}")
text = text.replace(old_source_change, new_source_change, 1)

old_destination_change = '''            .onChange(of: destinationAccountID) { value in
                if let account = store.account(withID: value),
                   destinationCurrencySelection != account.currencyCode.uppercased() {
                    destinationCurrencySelection = account.currencyCode.uppercased()
                }
                configureConversion(preserveEditingRate: false)
            }
'''
new_destination_change = '''            .onChange(of: destinationAccountID) { value in
                if let account = store.account(withID: value) {
                    destinationCurrencySelection = account.currencyCode.uppercased()
                }
                configureConversion(preserveEditingRate: false)
            }
'''
if text.count(old_destination_change) != 1:
    raise RuntimeError(f"TransferView destination onChange anchor count: {text.count(old_destination_change)}")
text = text.replace(old_destination_change, new_destination_change, 1)

# When Update is unavailable for a real reason, show the exact reason instead of
# leaving only a grey button with no explanation.
old_details_section = '''                Section("Details") {
                    TextField("Description (optional)", text: $details)
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
'''
new_details_section = '''                Section("Details") {
                    TextField("Description (optional)", text: $details)
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    if let saveValidationMessage {
                        Label(saveValidationMessage, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
'''
if text.count(old_details_section) != 1:
    raise RuntimeError(f"TransferView details anchor count: {text.count(old_details_section)}")
text = text.replace(old_details_section, new_details_section, 1)
write(transfer_path, text)


# ---------------------------------------------------------------------------
# Movement colors everywhere TransactionRow is used:
#   IN  = green
#   OUT = red
# For a global transfer row, show both source OUT and destination IN even when
# both accounts use the same currency. Account-specific views color the row by
# that account's side of the transfer.
# ---------------------------------------------------------------------------
components_path = "DailyLedger/Views/Components.swift"
text = read(components_path)

text = text.replace(
    '''            Image(systemName: AppTheme.categoryIcon(transaction.category))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.categoryColor(transaction.category))
                .frame(width: 42, height: 42)
                .background(
                    AppTheme.categoryColor(transaction.category).opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
''',
    '''            Image(systemName: AppTheme.categoryIcon(transaction.category))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 42, height: 42)
                .background(
                    iconColor.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
''',
    1,
)

old_destination_line = '''                if accountID == nil,
                   transaction.type == .transfer,
                   let destination = destinationAccount,
                   destination.currencyCode != sourceAccount?.currencyCode {
                    Text("+" + DisplayFormat.currency(
                        transaction.destinationAmount ?? transaction.amount,
                        code: destination.currencyCode
                    ))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.blue)
                }
'''
new_destination_line = '''                if accountID == nil,
                   transaction.type == .transfer,
                   let destination = destinationAccount {
                    Text("IN +" + DisplayFormat.currency(
                        store.effectiveDestinationAmount(transaction),
                        code: destination.currencyCode
                    ))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.green)
                }
'''
if text.count(old_destination_line) != 1:
    raise RuntimeError(f"Components destination transfer line count: {text.count(old_destination_line)}")
text = text.replace(old_destination_line, new_destination_line, 1)

old_amount_text = '''    private var amountText: String {
        let prefix = isDestinationTransfer || transaction.type == .income ? "+" : "−"
        return prefix + DisplayFormat.currency(
            isDestinationTransfer ? (transaction.destinationAmount ?? transaction.amount) : transaction.amount,
            code: balanceAccount?.currencyCode ?? store.currencyCode
        )
    }
'''
new_amount_text = '''    private var amountText: String {
        let incoming = transaction.type == .income || isDestinationTransfer
        let prefix = incoming ? "+" : "−"
        let value = isDestinationTransfer
            ? store.effectiveDestinationAmount(transaction)
            : transaction.amount
        let signed = prefix + DisplayFormat.currency(
            value,
            code: balanceAccount?.currencyCode ?? store.currencyCode
        )
        if transaction.type == .transfer {
            return (isDestinationTransfer ? "IN " : "OUT ") + signed
        }
        return (transaction.type == .income ? "IN " : "OUT ") + signed
    }
'''
if text.count(old_amount_text) != 1:
    raise RuntimeError(f"Components amountText anchor count: {text.count(old_amount_text)}")
text = text.replace(old_amount_text, new_amount_text, 1)

old_amount_color = '''    private var amountColor: Color {
        switch transaction.type {
        case .income: return AppTheme.green
        case .expense: return AppTheme.red
        case .transfer: return AppTheme.purple
        }
    }
'''
new_amount_color = '''    private var amountColor: Color {
        switch transaction.type {
        case .income:
            return AppTheme.green
        case .expense:
            return AppTheme.red
        case .transfer:
            return isDestinationTransfer ? AppTheme.green : AppTheme.red
        }
    }

    private var iconColor: Color {
        transaction.type == .transfer
            ? amountColor
            : AppTheme.categoryColor(transaction.category)
    }
'''
if text.count(old_amount_color) != 1:
    raise RuntimeError(f"Components amountColor anchor count: {text.count(old_amount_color)}")
text = text.replace(old_amount_color, new_amount_color, 1)
write(components_path, text)


# ---------------------------------------------------------------------------
# Use the same green/red convention in report summary views which do not render
# through TransactionRow.
# ---------------------------------------------------------------------------
reports_path = "DailyLedger/Views/ReportsView.swift"
text = read(reports_path)

old_comparison = '''            Text(DisplayFormat.currency(income, code: store.currencyCode))
                .font(.caption.bold()).frame(width: 100, alignment: .trailing)
            Text(DisplayFormat.currency(expense, code: store.currencyCode))
                .font(.caption.bold()).frame(width: 100, alignment: .trailing)
'''
new_comparison = '''            Text(DisplayFormat.currency(income, code: store.currencyCode))
                .font(.caption.bold())
                .foregroundStyle(AppTheme.green)
                .frame(width: 100, alignment: .trailing)
            Text(DisplayFormat.currency(expense, code: store.currencyCode))
                .font(.caption.bold())
                .foregroundStyle(AppTheme.red)
                .frame(width: 100, alignment: .trailing)
'''
if text.count(old_comparison) == 1:
    text = text.replace(old_comparison, new_comparison, 1)

old_account_metric = '''                Text(formatted(total(type, in: interval))).font(.subheadline.bold())
'''
new_account_metric = '''                Text(formatted(total(type, in: interval)))
                    .font(.subheadline.bold())
                    .foregroundStyle(type == .income ? AppTheme.green : AppTheme.red)
'''
if text.count(old_account_metric) == 1:
    text = text.replace(old_account_metric, new_account_metric, 1)

old_nature_metric = '''            Text(currencySummary(items)).font(.caption.bold())
'''
new_nature_metric = '''            Text(currencySummary(items))
                .font(.caption.bold())
                .foregroundStyle(type == .income ? AppTheme.green : AppTheme.red)
'''
if text.count(old_nature_metric) == 1:
    text = text.replace(old_nature_metric, new_nature_metric, 1)

write(reports_path, text)


# Settings version label.
settings_path = "DailyLedger/Views/SettingsView.swift"
settings = read(settings_path)
settings, count = re.subn(
    r'LabeledContent\("Version", value: "[^"]+"\)',
    'LabeledContent("Version", value: "1.3.65")',
    settings,
    count=1,
)
if count != 1:
    raise RuntimeError("Settings version label not found")
write(settings_path, settings)

print("Prepared Next Ledger 1.3.65 build 73: reliable transaction account updates and consistent green IN / red OUT movement colors.")
