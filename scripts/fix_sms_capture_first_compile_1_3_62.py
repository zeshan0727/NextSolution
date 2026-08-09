from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "RootHideSMSQueue/Sources/main.m"
text = path.read_text(encoding="utf-8")
old = 'static BOOL AutomaticScanIsDue(NSDictionary *config, NSDate *now) {'
new = '__attribute__((unused)) static BOOL AutomaticScanIsDue(NSDictionary *config, NSDate *now) {'
if text.count(old) != 1:
    raise RuntimeError(f"Expected one AutomaticScanIsDue declaration, found {text.count(old)}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Marked obsolete AutomaticScanIsDue helper unused for RootHide -Werror build.")
