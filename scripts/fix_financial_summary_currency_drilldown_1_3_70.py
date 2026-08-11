from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one match, found {count}: {old[:220]!r}")
    write(path, text.replace(old, new, 1))


# App-only update.
replace_once("project.yml", 'MARKETING_VERSION: "1.3.69"', 'MARKETING_VERSION: "1.3.70"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "77"', 'CURRENT_PROJECT_VERSION: "78"')

# Carry the exact Financial Summary movement currency into the drill-down.
reports = "DailyLedger/Views/ReportsView.swift"
replace_once(
    reports,
    '''                        PeriodTransactionsView(
                            kind: primaryKind == .income ? .loanIncreased : .loans,
                            interval: selectedInterval
                        )
''',
    '''                        PeriodTransactionsView(
                            kind: primaryKind == .income ? .loanIncreased : .loans,
                            interval: selectedInterval,
                            currencyCode: movement.currencyCode
                        )
'''
)

period = "DailyLedger/Views/PeriodTransactionsView.swift"
replace_once(
    period,
    '''    let kind: PeriodTransactionKind
    let interval: DateInterval
''',
    '''    let kind: PeriodTransactionKind
    let interval: DateInterval
    /// Optional currency scope supplied by a currency-specific Financial Summary card.
    /// Nil preserves the existing all-currency behavior for other report entry points.
    let currencyCode: String? = nil
'''
)

replace_once(
    period,
    '''        .navigationTitle(kind.title)
''',
    '''        .navigationTitle(currencyCode.map { "\\(kind.title) · \\($0)" } ?? kind.title)
'''
)

# Add a source-account currency gate only when a Financial Summary currency card supplied one.
replace_once(
    period,
    '''        store.transactions.filter { transaction in
            guard interval.contains(transaction.date) else { return false }
            let kindMatches: Bool
''',
    '''        store.transactions.filter { transaction in
            guard interval.contains(transaction.date) else { return false }
            if let currencyCode,
               (kind == .loanIncreased || kind == .loans),
               store.account(withID: transaction.accountID)?.currencyCode != currencyCode {
                return false
            }
            let kindMatches: Bool
'''
)

# A scoped loan drill-down should total in the card currency using the raw movement amount,
# not convert the footer back to the app's reporting/base currency.
replace_once(
    period,
    '''            case .loanIncreased:
                return $0 + (store.convertedFinancialSummaryLoanIncreaseAmount($1) ?? 0)
            case .loans:
                return $0 + (store.convertedFinancialSummaryLoanPaidAmount($1) ?? 0)
''',
    '''            case .loanIncreased:
                if currencyCode != nil {
                    return $0 + store.financialSummaryLoanIncreaseAmount($1)
                }
                return $0 + (store.convertedFinancialSummaryLoanIncreaseAmount($1) ?? 0)
            case .loans:
                if currencyCode != nil {
                    return $0 + store.financialSummaryLoanPaidAmount($1)
                }
                return $0 + (store.convertedFinancialSummaryLoanPaidAmount($1) ?? 0)
'''
)

replace_once(
    period,
    '''                    Text(DisplayFormat.currency(total, code: store.currencyCode)).bold()
''',
    '''                    Text(DisplayFormat.currency(total, code: currencyCode ?? store.currencyCode)).bold()
'''
)

# Visible app version.
settings = "DailyLedger/Views/SettingsView.swift"
text = read(settings)
old = 'LabeledContent("Version", value: "1.3.69")'
new = 'LabeledContent("Version", value: "1.3.70")'
if old not in text:
    raise RuntimeError("Settings 1.3.69 version marker missing")
write(settings, text.replace(old, new, 1))

print("Prepared Next Ledger 1.3.70 build 78: Financial Summary loan drill-downs are scoped to the tapped currency and totals stay in that currency.")
