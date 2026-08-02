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

snapshot_path = ROOT / "DailyLedger/Views/CategoryTransactionsView.swift"
snapshot = snapshot_path.read_text(encoding="utf-8")
old_start = '''                } else if transaction.type != .transfer {
                    Section("Refund") {
'''
new_start = '''                } else if transaction.type != .transfer {
                    Section {
'''
old_footer = '''                    } footer: {
                        Text("A refund creates a new opposite transaction using the refund amount and refund date. The original transaction and its original date remain unchanged.")
'''
new_footer = '''                    } header: {
                        Text("Refund")
                    } footer: {
                        Text("A refund creates a new opposite transaction using the refund amount and refund date. The original transaction and its original date remain unchanged.")
'''
if snapshot.count(old_start) != 1 or snapshot.count(old_footer) != 1:
    raise RuntimeError("Expected one refundable transaction Section")
snapshot = snapshot.replace(old_start, new_start, 1)
snapshot = snapshot.replace(old_footer, new_footer, 1)
snapshot_path.write_text(snapshot, encoding="utf-8")

print("Fixed refund Swift interpolation, key paths, and iOS 16 Section layout.")
