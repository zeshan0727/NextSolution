import Foundation

@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var entries: [PasswordEntry] = []

    init() { load() }

    func add(_ entry: PasswordEntry) {
        entries.insert(entry, at: 0)
        persist()
    }

    func delete(ids: [UUID]) {
        entries.removeAll { ids.contains($0.id) }
        persist()
    }

    private func load() {
        guard let data = KeychainStore.load(),
              let decoded = try? JSONDecoder().decode([PasswordEntry].self, from: data) else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? KeychainStore.save(data)
    }
}
