from pathlib import Path

path = Path(__file__).resolve().parents[1] / "DailyLedger/Views/SMSImportConsoleView.swift"
text = path.read_text(encoding="utf-8")
old = 'Text("\\(draftCount)")'
new = 'Text("\\\\(draftCount)")'
count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one SMS draft counter, found {count}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Prepared the existing SMS draft counter for the final interpolation cleanup.")
