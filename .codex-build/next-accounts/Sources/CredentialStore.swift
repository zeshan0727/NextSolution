import Foundation
import UIKit
import Combine

@MainActor
final class CredentialStore: ObservableObject {
    @Published private(set) var credentials: [Credential] = []
    @Published private(set) var statusMessage: String?

    private var statusTask: Task<Void, Never>?

    init() {
        loadCredentials()
    }

    func copy(_ value: String, label: String) {
        guard !value.isEmpty else {
            showStatus("Add an email first")
            return
        }
        UIPasteboard.general.string = value
        HapticManager.shared.copied()
        showStatus("\(label) copied")
    }

    func generateFive() {
        let existingEmails = Set(credentials.map { normalizedEmail($0.email) }.filter { !$0.isEmpty })
        credentials.append(contentsOf: makeGeneratedCredentials(count: 5, existingEmails: existingEmails))
        saveCredentials()
        HapticManager.shared.generated()
        showStatus("5 accounts generated")
    }

    func toggle(_ platform: AccountPlatform, for credentialID: UUID) {
        guard let index = credentials.firstIndex(where: { $0.id == credentialID }) else { return }

        var credential = credentials[index]
        if credential.activePlatforms.contains(platform) {
            credential.activePlatforms.remove(platform)
        } else {
            credential.activePlatforms.insert(platform)
        }
        credentials[index] = credential
        saveCredentials()
        HapticManager.shared.selectionChanged()
    }

    func deleteCredential(id: UUID) {
        guard let index = credentials.firstIndex(where: { $0.id == id }) else { return }
        credentials.remove(at: index)
        saveCredentials()
        HapticManager.shared.deleted()
        showStatus("Account deleted")
    }

    func updateCredential(id: UUID, email: String, password: String) {
        guard let index = credentials.firstIndex(where: { $0.id == id }) else { return }
        credentials[index].email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        credentials[index].password = password
        saveCredentials()
        HapticManager.shared.generated()
        showStatus("Account updated")
    }

    @discardableResult
    func importEmails(_ text: String) -> Int {
        let separators = CharacterSet(charactersIn: "\n,;")
        let candidates = text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { isValidEmail($0) }

        var known = Set(credentials.map { normalizedEmail($0.email) }.filter { !$0.isEmpty })
        var imported = 0

        for email in candidates where known.insert(normalizedEmail(email)).inserted {
            if let blankIndex = credentials.firstIndex(where: { $0.email.isEmpty }) {
                credentials[blankIndex].email = email
            } else {
                credentials.append(
                    Credential(
                        email: email,
                        password: makePassword(),
                        isGenerated: true
                    )
                )
            }
            imported += 1
        }

        guard imported > 0 else {
            showStatus("No new valid emails found")
            return 0
        }

        saveCredentials()
        HapticManager.shared.generated()
        showStatus("\(imported) email\(imported == 1 ? "" : "s") imported")
        return imported
    }

    func freshPassword() -> String {
        makePassword()
    }

    func freshEmail(excluding credentialID: UUID? = nil) -> String {
        let existingEmails = Set(
            credentials
                .filter { $0.id != credentialID }
                .map { normalizedEmail($0.email) }
                .filter { !$0.isEmpty }
        )
        return makeEmail(excluding: existingEmails)
    }

    private func loadCredentials() {
        let decoder = JSONDecoder()

        if let storedData = KeychainStore.load(),
           let stored = try? decoder.decode([Credential].self, from: storedData),
           !stored.isEmpty {
            credentials = stored
            return
        }

        if let previousData = KeychainStore.loadPrevious(),
           let previous = try? decoder.decode([Credential].self, from: previousData),
           !previous.isEmpty {
            credentials = fillingMissingGeneratedValues(in: previous)
            saveCredentials()
            KeychainStore.deletePrevious()
            return
        }

        if let legacyData = KeychainStore.loadLegacy(),
           let legacy = try? decoder.decode([Credential].self, from: legacyData),
           let first = legacy.first {
            let existingEmails = Set([normalizedEmail(first.email)].filter { !$0.isEmpty })
            credentials = [first] + makeGeneratedCredentials(count: 21, existingEmails: existingEmails)
            saveCredentials()
            KeychainStore.deleteLegacy()
            return
        }

        credentials = makeGeneratedCredentials(count: 22)
        saveCredentials()
    }

    private func saveCredentials() {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        KeychainStore.save(data)
    }

    private func makeGeneratedCredentials(
        count: Int,
        existingEmails: Set<String> = []
    ) -> [Credential] {
        var knownEmails = existingEmails
        var generated: [Credential] = []

        for style in 0..<count {
            let email = makeEmail(excluding: knownEmails, styleHint: style)
            knownEmails.insert(normalizedEmail(email))
            generated.append(
                Credential(
                    email: email,
                    password: makePassword(),
                    isGenerated: true
                )
            )
        }

        return generated
    }

    private func fillingMissingGeneratedValues(in stored: [Credential]) -> [Credential] {
        var migrated = stored
        var knownEmails = Set(stored.map { normalizedEmail($0.email) }.filter { !$0.isEmpty })

        for index in migrated.indices {
            if migrated[index].email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let email = makeEmail(excluding: knownEmails, styleHint: index)
                migrated[index].email = email
                knownEmails.insert(normalizedEmail(email))
            }

            if migrated[index].password.isEmpty {
                migrated[index].password = makePassword()
            }
        }

        return migrated
    }

    private func isValidEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[1].contains("."),
              !value.contains(" ") else {
            return false
        }
        return true
    }

    private func makePassword() -> String {
        let firstWords = [
            "Amber", "Blue", "Cedar", "Coral", "Fresh", "Golden",
            "Honey", "Mango", "Maple", "Quiet", "Ruby", "Silver"
        ]
        let secondWords = [
            "Bird", "Cove", "Dawn", "Falcon", "Hill", "Kite",
            "Lake", "Moon", "Orbit", "Palm", "Stone", "Wave"
        ]
        let symbols = ["@", "#", "!"]
        let first = firstWords.randomElement() ?? "Amber"
        let second = secondWords.randomElement() ?? "Moon"
        let symbol = symbols.randomElement() ?? "@"
        let digits = Int.random(in: 1000...9999)
        return "\(first)\(second)\(symbol)\(digits)"
    }

    private func makeEmail(excluding existingEmails: Set<String>, styleHint: Int? = nil) -> String {
        let firstWords = [
            "amber", "atlas", "cedar", "coral", "echo", "ember",
            "forest", "hazel", "indigo", "lunar", "maple", "meadow",
            "mint", "nova", "olive", "orbit", "pearl", "river",
            "silver", "solar", "swift", "urban", "violet", "willow"
        ]
        let secondWords = [
            "bird", "bloom", "cloud", "cove", "craft", "daily",
            "desk", "field", "fox", "garden", "harbor", "journal",
            "lane", "light", "nest", "notes", "page", "pixel",
            "point", "studio", "trail", "vault", "wave", "works"
        ]

        for attempt in 0..<100 {
            let first = firstWords.randomElement() ?? "amber"
            let second = secondWords.randomElement() ?? "wave"
            let twoDigits = Int.random(in: 10...99)
            let fourDigits = Int.random(in: 1000...9999)
            let baseStyle = styleHint ?? Int.random(in: 0...7)
            let style = (baseStyle + attempt) % 8

            let localPart: String
            switch style {
            case 0:
                localPart = "\(first)\(second)\(fourDigits)"
            case 1:
                localPart = "\(first)\(twoDigits)\(second)"
            case 2:
                localPart = "\(first.prefix(1))\(second)\(fourDigits)"
            case 3:
                localPart = "\(second)\(fourDigits)\(first.suffix(2))"
            case 4:
                localPart = "\(first).\(second)\(twoDigits)"
            case 5:
                localPart = "\(first.prefix(3))\(fourDigits)\(second)"
            case 6:
                localPart = "\(second)\(twoDigits)\(first)"
            default:
                localPart = "\(first)\(fourDigits)\(second.prefix(3))"
            }

            let candidate = "\(localPart)@gmail.com"
            if !existingEmails.contains(normalizedEmail(candidate)) {
                return candidate
            }
        }

        return "mail\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased())@gmail.com"
    }

    private func normalizedEmail(_ email: String) -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return trimmed }

        let domain = String(parts[1])
        guard domain == "gmail.com" || domain == "googlemail.com" else { return trimmed }
        let localPart = String(parts[0]).replacingOccurrences(of: ".", with: "")
        return "\(localPart)@gmail.com"
    }

    private func showStatus(_ message: String) {
        statusTask?.cancel()
        statusMessage = message
        statusTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }
}
