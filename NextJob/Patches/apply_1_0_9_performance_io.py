from pathlib import Path


def replace_required(text: str, old: str, new: str, label: str, count: int = 1) -> str:
    found = text.count(old)
    if found < count:
        raise RuntimeError(f"Could not locate {label}; expected {count}, found {found}")
    return text.replace(old, new, count)

# Move Secure Logins JSON writes away from the main UI thread.
store_path = Path("NextJob/Vault/VaultStore.swift")
store = store_path.read_text(encoding="utf-8")
store = replace_required(
    store,
    "    private let databaseURL: URL\n",
    '''    private let databaseURL: URL
    private let persistenceQueue = DispatchQueue(
        label: "com.nextsolution.nextjob.vault-persistence",
        qos: .utility
    )
''',
    "vault persistence queue",
)
store = replace_required(
    store,
    '''    private func persist() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let database = VaultDatabase(schemaVersion: 1, categories: categories, entries: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(database)
        try data.write(to: databaseURL, options: [.atomic, .completeFileProtection])
        try protectItem(at: databaseURL)
    }
''',
    '''    private func persist() throws {
        let database = VaultDatabase(schemaVersion: 1, categories: categories, entries: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(database)
        let rootURL = rootURL
        let databaseURL = databaseURL

        persistenceQueue.async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
                try data.write(to: databaseURL, options: [.atomic, .completeFileProtection])
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: databaseURL.path
                )
            } catch {
                Task { @MainActor [weak self] in
                    self?.lastError = "Secure Logins could not save changes: \(error.localizedDescription)"
                }
            }
        }
    }
''',
    "background vault persistence",
)

helpers = '''    func addFileAsync(from sourceURL: URL, entryID: UUID) async throws -> VaultAttachment {
        let destinationFolder = folderURL(for: entryID)
        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
            let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            guard values.isDirectory != true else { throw VaultError.folderNotSupported }

            try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
            try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destinationFolder.path)
            let attachmentID = UUID()
            let originalName = sourceURL.lastPathComponent.isEmpty ? "Attachment" : sourceURL.lastPathComponent
            let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            let cleaned = originalName.components(separatedBy: invalid).joined(separator: "-")
            let storedName = "\(attachmentID.uuidString)-\(cleaned.isEmpty ? "Attachment" : cleaned)"
            let destination = destinationFolder.appendingPathComponent(storedName)
            try fileManager.copyItem(at: sourceURL, to: destination)
            try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
            let byteCount = Int64((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            return VaultAttachment(id: attachmentID, originalName: originalName, storedName: storedName, byteCount: byteCount)
        }.value
    }

    func addDataAsync(_ data: Data, entryID: UUID, originalName: String) async throws -> VaultAttachment {
        let destinationFolder = folderURL(for: entryID)
        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
            try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destinationFolder.path)
            let attachmentID = UUID()
            let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            let cleaned = originalName.components(separatedBy: invalid).joined(separator: "-")
            let storedName = "\(attachmentID.uuidString)-\(cleaned.isEmpty ? "Attachment" : cleaned)"
            let destination = destinationFolder.appendingPathComponent(storedName)
            try data.write(to: destination, options: [.atomic, .completeFileProtection])
            try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
            return VaultAttachment(id: attachmentID, originalName: originalName, storedName: storedName, byteCount: Int64(data.count))
        }.value
    }

'''
store = replace_required(
    store,
    "    func attachmentURL(_ attachment: VaultAttachment, entryID: UUID) -> URL {\n",
    helpers + "    func attachmentURL(_ attachment: VaultAttachment, entryID: UUID) -> URL {\n",
    "background attachment helpers",
)
store_path.write_text(store, encoding="utf-8")

# Avoid re-rendering unchanged login cards and move bulk attachment work off the main actor.
views_path = Path("NextJob/Vault/VaultViews.swift")
views = views_path.read_text(encoding="utf-8")
views = replace_required(
    views,
    '''                                    } label: {
                                        VaultEntryCard(entry: entry)
                                    }
                                    .buttonStyle(.plain)''',
    '''                                    } label: {
                                        VaultEntryCard(entry: entry)
                                            .equatable()
                                    }
                                    .buttonStyle(.plain)''',
    "equatable login cards",
)
views = replace_required(
    views,
    "private struct VaultEntryCard: View {",
    "private struct VaultEntryCard: View, Equatable {",
    "equatable login card type",
)
views = replace_required(
    views,
    '''    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            isImporting = true
            defer { isImporting = false }
            for url in urls {
                let attachment = try vaultStore.addFile(from: url, entryID: draft.id)
                draft.attachments.append(attachment)
                addedAttachmentIDs.insert(attachment.id)
            }
        } catch {
            isImporting = false
            showNotice("Files Not Added", error.localizedDescription)
        }
    }
''',
    '''    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            isImporting = true
            Task {
                defer { isImporting = false }
                for url in urls {
                    do {
                        let attachment = try await vaultStore.addFileAsync(from: url, entryID: draft.id)
                        draft.attachments.append(attachment)
                        addedAttachmentIDs.insert(attachment.id)
                        await Task.yield()
                    } catch {
                        showNotice("File Not Added", error.localizedDescription)
                    }
                }
            }
        } catch {
            isImporting = false
            showNotice("Files Not Added", error.localizedDescription)
        }
    }
''',
    "background file imports",
)
views = replace_required(
    views,
    '''                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data),
                          let jpeg = image.jpegData(compressionQuality: 0.9) else {
                        throw VaultError.imageCouldNotBeSaved
                    }
                    let name = "Photo-\(Self.attachmentDateFormatter.string(from: Date()))-\(index + 1).jpg"
                    let attachment = try vaultStore.addData(jpeg, entryID: draft.id, originalName: name)
                    draft.attachments.append(attachment)
                    addedAttachmentIDs.insert(attachment.id)''',
    '''                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw VaultError.imageCouldNotBeSaved
                    }
                    let jpeg = try await Task.detached(priority: .userInitiated) {
                        guard let image = UIImage(data: data),
                              let compressed = image.jpegData(compressionQuality: 0.86) else {
                            throw VaultError.imageCouldNotBeSaved
                        }
                        return compressed
                    }.value
                    let name = "Photo-\(Self.attachmentDateFormatter.string(from: Date()))-\(index + 1).jpg"
                    let attachment = try await vaultStore.addDataAsync(jpeg, entryID: draft.id, originalName: name)
                    draft.attachments.append(attachment)
                    addedAttachmentIDs.insert(attachment.id)
                    await Task.yield()''',
    "background photo decoding and compression",
)
views_path.write_text(views, encoding="utf-8")

print("Next Job 1.0.9 background I/O performance update applied.")
