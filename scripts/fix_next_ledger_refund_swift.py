from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

for relative_path in (
    "DailyLedger/Services/LedgerStore.swift",
    "DailyLedger/Views/RefundTransactionView.swift",
):
    path = ROOT / relative_path
    text = path.read_text(encoding="utf-8")
    text = text.replace("\\\\(", "\\(")
    text = text.replace("\\\\.", "\\.")
    path.write_text(text, encoding="utf-8")

print("Fixed generated refund Swift interpolation and key paths.")
