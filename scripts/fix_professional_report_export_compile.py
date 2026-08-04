from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "DailyLedger/Services/ProfessionalReportExportService.swift"
text = path.read_text(encoding="utf-8")

old = '''                        .text(line.account.chartCode?.nilIfEmpty ?? "—"),
'''
new = '''                        .text(chartCodeText(line.account)),
'''
count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one inaccessible chart-code helper reference, found {count}")
text = text.replace(old, new, 1)

anchor = '''    private static func balanceSection(account: LedgerAccount, closing: Decimal) -> BalanceSheetSection {
'''
helper = '''    private static func chartCodeText(_ account: LedgerAccount) -> String {
        let value = account.chartCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "—" : value
    }

    private static func balanceSection(account: LedgerAccount, closing: Decimal) -> BalanceSheetSection {
'''
count = text.count(anchor)
if count != 1:
    raise RuntimeError(f"Expected one balance-section helper anchor, found {count}")
text = text.replace(anchor, helper, 1)

path.write_text(text, encoding="utf-8")
print("Fixed professional report chart-code formatting without cross-file private helpers.")
