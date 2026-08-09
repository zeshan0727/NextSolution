from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "RootHideSMSQueue/Sources/main.m"
text = path.read_text(encoding="utf-8")
old = "static NSString *StringFromDecodedObject(id object) {"
new = "__attribute__((unused)) static NSString *StringFromDecodedObject(id object) {"
count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one StringFromDecodedObject declaration, found {count}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Marked obsolete decoded-object helper unused after typedstream-safe SMS migration.")
