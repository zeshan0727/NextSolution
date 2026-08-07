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
replace_once(settings,
'''    @State private var openAIAPIKey = ""
    @State private var openAIConnected = OpenAIService.shared.hasAPIKey
    @State private var testingOpenAI = false
''',
'''    @State private var openAIAPIKey = ""
    @State private var openAIConnected = OpenAIService.shared.hasAPIKey
    @State private var testingOpenAI = false
    @State private var showOpenAIKey = false
    @FocusState private var openAIKeyFocused: Bool
''')

replacement = '''                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Group {
                                if showOpenAIKey {
                                    TextField(openAIConnected ? "Enter replacement API key" : "OpenAI API key", text: $openAIAPIKey)
                                } else {
                                    SecureField(openAIConnected ? "Enter replacement API key" : "OpenAI API key", text: $openAIAPIKey)
                                }
                            }
                            .focused($openAIKeyFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .textContentType(.password)
                            .submitLabel(.done)
                            .onSubmit { openAIKeyFocused = false }
                            Button { showOpenAIKey.toggle(); openAIKeyFocused = true } label: {
                                Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.plain)
                        }
                        HStack(spacing: 10) {
                            Button {
                                if let value = UIPasteboard.general.string, !value.isEmpty {
                                    openAIAPIKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                    openAIKeyFocused = true
                                } else {
                                    notice = SettingsNotice(title: "Clipboard Empty", message: "Copy your OpenAI API key first, then tap Paste.")
                                }
                            } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                            .buttonStyle(.bordered)
                            Button { openAIKeyFocused = true } label: { Label("Tap to Edit", systemImage: "keyboard") }
                            .buttonStyle(.bordered)
                            if !openAIAPIKey.isEmpty {
                                Button(role: .destructive) { openAIAPIKey = ""; openAIKeyFocused = true } label: {
                                    Label("Clear", systemImage: "xmark.circle")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .font(.caption)
                        Text(openAIConnected ? "OpenAI key saved. Paste a new key only to replace it." : "Tap the field or Tap to Edit for the keyboard, or copy the key and tap Paste.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
'''
text = read(settings)
pattern = r'(?ms)^\s*[^\n]*\$openAIAPIKey[^\n]*\n(?:\s*\.[^\n]*\n){0,8}'
text, count = re.subn(pattern, replacement, text, count=1)
if count != 1:
    for line in text.splitlines():
        if "openAIAPIKey" in line:
            print("OPENAI-LINE:", line)
    raise RuntimeError(f"Expected one generated OpenAI API key binding, replaced {count}")
write(settings, text)

text = read(settings)
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
            openAIKeyFocused = false
            openAIConnected = OpenAIService.shared.hasAPIKey
''',1)
text = re.sub(r'LabeledContent\("Version", value: "[^"]+"\)', 'LabeledContent("Version", value: "1.3.54")', text, count=1)
write(settings, text)
print("Prepared Next Ledger 1.3.54 API-key keyboard, paste, reveal, clear and saved-key status controls.")
