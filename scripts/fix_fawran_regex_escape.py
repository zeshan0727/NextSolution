from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "RootHideSMSQueue/Sources/main.m"
text = path.read_text(encoding="utf-8")
old = r"Current Acc Bal:\s+"
new = r"Current Acc Bal:\\s+"
count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one Fawran balance regex escape, found {count}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")

runpy.run_path(str(ROOT / "scripts/prepare_financial_flow_conversion_helpers.py"), run_name="__main__")
print("Fixed the Fawran regex escape and prepared financial conversion helpers.")
