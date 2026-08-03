from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "RootHideSMSQueue/Sources/main.m"

text = SOURCE.read_text(encoding="utf-8")
replacements = {
    "static NSString *QueueEvent(NSDictionary *parsed, NSString *sourceKey, NSString *sender) {":
        "__attribute__((unused)) static NSString *QueueEvent(NSDictionary *parsed, NSString *sourceKey, NSString *sender) {",
    "static void RetryPending(NSDictionary *config) {":
        "__attribute__((unused)) static void RetryPending(NSDictionary *config) {",
}

for old, new in replacements.items():
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match, found {count}: {old}")
    text = text.replace(old, new, 1)

SOURCE.write_text(text, encoding="utf-8")
print("Marked the retired direct SMS import pipeline as intentionally unused.")
