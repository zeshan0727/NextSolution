from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "DailyLedger/Views/ReportsView.swift"
text = path.read_text(encoding="utf-8")

old = '''                        PeriodTransactionsView(
                            kind: primaryKind == .income ? .loanIncreased : .loans,
                            interval: selectedInterval,
                            currencyCode: movement.currencyCode
                        )
'''
new = '''                        financialSummaryMovementDestination(
                            primaryKind: primaryKind,
                            currencyCode: movement.currencyCode
                        )
'''
if text.count(old) != 1:
    raise RuntimeError(f"Expected one currency movement destination, found {text.count(old)}")
text = text.replace(old, new, 1)

marker = "    private func formulaOperator("
index = text.find(marker)
if index < 0:
    raise RuntimeError("formulaOperator marker missing")

helper = '''    private func financialSummaryMovementDestination(
        primaryKind: PeriodTransactionKind,
        currencyCode: String
    ) -> PeriodTransactionsView {
        PeriodTransactionsView(
            kind: primaryKind == .income ? .loanIncreased : .loans,
            interval: selectedInterval,
            currencyCode: currencyCode
        )
    }

'''
text = text[:index] + helper + text[index:]
path.write_text(text, encoding="utf-8")
print("Simplified Next Ledger 1.3.70 Financial Summary currency drill-down destination for Swift 5.7 type checking.")
