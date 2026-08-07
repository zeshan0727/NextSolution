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

replace_once("project.yml", 'MARKETING_VERSION: "1.3.54"', 'MARKETING_VERSION: "1.3.55"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "62"', 'CURRENT_PROJECT_VERSION: "63"')
settings = "DailyLedger/Views/SettingsView.swift"
text = read(settings)
start = text.find('private struct OpenAIAPIKeyEntryView: View {')
end = text.find('private struct ImportDocumentPicker: UIViewControllerRepresentable {', start)
if start < 0 or end < 0:
    raise RuntimeError("OpenAIAPIKeyEntryView / ImportDocumentPicker markers not found")

replacement = r'''private struct OpenAIAPIKeyEntryView: View {
    @Binding var apiKey: String
    let connected: Bool

    @State private var reveal = false
    @State private var pasteStatus = ""
    @State private var focusRequest = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            UIKitAPIKeyTextField(
                text: $apiKey,
                placeholder: connected ? "Enter replacement API key" : "OpenAI API key",
                isSecure: !reveal,
                focusRequest: focusRequest
            )
            .frame(height: 44)

            HStack(spacing: 10) {
                Button {
                    if let value = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !value.isEmpty {
                        apiKey = value
                        pasteStatus = "API key pasted. Tap Save OpenAI API Key below."
                        focusRequest += 1
                    } else {
                        pasteStatus = "Clipboard is empty. Copy your OpenAI API key first."
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)

                Button {
                    focusRequest += 1
                } label: {
                    Label("Tap to Edit", systemImage: "keyboard")
                }
                .buttonStyle(.bordered)

                Button {
                    reveal.toggle()
                    focusRequest += 1
                } label: {
                    Label(reveal ? "Hide" : "Show", systemImage: reveal ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)

                if !apiKey.isEmpty {
                    Button(role: .destructive) {
                        apiKey = ""
                        pasteStatus = ""
                        focusRequest += 1
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.caption)

            Text(pasteStatus.isEmpty
                 ? (connected
                    ? "OpenAI key saved. Tap the field to replace it, or use Paste."
                    : "Tap directly inside the field for the keyboard, or use Paste from clipboard.")
                 : pasteStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct UIKitAPIKeyTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isSecure: Bool
    let focusRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField(frame: .zero)
        field.borderStyle = .roundedRect
        field.placeholder = placeholder
        field.isSecureTextEntry = isSecure
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.keyboardType = .asciiCapable
        field.textContentType = .password
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        if field.text != text { field.text = text }
        field.placeholder = placeholder
        if field.isSecureTextEntry != isSecure {
            let wasFirstResponder = field.isFirstResponder
            field.isSecureTextEntry = isSecure
            if wasFirstResponder {
                field.becomeFirstResponder()
            }
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                field.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var lastFocusRequest = 0

        init(text: Binding<String>) {
            _text = text
        }

        @objc func changed(_ sender: UITextField) {
            text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

'''
text = text[:start] + replacement + text[end:]
text = re.sub(r'LabeledContent\("Version", value: "[^"]+"\)', 'LabeledContent("Version", value: "1.3.55")', text, count=1)
write(settings, text)
print("Prepared Next Ledger 1.3.55 native UIKit OpenAI API-key entry with reliable keyboard and paste support.")
