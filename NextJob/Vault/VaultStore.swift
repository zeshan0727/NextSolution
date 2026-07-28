import Foundation
import LocalAuthentication
import Security
import UIKit

@MainActor
final class VaultStore: ObservableObject {
    static let shared = VaultStore()

    @Published private(set) var entries: [VaultEntry] = []
    @Published private(set) var categories: [String] = ["General"]
    @Published var lastError: String?

    private let fileManager = FileManager.default
    private let rootURL: URL
    private let entriesRootURL: URL
    private let databaseURL: URL

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextJob", isDirectory: true)
        rootURL = appSupport.appendingPathComponent("Secure Logins", isDirectory: true)
        entriesRootURL = rootURL.appendingPathComponent("Attachments", isDirectory: true)
        databaseURL = rootURL.appendingPathComponent("VaultData.json")

        do {
            try fileManager.createDirectory(at: entriesRootURL, withIntermediateDirectories: true)
            try protectItem(at: rootURL)
            load()
        } catch {
            lastError = "Secure Logins could not be opened: \(error.localizedDescription)"
        }
    }

    var sortedCategories: [String] {
        categories.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func entry(id: UUID) -> VaultEntry? {
        entries.first { $0.id == id }
    }

    func password(for entryID: UUID) -> String {
        VaultKeychain.load(entryID: entryID)
    }

    func save(_ entry: VaultEntry, password: String) throws {
        let service = entry.service.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPassword = password.trimmingCharacters(in: .newlines)
        guard !service.isEmpty else { throw VaultError.serviceRequired }
        guard !cleanedPassword.isEmpty else { throw VaultError.passwordRequired }

        var saved = entry
        saved.service = service
        saved.website = saved.website.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.userID = saved.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.category = cleanCategory(saved.category)
        saved.updatedAt = Date()

        try VaultKeychain.save(cleanedPassword, entryID: saved.id)

        if let index = entries.firstIndex(where: { $0.id == saved.id }) {
            entries[index] = saved
        } else {
            entries.append(saved)
        }
        addCategoryIfNeeded(saved.category)
        try persist()
    }

    func delete(_ entry: VaultEntry) {
        entries.removeAll { $0.id == entry.id }
        VaultKeychain.delete(entryID: entry.id)
        try? fileManager.removeItem(at: folderURL(for: entry.id))
        do {
            try persist()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func toggleFavourite(entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].isFavourite.toggle()
        entries[index].updatedAt = Date()
        do {
            try persist()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addCategoryIfNeeded(_ value: String) {
        let category = cleanCategory(value)
        guard !categories.contains(where: { $0.caseInsensitiveCompare(category) == .orderedSame }) else { return }
        categories.append(category)
    }

    func addFile(from sourceURL: URL, entryID: UUID) throws -> VaultAttachment {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        guard values.isDirectory != true else { throw VaultError.folderNotSupported }

        let attachmentID = UUID()
        let originalName = sourceURL.lastPathComponent.isEmpty ? "Attachment" : sourceURL.lastPathComponent
        let storedName = safeStoredName(id: attachmentID, originalName: originalName)
        let destination = try prepareFolder(entryID: entryID).appendingPathComponent(storedName)
        try fileManager.copyItem(at: sourceURL, to: destination)
        try protectItem(at: destination)

        let byteCount = Int64((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return VaultAttachment(
            id: attachmentID,
            originalName: originalName,
            storedName: storedName,
            byteCount: byteCount
        )
    }

    func addImage(_ image: UIImage, entryID: UUID, suggestedName: String = "Camera Photo.jpg") throws -> VaultAttachment {
        guard let data = image.jpegData(compressionQuality: 0.9) else { throw VaultError.imageCouldNotBeSaved }
        return try addData(data, entryID: entryID, originalName: suggestedName)
    }

    func addData(_ data: Data, entryID: UUID, originalName: String) throws -> VaultAttachment {
        let attachmentID = UUID()
        let storedName = safeStoredName(id: attachmentID, originalName: originalName)
        let destination = try prepareFolder(entryID: entryID).appendingPathComponent(storedName)
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        try protectItem(at: destination)
        return VaultAttachment(
            id: attachmentID,
            originalName: originalName,
            storedName: storedName,
            byteCount: Int64(data.count)
        )
    }

    func attachmentURL(_ attachment: VaultAttachment, entryID: UUID) -> URL {
        folderURL(for: entryID).appendingPathComponent(attachment.storedName)
    }

    func deleteAttachmentFile(_ attachment: VaultAttachment, entryID: UUID) {
        try? fileManager.removeItem(at: attachmentURL(attachment, entryID: entryID))
    }

    func cleanupDraft(entryID: UUID) {
        try? fileManager.removeItem(at: folderURL(for: entryID))
    }

    func reload() {
        load()
    }

    private func load() {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            entries = []
            categories = ["General"]
            return
        }
        do {
            let data = try Data(contentsOf: databaseURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let database = try decoder.decode(VaultDatabase.self, from: data)
            entries = database.entries
            categories = database.categories.isEmpty ? ["General"] : database.categories
            entries.forEach { addCategoryIfNeeded($0.displayCategory) }
        } catch {
            lastError = "Your secure login list could not be opened: \(error.localizedDescription)"
            entries = []
            categories = ["General"]
        }
    }

    private func persist() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let database = VaultDatabase(schemaVersion: 1, categories: categories, entries: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(database)
        try data.write(to: databaseURL, options: [.atomic, .completeFileProtection])
        try protectItem(at: databaseURL)
    }

    private func prepareFolder(entryID: UUID) throws -> URL {
        let folder = folderURL(for: entryID)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try protectItem(at: folder)
        return folder
    }

    private func folderURL(for entryID: UUID) -> URL {
        entriesRootURL.appendingPathComponent(entryID.uuidString, isDirectory: true)
    }

    private func cleanCategory(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "General" : cleaned
    }

    private func safeStoredName(id: UUID, originalName: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = originalName.components(separatedBy: invalid).joined(separator: "-")
        return "\(id.uuidString)-\(cleaned.isEmpty ? "Attachment" : cleaned)"
    }

    private func protectItem(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }
}

enum VaultError: LocalizedError {
    case serviceRequired
    case passwordRequired
    case folderNotSupported
    case imageCouldNotBeSaved

    var errorDescription: String? {
        switch self {
        case .serviceRequired: return "Enter the service name before saving."
        case .passwordRequired: return "Enter or generate a password before saving."
        case .folderNotSupported: return "Select individual files. Complete folders are not supported in Secure Logins."
        case .imageCouldNotBeSaved: return "The selected image could not be saved."
        }
    }
}

enum VaultKeychain {
    private static let service = "com.nextsolution.nextjob.secure-logins"

    static func save(_ value: String, entryID: UUID) throws {
        let account = entryID.uuidString
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func load(entryID: UUID) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: entryID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    static func delete(entryID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: entryID.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum VaultSecurity {
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

enum VaultPasswordGenerator {
    static func generate(length: Int = 20) -> String {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%&*+-_=?.")
        guard !characters.isEmpty else { return "" }
        var bytes = [UInt8](repeating: 0, count: max(12, length))
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "") + "!Aa7"
        }
        return String(bytes.map { characters[Int($0) % characters.count] })
    }
}
