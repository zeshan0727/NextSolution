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
        raise RuntimeError(f"Expected one match in {path}, found {text.count(old)}: {old[:220]!r}")
    write(path, text.replace(old, new, 1))

# App-only release; daemon remains 2.2.0.
replace_once("project.yml", 'MARKETING_VERSION: "1.3.57"', 'MARKETING_VERSION: "1.3.58"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "65"', 'CURRENT_PROJECT_VERSION: "66"')

# ---------------------------------------------------------------------------
# Replace the permanent/repeating AI worker with a finite, retry-limited worker.
# One invocation handles a bounded batch and then stops. Failed candidates use
# cooldown + max 3 automatic attempts; they never spin continuously.
# ---------------------------------------------------------------------------
ai = "DailyLedger/Services/SMSAIRecognitionService.swift"
text = read(ai)
pattern = r'actor SMSOpenAIAutoRecoveryCoordinator \{.*?\n\}\s*$'
replacement = r'''actor SMSOpenAIAutoRecoveryCoordinator {
    static let shared = SMSOpenAIAutoRecoveryCoordinator()

    private var processing = false
    private let statusKey = "SMSOpenAIWorkerStatusV2"
    private let lastErrorKey = "SMSOpenAILastErrorV1"
    private let retryPrefix = "SMSOpenAIRetryCountV2."
    private let nextRetryPrefix = "SMSOpenAINextRetryV2."
    private let blockedPrefix = "SMSOpenAIBlockedV2."

    func processPending(force: Bool = false, limit: Int = 5) async {
        guard !processing else { return }
        guard OpenAIService.shared.hasAPIKey else {
            setStatus("OpenAI API not connected")
            return
        }

        let allCandidates = SMSImportConsoleService.loadAICandidates()
        guard !allCandidates.isEmpty else {
            setStatus("Idle · No unresolved SMS")
            return
        }

        let now = Date().timeIntervalSince1970
        let candidates = allCandidates.filter { candidate in
            if force { return true }
            let id = candidate.id.uuidString
            if UserDefaults.standard.bool(forKey: blockedPrefix + id) { return false }
            let next = UserDefaults.standard.double(forKey: nextRetryPrefix + id)
            return next <= 0 || next <= now
        }

        guard !candidates.isEmpty else {
            setStatus("Paused · Waiting for retry or manual Retry AI Recovery")
            return
        }

        processing = true
        defer { processing = false }

        var completed = 0
        let batch = Array(candidates.prefix(max(1, min(limit, 5))))
        setStatus("Analyzing \(batch.count) unresolved SMS…")

        for candidate in batch {
            let id = candidate.id.uuidString
            do {
                let result = try await SMSAIRecognitionService.analyze(candidate: candidate)
                try SMSImportConsoleService.applyAIRecovery(result, to: candidate)
                completed += 1

                UserDefaults.standard.removeObject(forKey: retryPrefix + id)
                UserDefaults.standard.removeObject(forKey: nextRetryPrefix + id)
                UserDefaults.standard.removeObject(forKey: blockedPrefix + id)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "SMSOpenAILastSuccessAtV1")
                UserDefaults.standard.set(result.transactionType, forKey: "SMSOpenAILastResultTypeV1")
                UserDefaults.standard.removeObject(forKey: lastErrorKey)
            } catch {
                let retryKey = retryPrefix + id
                let attempts = UserDefaults.standard.integer(forKey: retryKey) + 1
                UserDefaults.standard.set(attempts, forKey: retryKey)
                UserDefaults.standard.set(error.localizedDescription, forKey: lastErrorKey)

                if attempts >= 3 {
                    UserDefaults.standard.set(true, forKey: blockedPrefix + id)
                    UserDefaults.standard.removeObject(forKey: nextRetryPrefix + id)
                    setStatus("Paused · AI failed 3 times. Tap Retry AI Recovery.")
                } else {
                    let delay: TimeInterval = attempts == 1 ? 60 : 300
                    UserDefaults.standard.set(Date().addingTimeInterval(delay).timeIntervalSince1970,
                                                      forKey: nextRetryPrefix + id)
                    setStatus("AI error · Stopped. Retry available later or tap Retry AI Recovery.")
                }
                return
            }
        }

        let remaining = SMSImportConsoleService.loadAICandidates().count
        if remaining == 0 {
            setStatus(completed > 0 ? "Finished · Recovered \(completed) SMS" : "Idle · No unresolved SMS")
        } else {
            setStatus("Finished batch · \(completed) recovered · \(remaining) waiting")
        }
    }

    func retryPending() async {
        let candidates = SMSImportConsoleService.loadAICandidates()
        for candidate in candidates {
            let id = candidate.id.uuidString
            UserDefaults.standard.removeObject(forKey: retryPrefix + id)
            UserDefaults.standard.removeObject(forKey: nextRetryPrefix + id)
            UserDefaults.standard.removeObject(forKey: blockedPrefix + id)
        }
        UserDefaults.standard.removeObject(forKey: lastErrorKey)
        setStatus(candidates.isEmpty ? "Idle · No unresolved SMS" : "Manual retry started…")
        await processPending(force: true)
    }

    private func setStatus(_ value: String) {
        UserDefaults.standard.set(value, forKey: statusKey)
    }
}
'''
text, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
if count != 1:
    raise RuntimeError(f"Expected one SMSOpenAIAutoRecoveryCoordinator actor, replaced {count}")
write(ai, text)

# ---------------------------------------------------------------------------
# App lifecycle: remove the endless 5-second while loop. Run one finite recovery
# pass on initial root-view task and one finite pass each time the app becomes active.
# ---------------------------------------------------------------------------
app = "DailyLedger/DailyLedgerApp.swift"
old_task = '''                .task {
                    // iOS suspends this task while the app is backgrounded. While
                    // active, pick up newly queued unresolved bank SMS within seconds.
                    while !Task.isCancelled {
                        await SMSOpenAIAutoRecoveryCoordinator.shared.processPending()
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                    }
                }
'''
new_task = '''                .task {
                    // One bounded pass only. No permanent AI polling loop.
                    await SMSOpenAIAutoRecoveryCoordinator.shared.processPending()
                }
'''
replace_once(app, old_task, new_task)

# ---------------------------------------------------------------------------
# SMS Console: stop starting a second AI worker every 0.35s refresh. The console
# becomes status + explicit retry only. It still refreshes scan/queue counters.
# ---------------------------------------------------------------------------
view = "DailyLedger/Views/SMSImportConsoleView.swift"
text = read(view)
call = "        startAIRecognitionIfNeeded()\n"
if text.count(call) != 1:
    raise RuntimeError(f"Expected one console auto-AI call, found {text.count(call)}")
text = text.replace(call, "", 1)

status_line = '                LabeledContent("AI Recognition", value: OpenAIService.shared.hasAPIKey ? "Automatic · OpenAI" : "OpenAI API required")\n'
if status_line not in text:
    raise RuntimeError("AI Recognition status line not found")
status_block = '''                LabeledContent("AI Recognition", value: OpenAIService.shared.hasAPIKey ? "OpenAI Connected" : "OpenAI API required")
                LabeledContent(
                    "AI Recovery Status",
                    value: UserDefaults.standard.string(forKey: "SMSOpenAIWorkerStatusV2") ?? "Idle"
                )
                LabeledContent("Unresolved AI Queue", value: "\(SMSImportConsoleService.loadAICandidates().count)")

                Button {
                    Task {
                        await SMSOpenAIAutoRecoveryCoordinator.shared.retryPending()
                        await MainActor.run { refresh() }
                    }
                } label: {
                    Label("Retry AI Recovery", systemImage: "arrow.clockwise.circle.fill")
                }
                .disabled(!OpenAIService.shared.hasAPIKey || SMSImportConsoleService.loadAICandidates().isEmpty)
'''
text = text.replace(status_line, status_block, 1)
write(view, text)

# Visible version label.
settings = "DailyLedger/Views/SettingsView.swift"
settings_text = read(settings)
settings_text = re.sub(r'LabeledContent\("Version", value: "[^"]+"\)', 'LabeledContent("Version", value: "1.3.58")', settings_text, count=1)
write(settings, settings_text)

print("Prepared Next Ledger 1.3.58: removed endless/duplicate AI loops, added bounded recovery, retry backoff, max-attempt pause and explicit Retry AI Recovery.")
