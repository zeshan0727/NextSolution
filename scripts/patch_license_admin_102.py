from pathlib import Path
import re

path = Path('NextSolutionLicenseAdmin/Sources/NextSolutionLicenseAdminApp.swift')
text = path.read_text()

new_store = r'''struct TokenSaveResult {
    let success: Bool
    let backend: String
    let detail: String
}

struct LicenseTokenStore {
    private static let service = "com.nextsolution.licenseadmin.github"
    private static let account = "github-pat"
    private static let fallbackDirectory = "NSAdmin"
    private static let fallbackFile = "github-token.dat"

    private static var fallbackURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base
            .appendingPathComponent(fallbackDirectory, isDirectory: true)
            .appendingPathComponent(fallbackFile, isDirectory: false)
    }

    private static func keychainQuery(returnData: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if returnData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }

    private static func keychainLoad() -> (String?, OSStatus) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(keychainQuery(returnData: true) as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return (nil, status) }
        return (value, status)
    }

    private static func fallbackLoad() -> String? {
        guard let url = fallbackURL,
              let data = try? Data(contentsOf: url),
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    static func load() -> String {
        if let value = keychainLoad().0 { return value }
        return fallbackLoad() ?? ""
    }

    static func storageBackend() -> String {
        if keychainLoad().0 != nil { return "iOS Keychain" }
        if fallbackLoad() != nil { return "Protected App Storage" }
        return "None"
    }

    private static func errorText(_ status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(message) (\(status))"
        }
        return "OSStatus \(status)"
    }

    private static func saveFallback(_ data: Data) throws {
        guard let url = fallbackURL else {
            throw NSError(
                domain: "NSAdmin",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Application Support directory is unavailable."]
            )
        }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
            .posixPermissions: 0o600
        ], ofItemAtPath: url.path)
    }

    private static func deleteFallback() {
        guard let url = fallbackURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    static func save(_ token: String) -> TokenSaveResult {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            _ = delete()
            return TokenSaveResult(success: true, backend: "None", detail: "Token removed.")
        }
        guard let data = value.data(using: .utf8) else {
            return TokenSaveResult(success: false, backend: "None", detail: "Token encoding failed.")
        }

        let key = keychainQuery()
        let update = SecItemUpdate(
            key as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if update == errSecSuccess {
            deleteFallback()
            return TokenSaveResult(success: true, backend: "iOS Keychain", detail: "")
        }

        var keychainFailure = update
        if update == errSecItemNotFound {
            var create = key
            create[kSecValueData as String] = data
            create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let add = SecItemAdd(create as CFDictionary, nil)
            if add == errSecSuccess {
                deleteFallback()
                return TokenSaveResult(success: true, backend: "iOS Keychain", detail: "")
            }
            keychainFailure = add
        }

        do {
            try saveFallback(data)
            return TokenSaveResult(
                success: true,
                backend: "Protected App Storage",
                detail: "Keychain is unavailable for this TrollStore signature (\(errorText(keychainFailure))). The token is stored inside NS Admin's private sandbox with iOS Data Protection."
            )
        } catch {
            return TokenSaveResult(
                success: false,
                backend: "None",
                detail: "Keychain failed: \(errorText(keychainFailure)). Protected storage also failed: \(error.localizedDescription)"
            )
        }
    }

    @discardableResult
    static func delete() -> Bool {
        _ = SecItemDelete(keychainQuery() as CFDictionary)
        deleteFallback()
        return true
    }
}'''

pattern = r'struct LicenseTokenStore \{.*?\n\}\n\nstruct GitHubLicenseAPI'
replacement = new_store + '\n\nstruct GitHubLicenseAPI'
text, count = re.subn(pattern, replacement, text, flags=re.S)
if count != 1:
    raise SystemExit(f'LicenseTokenStore replacement count was {count}, expected 1')

save_pattern = r'''    func saveToken\(\) \{.*?\n    \}\n\n    func clearToken\(\) \{'''
save_replacement = r'''    func saveToken() {
        let result = LicenseTokenStore.save(tokenDraft)
        if result.success {
            tokenDraft = LicenseTokenStore.load()
            if tokenDraft.isEmpty {
                settingsStatus = "Token removed."
            } else if result.detail.isEmpty {
                settingsStatus = "Token saved securely in \(result.backend)."
            } else {
                settingsStatus = "Token saved in \(result.backend). \(result.detail)"
            }
        } else {
            settingsStatus = result.detail
        }
    }

    func clearToken() {'''
text, count = re.subn(save_pattern, save_replacement, text, flags=re.S)
if count != 1:
    raise SystemExit(f'saveToken replacement count was {count}, expected 1')

text = text.replace('NextSolutionLicenseAdmin/1.0.0', 'NSAdmin/1.0.2')
text = text.replace('Button("Save Token to Keychain") { model.saveToken() }', 'Button("Save GitHub Token") { model.saveToken() }')
text = text.replace(
    'Use a fine-grained GitHub personal access token restricted to zeshan0727/NextJailbreak with Repository contents: Read and write. The token is stored only in iOS Keychain.',
    'Use a fine-grained GitHub personal access token restricted to zeshan0727/NextJailbreak with Repository contents: Read and write. NS Admin uses iOS Keychain when available; TrollStore signatures without Keychain access automatically use the app private sandbox with iOS Data Protection.'
)
text = text.replace('LabeledContent("App", value: "NextSolution License Admin")', 'LabeledContent("App", value: "NS Admin")')
text = text.replace('LabeledContent("Version", value: "1.0.0")', 'LabeledContent("Version", value: "1.0.2")')

# Make the storage method visible in Settings without exposing the token.
status_anchor = '''                if !model.settingsStatus.isEmpty {
                    Section("Status") {
                        Text(model.settingsStatus)
                    }
                }
'''
status_replacement = '''                if !model.settingsStatus.isEmpty {
                    Section("Status") {
                        Text(model.settingsStatus)
                        LabeledContent("Stored in", value: LicenseTokenStore.storageBackend())
                    }
                }
'''
if status_anchor not in text:
    raise SystemExit('Settings status anchor not found')
text = text.replace(status_anchor, status_replacement, 1)

path.write_text(text)
print('Patched NS Admin source for 1.0.2')
