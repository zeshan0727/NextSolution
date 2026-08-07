from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

def write(path, text):
    (ROOT / path).write_text(text, encoding="utf-8")

def replace_once(path, old, new):
    text = read(path)
    if text.count(old) != 1:
        raise RuntimeError(f"Expected one match in {path}: {old[:180]!r}")
    write(path, text.replace(old, new, 1))

# App-only release. SMS database daemon stays 2.2.0.
replace_once("project.yml", 'MARKETING_VERSION: "1.3.55"', 'MARKETING_VERSION: "1.3.56"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "63"', 'CURRENT_PROJECT_VERSION: "64"')

# SMS recognition must use the OpenAI API already saved by the main AI Settings.
ai = "DailyLedger/Services/SMSAIRecognitionService.swift"
replace_once(ai,
'''    static var isAvailable: Bool {
        OpenAIService.shared.hasAPIKey || DeepSeekService.shared.hasAPIKey
    }
''',
'''    static var isAvailable: Bool {
        // SMS database recovery intentionally uses the existing OpenAI credential
        // from the main AI Settings. There is no separate SMS API key.
        OpenAIService.shared.hasAPIKey
    }
''')

# Append one serialized app-level queue worker. It only contacts OpenAI when the
# daemon has unresolved candidates, and each candidate is removed/marked processed
# after a successful recovery so it cannot loop.
ai_text = read(ai)
coordinator = r'''

actor SMSOpenAIAutoRecoveryCoordinator {
    static let shared = SMSOpenAIAutoRecoveryCoordinator()

    private var processing = false
    private(set) var lastProcessedCount = 0

    func processPending(limit: Int = 20) async {
        guard !processing else { return }
        guard OpenAIService.shared.hasAPIKey else { return }

        let candidates = SMSImportConsoleService.loadAICandidates()
        guard !candidates.isEmpty else { return }

        processing = true
        defer { processing = false }

        var completed = 0
        for candidate in candidates.prefix(limit) {
            do {
                let result = try await SMSAIRecognitionService.analyze(candidate: candidate)
                try SMSImportConsoleService.applyAIRecovery(result, to: candidate)
                completed += 1
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "SMSOpenAILastSuccessAtV1")
                UserDefaults.standard.set(result.transactionType, forKey: "SMSOpenAILastResultTypeV1")
                UserDefaults.standard.removeObject(forKey: "SMSOpenAILastErrorV1")
            } catch {
                // Keep the candidate queued for a later retry. Do not mark it
                // processed on API/network/JSON failure.
                UserDefaults.standard.set(String(describing: error), forKey: "SMSOpenAILastErrorV1")
                break
            }
        }
        lastProcessedCount = completed
    }
}
'''
if "actor SMSOpenAIAutoRecoveryCoordinator" not in ai_text:
    write(ai, ai_text.rstrip() + coordinator + "\n")

# Remove the old separate enable gate from the SMS console. The existing OpenAI
# connection becomes the single source of truth.
view = "DailyLedger/Views/SMSImportConsoleView.swift"
text = read(view)
text = text.replace(
    'Toggle("AI Recognition for Unrecognized SMS", isOn: $aiRecognitionEnabled)',
    'LabeledContent("AI Recognition", value: OpenAIService.shared.hasAPIKey ? "Automatic · OpenAI" : "OpenAI API required")',
    1,
)
text = text.replace(
    'Text("When enabled, only SMS that the local parser cannot classify confidently is sent to your configured OpenAI or DeepSeek account. AI results remain review suggestions; they are not blindly recorded.")',
    'Text("Uses the OpenAI API key already saved in Settings → AI. Unresolved approved-bank SMS are sent automatically to OpenAI and returned as editable Drafts for your review. No separate SMS API key is required.")',
    1,
)
text = text.replace(
    'guard aiRecognitionEnabled, !aiProcessing, SMSAIRecognitionService.isAvailable else { return }',
    'guard OpenAIService.shared.hasAPIKey, !aiProcessing, SMSAIRecognitionService.isAvailable else { return }',
    1,
)
write(view, text)

# App lifecycle: poll unresolved DB queue while Next Ledger is open. This makes
# database -> OpenAI -> Draft recovery real-time without needing the SMS console.
app = "DailyLedger/DailyLedgerApp.swift"
replace_once(app,
'''                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .onChange(of: scenePhase) { phase in
''',
'''                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .task {
                    // iOS suspends this task while the app is backgrounded. While
                    // active, pick up newly queued unresolved bank SMS within seconds.
                    while !Task.isCancelled {
                        await SMSOpenAIAutoRecoveryCoordinator.shared.processPending()
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                    }
                }
                .onChange(of: scenePhase) { phase in
''')
replace_once(app,
'''                    if phase == .active {
                        store.reload()
''',
'''                    if phase == .active {
                        store.reload()
                        Task {
                            await SMSOpenAIAutoRecoveryCoordinator.shared.processPending()
                        }
''')

# Visible version label.
settings = "DailyLedger/Views/SettingsView.swift"
settings_text = read(settings)
settings_text = re.sub(r'LabeledContent\("Version", value: "[^"]+"\)', 'LabeledContent("Version", value: "1.3.56")', settings_text, count=1)
write(settings, settings_text)

print("Prepared Next Ledger 1.3.56: existing Settings OpenAI key is auto-used for realtime Messages DB -> OpenAI -> editable Draft recovery.")
