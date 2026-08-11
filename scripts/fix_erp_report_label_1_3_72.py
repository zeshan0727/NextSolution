from pathlib import Path

path = Path(__file__).resolve().parents[1] / "DailyLedger/Views/ERPReportDesignerView.swift"
text = path.read_text(encoding="utf-8")
changes = 0
for old, new in [
    ('addTemplate("Cash Flow")', 'addTemplate("Net Cash Flow")'),
    ('Label("Add Cash Flow", systemImage:', 'Label("Add Net Cash Flow", systemImage:'),
]:
    if old in text:
        text = text.replace(old, new, 1)
        changes += 1
if changes == 0 and 'Net Cash Flow' not in text:
    raise SystemExit("Cash Flow template label anchor missing")
path.write_text(text, encoding="utf-8")
print(f"Aligned ERP report designer Cash Flow label to Net Cash Flow ({changes} change(s)).")
