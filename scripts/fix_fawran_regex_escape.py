from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "RootHideSMSQueue/Sources/main.m"
text = path.read_text(encoding="utf-8")
old = r"Current Acc Bal:\s+"
new = r"Current Acc Bal:\\s+"
count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one Fawran balance regex escape, found {count}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Fixed the Fawran attributed-message regex escape for Theos Werror builds.")
