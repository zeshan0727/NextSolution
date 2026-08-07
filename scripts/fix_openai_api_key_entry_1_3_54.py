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
        raise RuntimeError(f"Expected one match in {path}: {old[:120]!r}")
    write(path, text.replace(old, new, 1))

replace_once("project.yml", 'MARKETING_VERSION: "1.3.53"', 'MARKETING_VERSION: "1.3.54"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "61"', 'CURRENT_PROJECT_VERSION: "62"')
settings = "DailyLedger/Views/SettingsView.swift"

# Keep only the API-key string/connection state in the already-large SettingsView.
# Focus/reveal/clipboard UI state lives in a separate child View so Swift does not
# need to type-check it as part of the giant Settings body expression.
text = read(settings)
pattern = r'(?ms)^\s*[^\n]*\$openAIAPIKey[^\n]*\n(?:\s*\.[^\n]*\n){0,8}'
text, count = re.subn(
    pattern,
    '                    OpenAIAPIKeyEntryView(apiKey: $openAIAPIKey, connected: openAIConnected)\n',
    text,
    count=1,
)
if count != 1:
    for line in text.splitlines():
        if "openAIAPIKey" in line:
            print("OPENAI-LINE:", line)
    raise RuntimeError(f"Expected one generated OpenAI API key binding, replaced {count}")

text = text.replace('''            .onAppear {
                selectedCurrency = store.currencyCode
            }
''','''            .onAppear {
                selectedCurrency = store.currencyCode
                openAIConnected = OpenAIService.shared.hasAPIKey
            }
''',1)
text = text.replace('''            try OpenAIService.shared.saveAPIKey(openAIAPIKey)
            openAIAPIKey = ""
            openAIConnected = true
''','''            try OpenAIService.shared.saveAPIKey(openAIAPIKey)
            openAIAPIKey = ""
            openAIConnected = OpenAIService.shared.hasAPIKey
''',1)
text = re.sub(r'LabeledContent\("Version", value: "[^"]+"\)', 'LabeledContent("Version", value: "1.3.54")', text, count=1)

child_marker = 'private struct ImportDocumentPicker: UIViewControllerRepresentable {'
child = r'''private struct OpenAIAPIKeyEntryView: View {
    @Binding var apiKey: String
    let connected: Bool

    @State private var showOpenAIKey = false
    @State private var pasteStatus = ""
    @FocusState private var openAIKeyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if showOpenAIKey {
                    TextField(connected ? "Enter replacement API key" : "OpenAI API key", text: $apiKey)
                        .focused($openAIKeyFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit { openAIKeyFocused = false }
                } else {
                    SecureField(connected ? "Enter replacement API key" : "OpenAI API key", text: $apiKey)
                        .focused($openAIKeyFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit { openAIKeyFocused = false }
                }

                Button {
                    showOpenAIKey.toggle()
                    openAIKeyFocused = true
                } label: {
                    Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showOpenAIKey ? "Hide API key" : "Show API key")
            }

            HStack(spacing: 10) {
                Button {
                    if let value = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !value.isEmpty {
                        apiKey = value
                        pasteStatus = "API key pasted. Tap Save OpenAI API Key below."
                        openAIKeyFocused = true
                    } else {
                        pasteStatus = "Clipboard is empty. Copy the OpenAI API key first."
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)

                Button {
                    openAIKeyFocused = true
                } label: {
                    Label("Tap to Edit", systemImage: "keyboard")
                }
                .buttonStyle(.bordered)

                if !apiKey.isEmpty {
                    Button(role: .destructive) {
                        apiKey = ""
                        pasteStatus = ""
                        openAIKeyFocused = true
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.caption)

            Text(pasteStatus.isEmpty
                 ? (connected
                    ? "OpenAI key saved. Paste a new key only to replace it."
                    : "Tap the field or Tap to Edit for the keyboard, or copy the key and tap Paste.")
                 : pasteStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

'''
if child_marker not in text:
    raise RuntimeError("ImportDocumentPicker marker not found")
text = text.replace(child_marker, child + child_marker, 1)
write(settings, text)
print("Prepared Next Ledger 1.3.54 standalone API-key editor with keyboard, paste, reveal, clear and saved-key status.")
