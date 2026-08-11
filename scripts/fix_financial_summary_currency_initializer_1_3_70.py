from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "DailyLedger/Views/PeriodTransactionsView.swift"
text = path.read_text(encoding="utf-8")

old = '''    let kind: PeriodTransactionKind
    let interval: DateInterval
    /// Optional currency scope supplied by a currency-specific Financial Summary card.
    /// Nil preserves the existing all-currency behavior for other report entry points.
    let currencyCode: String? = nil

    var body: some View {
'''
new = '''    let kind: PeriodTransactionKind
    let interval: DateInterval
    /// Optional currency scope supplied by a currency-specific Financial Summary card.
    /// Nil preserves the existing all-currency behavior for other report entry points.
    let currencyCode: String?

    init(
        kind: PeriodTransactionKind,
        interval: DateInterval,
        currencyCode: String? = nil
    ) {
        self.kind = kind
        self.interval = interval
        self.currencyCode = currencyCode
    }

    var body: some View {
'''
if text.count(old) != 1:
    raise RuntimeError(f"Expected one PeriodTransactionsView property block, found {text.count(old)}")
text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8")
print("Added explicit optional-currency initializer to PeriodTransactionsView for Next Ledger 1.3.70.")
