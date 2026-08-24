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
        credentials.append(contentsOf: makeBlankCredentials(count: 5))
        saveCredentials()
        HapticManager.shared.generated()
        showStatus("5 private slots added")
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

        var known = Set(credentials.map { $0.email.lowercased() }.filter { !$0.isEmpty })
        var imported = 0

        for email in candidates where known.insert(email.lowercased()).inserted {
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

    private func loadCredentials() {
        let decoder = JSONDecoder()

        if let storedData = KeychainStore.load(),
           let stored = try? decoder.decode([Credential].self, from: storedData),
           !stored.isEmpty {
            credentials = stored
            return
        }

        if let legacyData = KeychainStore.loadLegacy(),
           let legacy = try? decoder.decode([Credential].self, from: legacyData),
           let first = legacy.first {
            credentials = [first] + makeBlankCredentials(count: 21)
            saveCredentials()
            KeychainStore.deleteLegacy()
            return
        }

        credentials = makeBlankCredentials(count: 22)
        saveCredentials()
    }

    private func saveCredentials() {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        KeychainStore.save(data)
    }

    private func makeBlankCredentials(count: Int) -> [Credential] {
        (0..<count).map { _ in
            Credential(
                email: "",
                password: makePassword(),
                isGenerated: true
            )
        }
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
