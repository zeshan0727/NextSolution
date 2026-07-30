import Foundation

struct PortableBackupItem: Codable {
    var relativePath: String
    var isDirectory: Bool
    var data: Data?
}

struct PortableBackupEnvelope: Codable {
    var schemaVersion: Int
    var createdAt: Date
    var database: AppDatabase
    var items: [PortableBackupItem]
}

struct PreparedPortableBackup {
    var database: AppDatabase
    var stagingRoot: URL
    var fileCount: Int
    var totalBytes: Int64
}

enum PortableBackupError: LocalizedError {
    case unsupportedVersion
    case unsafePath
    case invalidBackup

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            return "This backup was created by a newer version of Next Job."
        case .unsafePath:
            return "The backup contains an unsafe attachment path and was not restored."
        case .invalidBackup:
            return "The selected file is not a valid complete Next Job backup."
        }
    }
}

final class PortableBackupService {
    static let shared = PortableBackupService()

    private let fileManager = FileManager.default
    private let schemaVersion = 1

    private init() {}

    func createBackup(database: AppDatabase) throws -> URL {
        let root = JobFileService.shared.filesRootURL
        var items: [PortableBackupItem] = []

        if fileManager.fileExists(atPath: root.path),
           let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
           ) {
            for case let itemURL as URL in enumerator {
                let values = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                let relativePath = try safeRelativePath(for: itemURL, under: root)
                if values.isDirectory == true {
                    items.append(
                        PortableBackupItem(relativePath: relativePath, isDirectory: true, data: nil)
                    )
                } else if values.isRegularFile == true {
                    let data = try Data(contentsOf: itemURL, options: .mappedIfSafe)
                    items.append(
                        PortableBackupItem(relativePath: relativePath, isDirectory: false, data: data)
                    )
                }
            }
        }

        let envelope = PortableBackupEnvelope(
            schemaVersion: schemaVersion,
            createdAt: Date(),
            database: database,
            items: items
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(envelope)
        let url = fileManager.temporaryDirectory.appendingPathComponent(
            "NextJob-Complete-Backup-\(Self.fileDateFormatter.string(from: Date())).nextjobbackup"
        )
        try data.write(to: url, options: .atomic)
        return url
    }

    func prepareRestore(from sourceURL: URL) throws -> PreparedPortableBackup {
        let data = try coordinatedData(from: sourceURL)
        let decoder = PropertyListDecoder()
        guard let envelope = try? decoder.decode(PortableBackupEnvelope.self, from: data) else {
            throw PortableBackupError.invalidBackup
        }
        guard envelope.schemaVersion <= schemaVersion else {
            throw PortableBackupError.unsupportedVersion
        }

        let stagingParent = fileManager.temporaryDirectory.appendingPathComponent(
            "NextJobRestore-\(UUID().uuidString)",
            isDirectory: true
        )
        let stagingRoot = stagingParent.appendingPathComponent("Next Job Files", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        var fileCount = 0
        var totalBytes: Int64 = 0
        do {
            let directories = envelope.items
                .filter(\.isDirectory)
                .sorted { $0.relativePath.count < $1.relativePath.count }
            for item in directories {
                let destination = try destinationURL(for: item.relativePath, root: stagingRoot)
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            }

            for item in envelope.items where !item.isDirectory {
                guard let itemData = item.data else { throw PortableBackupError.invalidBackup }
                let destination = try destinationURL(for: item.relativePath, root: stagingRoot)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try itemData.write(to: destination, options: .atomic)
                fileCount += 1
                totalBytes += Int64(itemData.count)
            }
        } catch {
            try? fileManager.removeItem(at: stagingParent)
            throw error
        }

        return PreparedPortableBackup(
            database: envelope.database,
            stagingRoot: stagingRoot,
            fileCount: fileCount,
            totalBytes: totalBytes
        )
    }

    func discard(_ prepared: PreparedPortableBackup) {
        try? fileManager.removeItem(at: prepared.stagingRoot.deletingLastPathComponent())
    }

    private func coordinatedData(from url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result { try Data(contentsOf: coordinatedURL, options: .mappedIfSafe) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw PortableBackupError.invalidBackup }
        return try result.get()
    }

    private func safeRelativePath(for url: URL, under root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        guard itemPath.hasPrefix(rootPath + "/") else { throw PortableBackupError.unsafePath }
        let relative = String(itemPath.dropFirst(rootPath.count + 1))
        try validate(relativePath: relative)
        return relative
    }

    private func destinationURL(for relativePath: String, root: URL) throws -> URL {
        try validate(relativePath: relativePath)
        let destination = root.appendingPathComponent(relativePath)
        let standardizedRoot = root.standardizedFileURL.path
        let standardizedDestination = destination.standardizedFileURL.path
        guard standardizedDestination.hasPrefix(standardizedRoot + "/") else {
            throw PortableBackupError.unsafePath
        }
        return destination
    }

    private func validate(relativePath: String) throws {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else {
            throw PortableBackupError.unsafePath
        }
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()
}
