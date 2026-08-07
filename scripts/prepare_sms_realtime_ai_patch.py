from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "scripts/add_sms_realtime_progress_ai_1_3_51.py"
text = path.read_text(encoding="utf-8")

# Add a first-match helper for anchors that intentionally occur in both the main
# console and nested log views.
if "def replace_first(path: str, old: str, new: str)" not in text:
    anchor = "def regex_replace_once(path: str, pattern: str, replacement: str) -> None:\n"
    helper = '''def replace_first(path: str, old: str, new: str) -> None:
    content = read(path)
    if old not in content:
        raise RuntimeError(f"Expected at least one match in {path}: {old[:220]!r}")
    write(path, content.replace(old, new, 1))


'''
    if anchor not in text:
        raise RuntimeError("Could not locate realtime-patch helper insertion anchor")
    text = text.replace(anchor, helper + anchor, 1)

# This call is intentionally first-match because the generated SMS console file
# contains another @State notice in SMSImportLogsView.
needle = '''view = "DailyLedger/Views/SMSImportConsoleView.swift"
replace_once(
    view,
    ''' + "'''" + '''    @State private var notice: String?
''' + "'''" + ''',
'''
replacement = needle.replace("replace_once(", "replace_first(", 1)
if needle in text:
    text = text.replace(needle, replacement, 1)
elif replacement not in text:
    raise RuntimeError("Could not locate ambiguous SMS console notice-state patch")

# The realtime patch itself is Python generating Objective-C. The regex therefore
# needs two backslashes in the generated Objective-C string, which means four in
# the Python source. A single generated \s is only a warning with macOS clang but
# becomes a hard -Werror failure in the RootHide/Theos build.
old_regex = 'Capture(@"\\\\b(QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\\\s*[0-9]", filtered, 1)'
new_regex = 'Capture(@"\\\\\\\\b(QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\\\\\\\s*[0-9]", filtered, 1)'
if old_regex in text:
    text = text.replace(old_regex, new_regex, 1)
elif new_regex not in text:
    raise RuntimeError("Could not locate typedstream currency regex escape")

# Keep Swift actor inference simple for iOS 16 / Swift 5.7 compatibility. These
# methods are invoked from SwiftUI view tasks and update local @State.
text = text.replace(
    '''    @MainActor
    private func analyzeWithAI(force: Bool) async {''',
    '''    private func analyzeWithAI(force: Bool) async {'''
)
text = text.replace(
    '''    @MainActor
    private func applyAIRecognition(_ result: SMSAIRecognitionResult) {''',
    '''    private func applyAIRecognition(_ result: SMSAIRecognitionResult) {'''
)

path.write_text(text, encoding="utf-8")
print("Prepared stable SMS realtime/AI patch anchors and strict Theos regex escaping.")
