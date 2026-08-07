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
        raise RuntimeError(f"Expected one match in {path}: {old[:220]!r}")
    write(path, text.replace(old, new, 1))

# App-only release. SMS daemon remains 2.2.0.
replace_once("project.yml", 'MARKETING_VERSION: "1.3.56"', 'MARKETING_VERSION: "1.3.57"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "64"', 'CURRENT_PROJECT_VERSION: "65"')

# Make OpenAI credential persistence robust on TrollStore/rootless installs.
# Protected app storage is authoritative; Keychain is mirrored best-effort.
service = "DailyLedger/Services/OpenAIService.swift"
replace_once(service,
'''    func saveAPIKey(_ value: String) throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { deleteAPIKey(); return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service, kSecAttrAccount as String: Self.account]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw OpenAIServiceError.server("The OpenAI API key could not be saved securely.")
        }
        try? ProtectedSecretStore.shared.save(value, for: Self.service)
    }
''',
'''    func saveAPIKey(_ value: String) throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { deleteAPIKey(); return }

        // The protected app store is the reliable source of truth for TrollStore
        // and rootless installs. If Keychain entitlement behavior differs, the
        // OpenAI key still persists securely inside this device/app container.
        try ProtectedSecretStore.shared.save(value, for: Self.service)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        _ = SecItemAdd(item as CFDictionary, nil) // best-effort mirror

        guard loadAPIKey() == value else {
            throw OpenAIServiceError.server("The OpenAI API key could not be verified after saving.")
        }
    }
''')

settings = "DailyLedger/Views/SettingsView.swift"
text = read(settings)

# Add a visible save-status line so the user can see that Save actually ran.
state_anchor = '''    @State private var openAIConnected = OpenAIService.shared.hasAPIKey
    @State private var testingOpenAI = false
'''
if state_anchor in text:
    text = text.replace(state_anchor,
'''    @State private var openAIConnected = OpenAIService.shared.hasAPIKey
    @State private var testingOpenAI = false
    @State private var openAISaveStatus = ""
''', 1)
else:
    raise RuntimeError("OpenAI settings state anchor not found")

# Replace the generated save button with an explicit closure and visible status.
button_patterns = [
'''                                Button("Save OpenAI API Key", action: saveOpenAIKey)
                                    .disabled(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
''',
'''                    Button("Save OpenAI API Key", action: saveOpenAIKey)
                        .disabled(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
'''
]
button_replaced = False
for old in button_patterns:
    if old in text:
        indent = old.split('Button')[0]
        new = f'''{indent}Button {{
{indent}    saveOpenAIKey()
{indent}}} label: {{
{indent}    Label("Save OpenAI API Key", systemImage: "checkmark.circle.fill")
{indent}}}
{indent}.buttonStyle(.borderedProminent)
{indent}.disabled(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
{indent}if !openAISaveStatus.isEmpty {{
{indent}    Text(openAISaveStatus)
{indent}        .font(.caption)
{indent}        .foregroundStyle(openAIConnected ? AppTheme.green : AppTheme.red)
{indent}}}
'''
        text = text.replace(old, new, 1)
        button_replaced = True
        break
if not button_replaced:
    raise RuntimeError("Generated Save OpenAI button not found")

# Replace save action with verified persistence + immediate SMS AI queue kick.
old_func = '''    private func saveOpenAIKey() {
        do {
            try OpenAIService.shared.saveAPIKey(openAIAPIKey)
            openAIAPIKey = ""
            openAIConnected = OpenAIService.shared.hasAPIKey
            notice = SettingsNotice(title: "OpenAI Connected", message: "The API key was saved securely in this iPhone's Keychain.")
        } catch {
            notice = SettingsNotice(title: "Connection Failed", message: error.localizedDescription)
        }
    }
'''
if old_func not in text:
    # Older generated wording may set connected=true directly.
    old_func = '''    private func saveOpenAIKey() {
        do {
            try OpenAIService.shared.saveAPIKey(openAIAPIKey)
            openAIAPIKey = ""
            openAIConnected = true
            notice = SettingsNotice(title: "OpenAI Connected", message: "The API key was saved securely in this iPhone's Keychain.")
        } catch {
            notice = SettingsNotice(title: "Connection Failed", message: error.localizedDescription)
        }
    }
'''
if old_func not in text:
    raise RuntimeError("saveOpenAIKey function not found")

new_func = '''    private func saveOpenAIKey() {
        let value = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            openAIConnected = OpenAIService.shared.hasAPIKey
            openAISaveStatus = "Enter or paste an OpenAI API key first."
            return
        }

        do {
            try OpenAIService.shared.saveAPIKey(value)
            let verified = OpenAIService.shared.loadAPIKey() == value && OpenAIService.shared.hasAPIKey
            openAIConnected = verified
            if verified {
                openAIAPIKey = ""
                openAISaveStatus = "Saved & Connected · SMS AI will use this OpenAI key automatically."
                notice = SettingsNotice(
                    title: "OpenAI Connected",
                    message: "The API key was saved and verified. Automatic SMS database AI recovery is now linked to this same OpenAI connection."
                )
                Task {
                    await SMSOpenAIAutoRecoveryCoordinator.shared.processPending()
                }
            } else {
                openAISaveStatus = "Save failed verification."
                notice = SettingsNotice(title: "Save Failed", message: "Next Ledger could not read the OpenAI key back after saving.")
            }
        } catch {
            openAIConnected = OpenAIService.shared.hasAPIKey
            openAISaveStatus = "Save failed: \\(error.localizedDescription)"
            notice = SettingsNotice(title: "Connection Failed", message: error.localizedDescription)
        }
    }
'''
text = text.replace(old_func, new_func, 1)

# Refresh connected state whenever Settings appears and show already-saved status.
appear_old = '''            .onAppear {
                selectedCurrency = store.currencyCode
                openAIConnected = OpenAIService.shared.hasAPIKey
            }
'''
appear_new = '''            .onAppear {
                selectedCurrency = store.currencyCode
                openAIConnected = OpenAIService.shared.hasAPIKey
                if openAIConnected && openAISaveStatus.isEmpty {
                    openAISaveStatus = "Connected · SMS AI automatically uses this saved OpenAI key."
                }
            }
'''
if appear_old in text:
    text = text.replace(appear_old, appear_new, 1)
else:
    # Fallback for unmodified parent onAppear.
    appear_old2 = '''            .onAppear {
                selectedCurrency = store.currencyCode
            }
'''
    if appear_old2 in text:
        text = text.replace(appear_old2, appear_new, 1)
    else:
        raise RuntimeError("Settings onAppear anchor not found")

text = re.sub(r'LabeledContent\("Version", value: "[^"]+"\)', 'LabeledContent("Version", value: "1.3.57")', text, count=1)
write(settings, text)

print("Prepared Next Ledger 1.3.57: main OpenAI Save button is explicit, storage is TrollStore-safe, save is verified, and SMS AI auto-links to the same saved key.")
