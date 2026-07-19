import Foundation
import Darwin

final class LedgerDiskStore {
    static let shared = LedgerDiskStore()

    private let queue = DispatchQueue(label: "com.nextsolution.dailyledger.storage")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> LedgerData {
        queue.sync {
            withFileLock {
                let exists = FileManager.default.fileExists(atPath: fileURL.path)
                let ledger = loadUnlocked()
                if !exists {
                    try? saveUnlocked(ledger)
                }
                return ledger
            }
        }
    }

    func save(_ ledger: LedgerData) throws {
        try queue.sync {
            try withFileLock { try saveUnlocked(ledger) }
        }
    }

    @discardableResult
    func mutate(_ changes: (inout LedgerData) -> Void) throws -> LedgerData {
        try queue.sync {
            try withFileLock {
                var ledger = loadUnlocked()
                changes(&ledger)
                try saveUnlocked(ledger)
                return ledger
            }
        }
    }

    @discardableResult
    func add(_ transaction: LedgerTransaction) throws -> LedgerData {
        try queue.sync {
            try withFileLock {
                var ledger = loadUnlocked()
                guard !ledger.transactions.contains(where: { $0.id == transaction.id }) else {
                    return ledger
                }
                ledger.transactions.append(transaction)
                try saveUnlocked(ledger)
                return ledger
            }
        }
    }

    @discardableResult
    func merge(
        _ incoming: [LedgerTransaction],
        restoring settings: LedgerSettings? = nil
    ) throws -> LedgerData {
        try queue.sync {
            try withFileLock {
                var ledger = loadUnlocked()
                let existingIDs = Set(ledger.transactions.map(\.id))
                ledger.transactions.append(contentsOf: incoming.filter { !existingIDs.contains($0.id) })
                if let settings {
                    ledger.settings = settings
                }
                try saveUnlocked(ledger)
                return ledger
            }
        }
    }

    private func withFileLock<T>(_ work: () throws -> T) rethrows -> T {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return try work() }
        Darwin.flock(descriptor, LOCK_EX)
        defer {
            Darwin.flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
        }
        return try work()
    }

    private func loadUnlocked() -> LedgerData {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode(LedgerData.self, from: data) else {
            return LedgerData()
        }
        return decoded
    }

    private func saveUnlocked(_ ledger: LedgerData) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        let data = try encoder.encode(ledger)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    private var fileURL: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return root
            .appendingPathComponent("DailyLedger", isDirectory: true)
            .appendingPathComponent("ledger.json")
    }

    private var lockURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("ledger.lock")
    }
}
