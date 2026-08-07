from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:220]!r}")
    write(path, text.replace(old, new, 1))


replace_once("project.yml", 'MARKETING_VERSION: "1.3.53"', 'MARKETING_VERSION: "1.3.54"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "61"', 'CURRENT_PROJECT_VERSION: "62"')

settings = "DailyLedger/Views/SettingsView.swift"

replace_once(
    settings,
    '''    @State private var openAIAPIKey = ""\n    @State private var openAIConnected = OpenAIService.shared.hasAPIKey\n    @State private var testingOpenAI = false\n''',
    '''    @State private var openAIAPIKey = ""\n    @State private var openAIConnected = OpenAIService.shared.hasAPIKey\n    @State private var testingOpenAI = false\n    @State private var showOpenAIKey = false\n    @FocusState private var openAIKeyFocused: Bool\n''',
)

old = '''                    SecureField(openAIConnected ? "Enter replacement API key" : "OpenAI API key", text: $openAIAPIKey)\n                        .textInputAutocapitalization(.never).autocorrectionDisabled()\n'''
new = '''                    VStack(alignment: .leading, spacing: 8) {\n                        HStack(spacing: 8) {\n                            Group {\n                                if showOpenAIKey {\n                                    TextField(openAIConnected ? "Enter replacement API key" : "OpenAI API key", text: $openAIAPIKey)\n                                } else {\n                                    SecureField(openAIConnected ? "Enter replacement API key" : "OpenAI API key", text: $openAIAPIKey)\n                                }\n                            }\n                            .focused($openAIKeyFocused)\n                            .textInputAutocapitalization(.never)\n                            .autocorrectionDisabled()\n                            .keyboardType(.asciiCapable)\n                            .textContentType(.password)\n                            .submitLabel(.done)\n                            .onSubmit { openAIKeyFocused = false }\n\n                            Button {\n                                showOpenAIKey.toggle()\n                                openAIKeyFocused = true\n                            } label: {\n                                Image(systemName: showOpenAIKey ? "eye.slash" : "eye")\n                            }\n                            .buttonStyle(.plain)\n                            .accessibilityLabel(showOpenAIKey ? "Hide API key" : "Show API key")\n                        }\n\n                        HStack(spacing: 12) {\n                            Button {\n                                if let value = UIPasteboard.general.string {\n                                    openAIAPIKey = value.trimmingCharacters(in: .whitespacesAndNewlines)\n                                    openAIKeyFocused = true\n                                } else {\n                                    notice = SettingsNotice(title: "Clipboard Empty", message: "Copy your OpenAI API key first, then tap Paste.")\n                                }\n                            } label: {\n                                Label("Paste", systemImage: "doc.on.clipboard")\n                            }\n                            .buttonStyle(.bordered)\n\n                            Button {\n                                openAIKeyFocused = true\n                            } label: {\n                                Label("Tap to Edit", systemImage: "keyboard")\n                            }\n                            .buttonStyle(.bordered)\n\n                            if !openAIAPIKey.isEmpty {\n                                Button(role: .destructive) {\n                                    openAIAPIKey = ""\n                                    openAIKeyFocused = true\n                                } label: {\n                                    Label("Clear", systemImage: "xmark.circle")\n                                }\n                                .buttonStyle(.bordered)\n                            }\n                        }\n                        .font(.caption)\n\n                        if openAIConnected {\n                            Text("A saved OpenAI API key is available to SMS AI recovery. Paste a new key only if you want to replace it.")\n                                .font(.caption)\n                                .foregroundStyle(.secondary)\n                        } else {\n                            Text("Tap the field or Tap to Edit to open the keyboard. You can also copy your key and use Paste.")\n                                .font(.caption)\n                                .foregroundStyle(.secondary)\n                        }\n                    }\n'''
replace_once(settings, old, new)

replace_once(
    settings,
    '''            .onAppear {\n                selectedCurrency = store.currencyCode\n            }\n''',
    '''            .onAppear {\n                selectedCurrency = store.currencyCode\n                openAIConnected = OpenAIService.shared.hasAPIKey\n            }\n''',
)

replace_once(
    settings,
    '''            try OpenAIService.shared.saveAPIKey(openAIAPIKey)\n            openAIAPIKey = ""\n            openAIConnected = true\n            notice = SettingsNotice(title: "OpenAI Connected", message: "The API key was saved securely in this iPhone's Keychain.")\n''',
    '''            try OpenAIService.shared.saveAPIKey(openAIAPIKey)\n            openAIAPIKey = ""\n            openAIKeyFocused = false\n            openAIConnected = OpenAIService.shared.hasAPIKey\n            notice = SettingsNotice(title: "OpenAI Connected", message: "The API key was saved securely in this iPhone's Keychain and is ready for SMS AI recovery.")\n''',
)

replace_once(
    settings,
    '''                    LabeledContent("Version", value: "1.3.41")\n''',
    '''                    LabeledContent("Version", value: "1.3.54")\n''',
)

print("Prepared Next Ledger 1.3.54 OpenAI API key keyboard, paste, reveal and clear controls.")

# Build trigger: API key entry fix.
