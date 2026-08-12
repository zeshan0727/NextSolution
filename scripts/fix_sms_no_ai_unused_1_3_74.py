from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "RootHideSMSQueue/Sources/main.m"
text = path.read_text(encoding="utf-8")

block = '''                const unsigned char *guidBytesForAI = sqlite3_column_text(statement, 1);\n                NSString *guidForAI = guidBytesForAI ? [NSString stringWithUTF8String:(const char *)guidBytesForAI] : @"";\n                NSString *sourceForAI = guidForAI.length ? guidForAI : [NSString stringWithFormat:@"%lld|%@", rowID, text];\n'''
block2 = '''            const unsigned char *guidBytesForAI = sqlite3_column_text(statement, 1);\n            NSString *guidForAI = guidBytesForAI ? [NSString stringWithUTF8String:(const char *)guidBytesForAI] : @"";\n            NSString *sourceForAI = guidForAI.length ? guidForAI : [NSString stringWithFormat:@"%lld|%@", rowID, text];\n'''

removed = 0
for candidate in (block, block2):
    count = text.count(candidate)
    if count:
        text = text.replace(candidate, "")
        removed += count

if removed != 2:
    raise RuntimeError(f"Expected to remove exactly 2 obsolete AI source blocks, removed {removed}")
if "sourceForAI" in text or "guidForAI" in text or "guidBytesForAI" in text:
    raise RuntimeError("Obsolete automatic AI source variables still remain")

old_helper = "static BOOL QueueAICandidate(NSString *text, NSString *sourceKey, NSString *sender, sqlite3_int64 rowID, NSDate *date) {"
new_helper = "__attribute__((unused)) static BOOL QueueAICandidate(NSString *text, NSString *sourceKey, NSString *sender, sqlite3_int64 rowID, NSDate *date) {"
if old_helper not in text:
    raise RuntimeError("QueueAICandidate helper anchor not found")
text = text.replace(old_helper, new_helper, 1)

path.write_text(text, encoding="utf-8")
print("Removed automatic-AI call variables and retired the unused daemon AI helper.")
