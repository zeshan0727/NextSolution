from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "RootHideSMSQueue/Sources/main.m"
text = path.read_text(encoding="utf-8")
old = "static NSString *SMSDatabaseDiagnostics(void) {"
new = "__attribute__((unused)) static NSString *SMSDatabaseDiagnostics(void) {"
count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one SMSDatabaseDiagnostics helper, found {count}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Marked the retained Messages database diagnostic helper as intentionally unused.")
