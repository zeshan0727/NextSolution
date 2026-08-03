from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
reports = ROOT / "DailyLedger/Views/ReportsView.swift"
text = reports.read_text(encoding="utf-8")

old = r'''    private func consolidatedRow(title: String, amount: Decimal) -> some View {
        LabeledContent {
            Text(title)
                .font(.subheadline.weight(title == "Change" ? .bold : .regular))
        } value: {
            Text(DisplayFormat.currency(amount, code: store.currencyCode))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(amount >= 0 ? AppTheme.green : AppTheme.red)
        }
    }
'''

new = r'''    private func consolidatedRow(title: String, amount: Decimal) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(title == "Change" ? .bold : .regular))
            Spacer(minLength: 8)
            Text(DisplayFormat.currency(amount, code: store.currencyCode))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(amount >= 0 ? AppTheme.green : AppTheme.red)
                .multilineTextAlignment(.trailing)
        }
    }
'''

count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one consolidated-row match, found {count}")

reports.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Fixed Loan Summary Comparison consolidated rows for iOS 16.")
