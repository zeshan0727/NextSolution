import Foundation
import WebKit

struct BrowserProfileStorageSnapshot {
    let cookieCount: Int
    let cookiesBytes: Int64
    let cacheBytes: Int64
    let localStorageBytes: Int64
    let indexedDBBytes: Int64
    let otherWebsiteDataBytes: Int64
    let totalWebsiteDataBytes: Int64
    let websiteRecordCount: Int
    let isManagedByWebKit: Bool

    static func empty(cookieCount: Int = 0) -> BrowserProfileStorageSnapshot {
        BrowserProfileStorageSnapshot(
            cookieCount: cookieCount,
            cookiesBytes: 0,
            cacheBytes: 0,
            localStorageBytes: 0,
            indexedDBBytes: 0,
            otherWebsiteDataBytes: 0,
            totalWebsiteDataBytes: 0,
            websiteRecordCount: 0,
            isManagedByWebKit: false
        )
    }
}

struct BrowserProfileRestoreResult {
    let backupDate: Date
    let restartRequiredForFullWebsiteData: Bool
}

enum BrowserProfileFormatting {
    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        if value == 0 { return "0 KB" }
        return formatter.string(fromByteCount: value)
    }

    static func lastUsed(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return "Today, \(formatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func dateAndTime(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

extension BrowserProfileStore {
    func inspectStorage(
        for index: Int,
        includeWebsiteRecords: Bool = true,
        completion: @escaping (BrowserProfileStorageSnapshot) -> Void
    ) {
        let cookieCount = snapshot(for: index).cookieCount
        let namedStoreActive: Bool
        if #available(iOS 17.0, *) {
            namedStoreActive = usesNamedDataStoreWhenAvailable
        } else {
            namedStoreActive = false
        }
        BrowserProfileStorageInspector.inspect(
            profileIndex: index,
            cookieCount: cookieCount,
            profilesRootDirectory: profilesRootDirectory,
            managedByNamedStore: namedStoreActive
        ) { [weak self] diskSnapshot in
            guard let self else {
                DispatchQueue.main.async { completion(diskSnapshot) }
                return
            }

            let finish: (BrowserProfileStorageSnapshot) -> Void = { value in
                self.updateCachedStorageSize(value.totalWebsiteDataBytes, for: index)
                DispatchQueue.main.async {
                    completion(value)
                }
            }

            guard includeWebsiteRecords else {
                finish(diskSnapshot)
                return
            }

            let session = self.session(for: index)
            session.whenReady {
                session.dataStore.fetchDataRecords(
                    ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()
                ) { records in
                    let value = BrowserProfileStorageSnapshot(
                        cookieCount: diskSnapshot.cookieCount,
                        cookiesBytes: diskSnapshot.cookiesBytes,
                        cacheBytes: diskSnapshot.cacheBytes,
                        localStorageBytes: diskSnapshot.localStorageBytes,
                        indexedDBBytes: diskSnapshot.indexedDBBytes,
                        otherWebsiteDataBytes: diskSnapshot.otherWebsiteDataBytes,
                        totalWebsiteDataBytes: diskSnapshot.totalWebsiteDataBytes,
                        websiteRecordCount: records.count,
                        isManagedByWebKit: diskSnapshot.isManagedByWebKit
                    )
                    finish(value)
                }
            }
        }
    }

    func createBackup(
        for index: Int,
        completion: @escaping (Result<Date, Error>) -> Void
    ) {
        let session = session(for: index)
        session.whenReady { [weak self] in
            guard let self else { return }
            session.flushCookies {
                session.getAllCookies { cookies in
                    let snapshot = self.snapshot(for: index)
                    let manifest = BrowserProfileBackupManifest(
                        version: 1,
                        createdAt: Date(),
                        profileName: snapshot.displayName,
                        icon: snapshot.icon,
                        color: snapshot.color,
                        environment: snapshot.environment,
                        lastURL: self.lastURL(for: index)?.absoluteString,
                        permissions: self.exportedWebsitePermissions(for: index),
                        includesWebsiteData: false
                    )
                    BrowserProfileBackupManager.createBackup(
                        profileIndex: index,
                        manifest: manifest,
                        cookies: cookies,
                        profilesRootDirectory: self.profilesRootDirectory
                    ) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let completedManifest):
                                self.setLastBackupDate(completedManifest.createdAt, for: index)
                                completion(.success(completedManifest.createdAt))
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        }
                    }
                }
            }
        }
    }

    func restoreLatestBackup(
        for index: Int,
        completion: @escaping (Result<BrowserProfileRestoreResult, Error>) -> Void
    ) {
        let hasActiveSession = existingSession(for: index) != nil
        BrowserProfileBackupManager.prepareRestore(
            profileIndex: index,
            profilesRootDirectory: profilesRootDirectory,
            hasActiveSession: hasActiveSession
        ) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let payload):
                    self.setDisplayName(payload.manifest.profileName, for: index)
                    self.setIcon(payload.manifest.icon, for: index)
                    self.setColor(payload.manifest.color, for: index)
                    if let value = payload.manifest.lastURL, let url = URL(string: value) {
                        self.setLastURL(url, for: index)
                    } else {
                        self.clearLastURL(for: index)
                    }
                    self.replaceWebsitePermissions(payload.manifest.permissions, for: index)

                    BrowserCookieArchive.save(
                        payload.cookies,
                        profileIndex: index,
                        profilesRootDirectory: self.profilesRootDirectory
                    ) {
                        DispatchQueue.main.async {
                            let finish = {
                                self.setEnvironment(payload.manifest.environment, for: index)
                                self.setLastBackupDate(payload.manifest.createdAt, for: index)
                                self.inspectStorage(for: index, includeWebsiteRecords: false) { _ in
                                    completion(.success(BrowserProfileRestoreResult(
                                        backupDate: payload.manifest.createdAt,
                                        restartRequiredForFullWebsiteData: payload.restartRequired
                                    )))
                                }
                            }

                            if let session = self.existingSession(for: index) {
                                session.replaceCookies(payload.cookies, completion: finish)
                            } else {
                                finish()
                            }
                        }
                    }
                }
            }
        }
    }

    func hasBackup(for index: Int) -> Bool {
        BrowserProfileBackupManager.hasBackup(
            profileIndex: index,
            profilesRootDirectory: profilesRootDirectory
        )
    }
}

private enum BrowserProfileStorageInspector {
    private static let queue = DispatchQueue(
        label: "com.nextsolution.multibrowser.storage-inspector",
        qos: .utility
    )

    static func inspect(
        profileIndex: Int,
        cookieCount: Int,
        profilesRootDirectory: URL,
        managedByNamedStore: Bool,
        completion: @escaping (BrowserProfileStorageSnapshot) -> Void
    ) {
        queue.async {
            let websiteData = BrowserProfileDirectories.websiteDataDirectory(
                profilesRootDirectory: profilesRootDirectory,
                profileIndex: profileIndex
            )
            let cookiesBytes = sizes(
                names: ["Cookies"],
                beneath: websiteData
            ) + fileSize(
                BrowserCookieArchive.fileURL(
                    profileIndex: profileIndex,
                    profilesRootDirectory: profilesRootDirectory
                )
            )
            let cacheBytes = sizes(
                names: ["CacheStorage", "NetworkCache", "ApplicationCache", "MediaCache"],
                beneath: websiteData
            )
            let localStorageBytes = sizes(
                names: ["LocalStorage"],
                beneath: websiteData
            )
            let indexedDBBytes = sizes(
                names: ["IndexedDB"],
                beneath: websiteData
            )
            let websiteDirectoryBytes = directorySize(websiteData)
            let totalBytes = websiteDirectoryBytes + fileSize(
                BrowserCookieArchive.fileURL(
                    profileIndex: profileIndex,
                    profilesRootDirectory: profilesRootDirectory
                )
            )
            let knownBytes = cookiesBytes + cacheBytes + localStorageBytes + indexedDBBytes
            let otherBytes = max(0, totalBytes - knownBytes)
            let isManaged = managedByNamedStore && websiteDirectoryBytes == 0

            completion(BrowserProfileStorageSnapshot(
                cookieCount: cookieCount,
                cookiesBytes: cookiesBytes,
                cacheBytes: cacheBytes,
                localStorageBytes: localStorageBytes,
                indexedDBBytes: indexedDBBytes,
                otherWebsiteDataBytes: otherBytes,
                totalWebsiteDataBytes: totalBytes,
                websiteRecordCount: 0,
                isManagedByWebKit: isManaged
            ))
        }
    }

    private static func sizes(names: [String], beneath root: URL) -> Int64 {
        names.reduce(0) { partial, name in
            partial + directorySize(root.appendingPathComponent(name, isDirectory: true))
        }
    }

    private static func directorySize(_ directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey,
                .fileSizeKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey,
                .fileSizeKey
            ]), values.isRegularFile == true else {
                continue
            }
            let size = values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.fileSize
                ?? 0
            total += Int64(size)
        }
        return total
    }

    private static func fileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey
        ]) else {
            return 0
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }
}

struct BrowserProfileBackupManifest: Codable {
    let version: Int
    let createdAt: Date
    let profileName: String
    let icon: BrowserProfileIcon
    let color: BrowserProfileColor
    let environment: BrowserProfileEnvironment
    let lastURL: String?
    let permissions: [String: [String: String]]
    var includesWebsiteData: Bool
}

struct BrowserProfileRestorePayload {
    let manifest: BrowserProfileBackupManifest
    let cookies: [HTTPCookie]
    let restartRequired: Bool
}

enum BrowserProfileBackupManager {
    private static let queue = DispatchQueue(
        label: "com.nextsolution.multibrowser.profile-backup",
        qos: .userInitiated
    )

    static func createBackup(
        profileIndex: Int,
        manifest: BrowserProfileBackupManifest,
        cookies: [HTTPCookie],
        profilesRootDirectory: URL,
        completion: @escaping (Result<BrowserProfileBackupManifest, Error>) -> Void
    ) {
        queue.async {
            do {
                let fileManager = FileManager.default
                let parent = backupRoot(profilesRootDirectory: profilesRootDirectory)
                try fileManager.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                let temporary = parent.appendingPathComponent(
                    ".Profile-\(profileIndex)-\(UUID().uuidString)",
                    isDirectory: true
                )
                try fileManager.createDirectory(
                    at: temporary,
                    withIntermediateDirectories: true,
                    attributes: [
                        .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
                    ]
                )

                var completedManifest = manifest
                let sourceWebsiteData = BrowserProfileDirectories.websiteDataDirectory(
                    profilesRootDirectory: profilesRootDirectory,
                    profileIndex: profileIndex
                )
                if fileManager.fileExists(atPath: sourceWebsiteData.path) {
                    do {
                        try fileManager.copyItem(
                            at: sourceWebsiteData,
                            to: temporary.appendingPathComponent("WebsiteData", isDirectory: true)
                        )
                        completedManifest.includesWebsiteData = true
                    } catch {
                        try? fileManager.removeItem(
                            at: temporary.appendingPathComponent("WebsiteData", isDirectory: true)
                        )
                        completedManifest.includesWebsiteData = false
                    }
                }

                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                let manifestData = try encoder.encode(completedManifest)
                try manifestData.write(
                    to: temporary.appendingPathComponent("Manifest.plist"),
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
                if let cookieData = BrowserCookieArchive.serializedData(for: cookies) {
                    try cookieData.write(
                        to: temporary.appendingPathComponent("Cookies.plist"),
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                    )
                }

                let destination = backupURL(
                    profileIndex: profileIndex,
                    profilesRootDirectory: profilesRootDirectory
                )
                try? fileManager.removeItem(at: destination)
                try fileManager.moveItem(at: temporary, to: destination)
                completion(.success(completedManifest))
            } catch {
                completion(.failure(error))
            }
        }
    }

    static func prepareRestore(
        profileIndex: Int,
        profilesRootDirectory: URL,
        hasActiveSession: Bool,
        completion: @escaping (Result<BrowserProfileRestorePayload, Error>) -> Void
    ) {
        queue.async {
            do {
                let source = backupURL(
                    profileIndex: profileIndex,
                    profilesRootDirectory: profilesRootDirectory
                )
                let manifestURL = source.appendingPathComponent("Manifest.plist")
                guard let manifestData = try? Data(contentsOf: manifestURL),
                      let manifest = try? PropertyListDecoder().decode(
                        BrowserProfileBackupManifest.self,
                        from: manifestData
                      ), manifest.version == 1 else {
                    throw BrowserProfileStoreError.invalidBackup
                }

                let cookieData = (try? Data(
                    contentsOf: source.appendingPathComponent("Cookies.plist")
                )) ?? Data()
                let cookies = BrowserCookieArchive.cookies(from: cookieData)
                var restartRequired = false

                let sourceWebsiteData = source.appendingPathComponent(
                    "WebsiteData",
                    isDirectory: true
                )
                if manifest.includesWebsiteData,
                   FileManager.default.fileExists(atPath: sourceWebsiteData.path) {
                    if hasActiveSession {
                        try stagePendingRestore(
                            sourceWebsiteData: sourceWebsiteData,
                            profileIndex: profileIndex,
                            profilesRootDirectory: profilesRootDirectory
                        )
                        restartRequired = true
                    } else {
                        try replaceWebsiteData(
                            sourceWebsiteData: sourceWebsiteData,
                            profileIndex: profileIndex,
                            profilesRootDirectory: profilesRootDirectory
                        )
                    }
                }

                completion(.success(BrowserProfileRestorePayload(
                    manifest: manifest,
                    cookies: cookies,
                    restartRequired: restartRequired
                )))
            } catch {
                completion(.failure(error))
            }
        }
    }

    static func hasBackup(profileIndex: Int, profilesRootDirectory: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: backupURL(
                profileIndex: profileIndex,
                profilesRootDirectory: profilesRootDirectory
            ).appendingPathComponent("Manifest.plist").path
        )
    }

    static func removeBackup(profileIndex: Int, profilesRootDirectory: URL) {
        queue.async {
            try? FileManager.default.removeItem(
                at: backupURL(
                    profileIndex: profileIndex,
                    profilesRootDirectory: profilesRootDirectory
                )
            )
            try? FileManager.default.removeItem(
                at: pendingProfileURL(
                    profileIndex: profileIndex,
                    profilesRootDirectory: profilesRootDirectory
                )
            )
        }
    }

    static func applyPendingRestores(profilesRootDirectory: URL) {
        let fileManager = FileManager.default
        for index in 1...BrowserProfileStore.profileCount {
            let pendingProfile = pendingProfileURL(
                profileIndex: index,
                profilesRootDirectory: profilesRootDirectory
            )
            let pendingWebsiteData = pendingProfile.appendingPathComponent(
                "WebsiteData",
                isDirectory: true
            )
            guard fileManager.fileExists(atPath: pendingWebsiteData.path) else { continue }

            let destination = BrowserProfileDirectories.websiteDataDirectory(
                profilesRootDirectory: profilesRootDirectory,
                profileIndex: index
            )
            do {
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                try? fileManager.removeItem(at: destination)
                try fileManager.moveItem(at: pendingWebsiteData, to: destination)
                try? fileManager.removeItem(at: pendingProfile)
            } catch {
                // Leave the queued restore intact so the next launch can retry.
            }
        }
    }

    private static func replaceWebsiteData(
        sourceWebsiteData: URL,
        profileIndex: Int,
        profilesRootDirectory: URL
    ) throws {
        let fileManager = FileManager.default
        let destination = BrowserProfileDirectories.websiteDataDirectory(
            profilesRootDirectory: profilesRootDirectory,
            profileIndex: profileIndex
        )
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let temporary = parent.appendingPathComponent(
            ".WebsiteData-Restore-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.copyItem(at: sourceWebsiteData, to: temporary)
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporary, to: destination)
    }

    private static func stagePendingRestore(
        sourceWebsiteData: URL,
        profileIndex: Int,
        profilesRootDirectory: URL
    ) throws {
        let fileManager = FileManager.default
        let pendingRoot = pendingRoot(profilesRootDirectory: profilesRootDirectory)
        try fileManager.createDirectory(
            at: pendingRoot,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let temporary = pendingRoot.appendingPathComponent(
            ".Profile-\(profileIndex)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: temporary,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try fileManager.copyItem(
            at: sourceWebsiteData,
            to: temporary.appendingPathComponent("WebsiteData", isDirectory: true)
        )
        let destination = pendingProfileURL(
            profileIndex: profileIndex,
            profilesRootDirectory: profilesRootDirectory
        )
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporary, to: destination)
    }

    private static func backupRoot(profilesRootDirectory: URL) -> URL {
        profilesRootDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("BrowserProfileBackups", isDirectory: true)
    }

    private static func backupURL(profileIndex: Int, profilesRootDirectory: URL) -> URL {
        backupRoot(profilesRootDirectory: profilesRootDirectory)
            .appendingPathComponent(
                String(format: "Profile-%02d.nmbprofile", profileIndex),
                isDirectory: true
            )
    }

    private static func pendingRoot(profilesRootDirectory: URL) -> URL {
        profilesRootDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("BrowserProfileRestoreQueue", isDirectory: true)
    }

    private static func pendingProfileURL(
        profileIndex: Int,
        profilesRootDirectory: URL
    ) -> URL {
        pendingRoot(profilesRootDirectory: profilesRootDirectory)
            .appendingPathComponent(
                String(format: "Profile-%02d", profileIndex),
                isDirectory: true
            )
    }
}
