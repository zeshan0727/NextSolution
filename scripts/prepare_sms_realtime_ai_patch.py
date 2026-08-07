from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "scripts/add_sms_realtime_progress_ai_1_3_51.py"
text = path.read_text(encoding="utf-8")

# Add a first-match helper for anchors that intentionally occur in both the main
# console and nested log views.
if "def replace_first(path: str, old: str, new: str)" not in text:
    anchor = '''def regex_replace_once(path: str, pattern: str, replacement: str) -> None:\n'''
    helper = '''def replace_first(path: str, old: str, new: str) -> None:\n    content = read(path)\n    if old not in content:\n        raise RuntimeError(f"Expected at least one match in {path}: {old[:220]!r}")\n    write(path, content.replace(old, new, 1))\n\n\n'''
    if anchor not in text:
        raise RuntimeError("Could not locate realtime-patch helper insertion anchor")
    text = text.replace(anchor, helper + anchor, 1)

old_call = '''replace_once(\n    view,\n    ''' + "'''" + '''    @State private var notice: String?\\n''' + "'''" + ''',\n    ''' + "'''" + '''    @AppStorage("SMSAIRecognitionEnabledV1") private var aiRecognitionEnabled = false\n    @State private var localManualScan = false\n    @State private var manualScanRequestedAt: Date?\n    @State private var aiProcessing = false\n    @State private var aiProcessedCount = 0\n    @State private var notice: String?\n''' + "'''" + ''',\n)\n'''
new_call = old_call.replace("replace_once(\n    view,", "replace_first(\n    view,", 1)
if old_call in text:
    text = text.replace(old_call, new_call, 1)
elif new_call not in text:
    raise RuntimeError("Could not locate ambiguous SMS console notice-state patch")

# Keep Swift actor inference simple for iOS 16 / Swift 5.7 compatibility. These
# methods are invoked from SwiftUI view tasks and update local @State.
text = text.replace(
    '''    @MainActor\n    private func analyzeWithAI(force: Bool) async {''',
    '''    private func analyzeWithAI(force: Bool) async {'''
)
text = text.replace(
    '''    @MainActor\n    private func applyAIRecognition(_ result: SMSAIRecognitionResult) {''',
    '''    private func applyAIRecognition(_ result: SMSAIRecognitionResult) {'''
)

path.write_text(text, encoding="utf-8")
print("Prepared stable first-match anchors and Swift 5.7 AI review helpers.")
