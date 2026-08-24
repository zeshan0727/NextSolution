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
        UIPasteboard.general.string = value
        HapticManager.shared.copied()
        showStatus("\(label) copied")
    }

    func generateFive() {
        var newCredentials: [Credential] = []
        var knownEmails = Set(credentials.map { $0.email.lowercased() })

        while newCredentials.count < 5 {
            let email = makeEmailSuggestion()
            guard knownEmails.insert(email.lowercased()).inserted else { continue }
            newCredentials.append(
                Credential(
                    email: email,
                    password: makePassword(),
                    isGenerated: true
                )
            )
        }

        credentials.append(contentsOf: newCredentials)
        saveCredentials()
        HapticManager.shared.generated()
        showStatus("5 suggestions added")
    }

    private func loadCredentials() {
        let decoder = JSONDecoder()

        if let storedData = KeychainStore.load(),
           let stored = try? decoder.decode([Credential].self, from: storedData),
           !stored.isEmpty {
            credentials = stored
            return
        }

        guard let url = Bundle.main.url(forResource: "Seed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let seed = try? decoder.decode([SeedCredential].self, from: data) else {
            credentials = []
            return
        }

        credentials = seed.map {
            Credential(email: $0.email, password: $0.password)
        }
        saveCredentials()
    }

    private func saveCredentials() {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        KeychainStore.save(data)
    }

    private func makeEmailSuggestion() -> String {
        let firstWords = [
            "amber", "bright", "cedar", "coral", "fresh", "golden",
            "maple", "quiet", "silver", "sunny", "urban", "velvet"
        ]
        let secondWords = [
            "bird", "cove", "desk", "harbor", "meadow", "orbit",
            "palm", "river", "stone", "studio", "trail", "wave"
        ]
        let first = firstWords.randomElement() ?? "bright"
        let second = secondWords.randomElement() ?? "cove"
        let digits = Int.random(in: 1000...9999)
        return "\(first)\(second)\(digits)@gmail.com"
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
