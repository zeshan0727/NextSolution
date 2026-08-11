from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "DailyLedger/Views/FixedAccountingRegistersView.swift"
text = path.read_text(encoding="utf-8")

pattern = re.compile(r'''    private var currencySummaries: \[\(currency: String, cost: Decimal, accumulated: Decimal, nbv: Decimal, gainLoss: Decimal\)\] \{.*?\n    \}\n\n    private func generatePDF\(\) \{''', re.S)
replacement = '''    private var currencySummaries: [(currency: String, cost: Decimal, accumulated: Decimal, nbv: Decimal, gainLoss: Decimal)] {
        let grouped = Dictionary(grouping: assets, by: { $0.currencyCode })
        var result: [(currency: String, cost: Decimal, accumulated: Decimal, nbv: Decimal, gainLoss: Decimal)] = []
        for currency in grouped.keys.sorted() {
            let values = grouped[currency] ?? []
            var cost = Decimal.zero
            var accumulated = Decimal.zero
            var nbv = Decimal.zero
            var gainLoss = Decimal.zero
            for asset in values {
                cost += asset.cost
                accumulated += asset.accumulatedDepreciation(asOf: asOfDate)
                nbv += asset.netBookValue(asOf: asOfDate)
                gainLoss += asset.disposalGainLoss ?? 0
            }
            result.append((currency, cost, accumulated, nbv, gainLoss))
        }
        return result
    }

    private func generatePDF() {'''
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise RuntimeError(f"currencySummaries replacement count: {count}")
path.write_text(text, encoding="utf-8")
print("Simplified Next Ledger 1.3.67 FAR snapshot currency summaries for Swift 5.7 type checking.")
