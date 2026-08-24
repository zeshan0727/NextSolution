import Foundation
import WebKit

extension Notification.Name {
    static let nextMultiBrowserProfileDidChange = Notification.Name("NextMultiBrowserProfileDidChange")
    static let nextMultiBrowserProfileEnvironmentDidChange = Notification.Name("NextMultiBrowserProfileEnvironmentDidChange")
}

enum BrowserPermissionDecision: String, Codable {
    case allow
    case deny
}

struct BrowserProfileSnapshot {
    let index: Int
    let displayName: String
    let icon: BrowserProfileIcon
    let color: BrowserProfileColor
    let environment: BrowserProfileEnvironment
    let cookieCount: Int
    let hasGoogleSession: Bool
    let lastUpdated: Date?
    let lastUsed: Date?
    let cachedStorageSize: Int64
    let lastBackupDate: Date?
    let savedPermissionCount: Int

    var statusText: String {
        if hasGoogleSession {
            return "Google session saved"
        }
        if cookieCount > 0 {
            return "\(cookieCount) cookie\(cookieCount == 1 ? "" : "s") saved"
        }
        return "Ready for a separate login"
    }
}

enum BrowserProfileStoreError: LocalizedError {
    case noAvailableDuplicateSlot
    case backupUnavailable
    case invalidBackup

    var errorDescription: String? {
        switch self {
        case .noAvailableDuplicateSlot:
            return "No unused profile slot is available. Clear or delete an unused profile first."
        case .backupUnavailable:
            return "No backup exists for this profile."
        case .invalidBackup:
            return "The profile backup could not be read."
        }
    }
}

final class BrowserProfileStore {
    static let shared = BrowserProfileStore()
    static let profileCount = 20

    let defaults: UserDefaults
    let profilesRootDirectory: URL
    let usesNamedDataStoreWhenAvailable: Bool

    private var sessions: [Int: BrowserProfileSession] = [:]
    private let profileWorkQueue = DispatchQueue(
        label: "com.nextsolution.multibrowser.profile-work",
        qos: .userInitiated
    )

    private convenience init() {
        self.init(
            defaults: .standard,
            profilesRootDirectory: BrowserProfileDirectories.defaultRootDirectory,
            usesNamedDataStoreWhenAvailable: true
        )
    }

    init(
        defaults: UserDefaults,
        profilesRootDirectory: URL,
        usesNamedDataStoreWhenAvailable: Bool = true
    ) {
        self.defaults = defaults
        self.profilesRootDirectory = profilesRootDirectory
        self.usesNamedDataStoreWhenAvailable = usesNamedDataStoreWhenAvailable
        BrowserProfileBackupManager.applyPendingRestores(
            profilesRootDirectory: profilesRootDirectory
        )
    }

    func session(for index: Int) -> BrowserProfileSession {
        validate(index)
        if let session = sessions[index] {
            return session
        }

        let session = BrowserProfileSession(
            index: index,
            persistentIdentifier: persistentIdentifier(for: index),
            profilesRootDirectory: profilesRootDirectory,
            useNamedDataStoreWhenAvailable: usesNamedDataStoreWhenAvailable,
            profileStore: self
        )
        sessions[index] = session
        return session
    }

    func existingSession(for index: Int) -> BrowserProfileSession? {
        sessions[index]
    }

    func snapshot(for index: Int) -> BrowserProfileSnapshot {
        validate(index)
        return BrowserProfileSnapshot(
            index: index,
            displayName: displayName(for: index),
            icon: icon(for: index),
            color: color(for: index),
            environment: environment(for: index),
            cookieCount: defaults.integer(forKey: cookieCountKey(for: index)),
            hasGoogleSession: defaults.bool(forKey: googleSessionKey(for: index)),
            lastUpdated: defaults.object(forKey: lastUpdatedKey(for: index)) as? Date,
            lastUsed: defaults.object(forKey: lastUsedKey(for: index)) as? Date,
            cachedStorageSize: Int64(defaults.double(forKey: cachedStorageSizeKey(for: index))),
            lastBackupDate: defaults.object(forKey: lastBackupDateKey(for: index)) as? Date,
            savedPermissionCount: websitePermissions(for: index).values.reduce(0) { $0 + $1.count }
        )
    }

    func persistenceDescription(for index: Int) -> String {
        session(for: index).persistenceDescription
    }

    func storageLocationDescription(for index: Int) -> String {
        validate(index)
        return BrowserProfileDirectories.relativeWebsiteDataPath(profileIndex: index)
    }

    func displayName(for index: Int) -> String {
        validate(index)
        let saved = defaults.string(forKey: displayNameKey(for: index))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return saved?.isEmpty == false ? saved! : "Browser \(index)"
    }

    func setDisplayName(_ name: String, for index: Int) {
        validate(index)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Browser \(index)" {
            defaults.removeObject(forKey: displayNameKey(for: index))
        } else {
            defaults.set(trimmed, forKey: displayNameKey(for: index))
        }
        postProfileChanged(index)
    }

    func icon(for index: Int) -> BrowserProfileIcon {
        validate(index)
        guard let rawValue = defaults.string(forKey: iconKey(for: index)),
              let value = BrowserProfileIcon(rawValue: rawValue) else {
            return .person
        }
        return value
    }

    func setIcon(_ icon: BrowserProfileIcon, for index: Int) {
        validate(index)
        if icon == .person {
            defaults.removeObject(forKey: iconKey(for: index))
        } else {
            defaults.set(icon.rawValue, forKey: iconKey(for: index))
        }
        postProfileChanged(index)
    }

    func color(for index: Int) -> BrowserProfileColor {
        validate(index)
        guard let rawValue = defaults.string(forKey: colorKey(for: index)),
              let value = BrowserProfileColor(rawValue: rawValue) else {
            return .blue
        }
        return value
    }

    func setColor(_ color: BrowserProfileColor, for index: Int) {
        validate(index)
        if color == .blue {
            defaults.removeObject(forKey: colorKey(for: index))
        } else {
            defaults.set(color.rawValue, forKey: colorKey(for: index))
        }
        postProfileChanged(index)
    }

    func environment(for index: Int) -> BrowserProfileEnvironment {
        validate(index)
        guard let data = defaults.data(forKey: environmentKey(for: index)),
              let value = try? JSONDecoder().decode(BrowserProfileEnvironment.self, from: data) else {
            return .default
        }
        let normalized = value.manuallySelectableNormalized
        if normalized != value {
            persistEnvironment(normalized, for: index)
        }
        return normalized
    }

    func setEnvironment(_ environment: BrowserProfileEnvironment, for index: Int) {
        validate(index)
        persistEnvironment(environment.manuallySelectableNormalized, for: index)
        postEnvironmentChanged(index)
    }

    @discardableResult
    func randomizeAllEnvironments() -> [BrowserProfileEnvironment] {
        let indices = Array(1...Self.profileCount)
        let existing = indices.map(environment(for:))
        let randomized = BrowserProfileEnvironment.randomizedBatch(
            count: Self.profileCount,
            excluding: existing
        )
        guard randomized.count == Self.profileCount else { return [] }

        for (index, environment) in zip(indices, randomized) {
            persistEnvironment(environment, for: index)
        }
        indices.forEach { postEnvironmentChanged($0) }
        return randomized
    }

    private func persistEnvironment(_ environment: BrowserProfileEnvironment, for index: Int) {
        if environment == .default {
            defaults.removeObject(forKey: environmentKey(for: index))
        } else if let data = try? JSONEncoder().encode(environment) {
            defaults.set(data, forKey: environmentKey(for: index))
        }
    }

    func setLastURL(_ url: URL, for index: Int) {
        validate(index)
        guard url.scheme == "http" || url.scheme == "https" else { return }
        defaults.set(url.absoluteString, forKey: lastURLKey(for: index))
        recordLastUsed(index)
    }

    func lastURL(for index: Int) -> URL? {
        validate(index)
        guard let value = defaults.string(forKey: lastURLKey(for: index)) else { return nil }
        return URL(string: value)
    }

    func clearLastURL(for index: Int) {
        validate(index)
        defaults.removeObject(forKey: lastURLKey(for: index))
        postProfileChanged(index)
    }

    func recordLastUsed(_ index: Int) {
        validate(index)
        defaults.set(Date(), forKey: lastUsedKey(for: index))
        postProfileChanged(index)
    }

    func clearProfile(_ index: Int, completion: @escaping () -> Void) {
        validate(index)
        let session = session(for: index)
        session.whenReady { [weak self] in
            guard let self else {
                completion()
                return
            }

            session.clearWebsiteData {
                self.defaults.removeObject(forKey: self.cookieCountKey(for: index))
                self.defaults.removeObject(forKey: self.googleSessionKey(for: index))
                self.defaults.removeObject(forKey: self.lastUpdatedKey(for: index))
                self.defaults.removeObject(forKey: self.lastURLKey(for: index))
                self.defaults.set(0, forKey: self.cachedStorageSizeKey(for: index))
                self.postProfileChanged(index)
                completion()
            }
        }
    }

    func deleteProfile(_ index: Int, completion: @escaping () -> Void) {
        validate(index)
        clearProfile(index) { [weak self] in
            guard let self else {
                completion()
                return
            }
            self.removeProfileMetadata(index, preserveStoreIdentifier: true)
            BrowserProfileBackupManager.removeBackup(
                profileIndex: index,
                profilesRootDirectory: self.profilesRootDirectory
            )
            self.postEnvironmentChanged(index)
            completion()
        }
    }

    func duplicateProfile(
        _ sourceIndex: Int,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        validate(sourceIndex)
        let sourceSnapshot = snapshot(for: sourceIndex)
        let sourceLastURL = lastURL(for: sourceIndex)

        profileWorkQueue.async { [weak self] in
            guard let self else { return }
            let target = (1...Self.profileCount).first { candidate in
                candidate != sourceIndex && self.isReusableDuplicateTarget(candidate)
            }
            guard let target else {
                DispatchQueue.main.async {
                    completion(.failure(BrowserProfileStoreError.noAvailableDuplicateSlot))
                }
                return
            }

            let targetDirectory = BrowserProfileDirectories.profileDirectory(
                profilesRootDirectory: self.profilesRootDirectory,
                profileIndex: target
            )
            try? FileManager.default.removeItem(at: targetDirectory)
            BrowserCookieArchive.remove(
                profileIndex: target,
                profilesRootDirectory: self.profilesRootDirectory
            )

            self.removeProfileMetadata(target, preserveStoreIdentifier: false)
            self.defaults.set(UUID().uuidString, forKey: self.persistentIdentifierKey(for: target))
            self.defaults.set(
                self.uniqueDuplicateName(sourceSnapshot.displayName, targetIndex: target),
                forKey: self.displayNameKey(for: target)
            )
            if sourceSnapshot.icon != .person {
                self.defaults.set(sourceSnapshot.icon.rawValue, forKey: self.iconKey(for: target))
            }
            if sourceSnapshot.color != .blue {
                self.defaults.set(sourceSnapshot.color.rawValue, forKey: self.colorKey(for: target))
            }
            if sourceSnapshot.environment != .default,
               let data = try? JSONEncoder().encode(sourceSnapshot.environment) {
                self.defaults.set(data, forKey: self.environmentKey(for: target))
            }
            if let sourceLastURL {
                self.defaults.set(sourceLastURL.absoluteString, forKey: self.lastURLKey(for: target))
            }

            DispatchQueue.main.async {
                self.postEnvironmentChanged(target)
                completion(.success(target))
            }
        }
    }

    func flushAllProfiles(completion: @escaping () -> Void = {}) {
        let activeSessions = Array(sessions.values)
        guard !activeSessions.isEmpty else {
            completion()
            return
        }

        let group = DispatchGroup()
        activeSessions.forEach { session in
            group.enter()
            session.flushCookies {
                group.leave()
            }
        }
        group.notify(queue: .main, execute: completion)
    }

    func permissionDecision(
        forOrigin origin: String,
        kind: String,
        profileIndex: Int
    ) -> BrowserPermissionDecision? {
        validate(profileIndex)
        guard let rawValue = websitePermissions(for: profileIndex)[origin]?[kind] else {
            return nil
        }
        return BrowserPermissionDecision(rawValue: rawValue)
    }

    func setPermissionDecision(
        _ decision: BrowserPermissionDecision,
        forOrigin origin: String,
        kind: String,
        profileIndex: Int
    ) {
        validate(profileIndex)
        var values = websitePermissions(for: profileIndex)
        var originValues = values[origin] ?? [:]
        originValues[kind] = decision.rawValue
        values[origin] = originValues
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: permissionsKey(for: profileIndex))
        }
        postProfileChanged(profileIndex)
    }

    func resetWebsitePermissions(_ index: Int) {
        validate(index)
        defaults.removeObject(forKey: permissionsKey(for: index))
        postProfileChanged(index)
    }

    func exportedWebsitePermissions(for index: Int) -> [String: [String: String]] {
        validate(index)
        return websitePermissions(for: index)
    }

    func replaceWebsitePermissions(
        _ values: [String: [String: String]],
        for index: Int
    ) {
        validate(index)
        if values.isEmpty {
            defaults.removeObject(forKey: permissionsKey(for: index))
        } else if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: permissionsKey(for: index))
        }
        postProfileChanged(index)
    }

    func persistentIdentifier(for index: Int) -> UUID {
        validate(index)
        let key = persistentIdentifierKey(for: index)
        if let value = defaults.string(forKey: key), let identifier = UUID(uuidString: value) {
            return identifier
        }

        let identifier = UUID()
        defaults.set(identifier.uuidString, forKey: key)
        return identifier
    }

    func updateCachedStorageSize(_ bytes: Int64, for index: Int) {
        validate(index)
        defaults.set(Double(bytes), forKey: cachedStorageSizeKey(for: index))
        postProfileChanged(index)
    }

    func setLastBackupDate(_ date: Date?, for index: Int) {
        validate(index)
        if let date {
            defaults.set(date, forKey: lastBackupDateKey(for: index))
        } else {
            defaults.removeObject(forKey: lastBackupDateKey(for: index))
        }
        postProfileChanged(index)
    }

    fileprivate func recordCookies(_ cookies: [HTTPCookie], for index: Int) {
        defaults.set(cookies.count, forKey: cookieCountKey(for: index))
        defaults.set(Self.containsGoogleSession(cookies), forKey: googleSessionKey(for: index))
        defaults.set(Date(), forKey: lastUpdatedKey(for: index))
        postProfileChanged(index)
    }

    func postProfileChanged(_ index: Int) {
        let post = {
            NotificationCenter.default.post(
                name: .nextMultiBrowserProfileDidChange,
                object: self,
                userInfo: ["profileIndex": index]
            )
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    private func postEnvironmentChanged(_ index: Int) {
        postProfileChanged(index)
        let post = {
            NotificationCenter.default.post(
                name: .nextMultiBrowserProfileEnvironmentDidChange,
                object: self,
                userInfo: ["profileIndex": index]
            )
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    private func isReusableDuplicateTarget(_ index: Int) -> Bool {
        guard sessions[index] == nil,
              displayName(for: index) == "Browser \(index)",
              icon(for: index) == .person,
              color(for: index) == .blue,
              environment(for: index) == .default,
              lastURL(for: index) == nil,
              defaults.integer(forKey: cookieCountKey(for: index)) == 0,
              websitePermissions(for: index).isEmpty else {
            return false
        }

        return !BrowserProfileDirectories.profileHasWebsiteData(
            profilesRootDirectory: profilesRootDirectory,
            profileIndex: index
        )
    }

    private func uniqueDuplicateName(_ sourceName: String, targetIndex: Int) -> String {
        let baseName = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let proposed = baseName.isEmpty ? "Browser \(targetIndex) Copy" : "\(baseName) Copy"
        let existingNames = Set((1...Self.profileCount).map(displayName(for:)))
        guard existingNames.contains(proposed) else { return proposed }
        return "\(proposed) \(targetIndex)"
    }

    private func removeProfileMetadata(_ index: Int, preserveStoreIdentifier: Bool) {
        let keys = [
            displayNameKey(for: index),
            iconKey(for: index),
            colorKey(for: index),
            environmentKey(for: index),
            cookieCountKey(for: index),
            googleSessionKey(for: index),
            lastUpdatedKey(for: index),
            lastUsedKey(for: index),
            lastURLKey(for: index),
            cachedStorageSizeKey(for: index),
            lastBackupDateKey(for: index),
            permissionsKey(for: index)
        ]
        keys.forEach(defaults.removeObject(forKey:))
        if !preserveStoreIdentifier {
            defaults.removeObject(forKey: persistentIdentifierKey(for: index))
        }
    }

    private func websitePermissions(for index: Int) -> [String: [String: String]] {
        guard let data = defaults.data(forKey: permissionsKey(for: index)),
              let values = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            return [:]
        }
        return values
    }

    private static func containsGoogleSession(_ cookies: [HTTPCookie]) -> Bool {
        let authenticationCookies: Set<String> = [
            "SID", "HSID", "SSID", "APISID", "SAPISID", "LOGIN_INFO",
            "__Secure-1PSID", "__Secure-3PSID", "__Secure-1PAPISID", "__Secure-3PAPISID"
        ]

        return cookies.contains { cookie in
            let domain = cookie.domain.lowercased()
            let isGoogleDomain = domain.contains("google.") || domain.hasSuffix("youtube.com")
            return isGoogleDomain && authenticationCookies.contains(cookie.name)
        }
    }

    private func validate(_ index: Int) {
        precondition((1...Self.profileCount).contains(index))
    }

    private func persistentIdentifierKey(for index: Int) -> String {
        "NextMultiBrowser.profile.\(index).websiteDataStoreIdentifier"
    }

    private func displayNameKey(for index: Int) -> String {
        "NextMultiBrowser.profile.\(index).displayName"
    }

    private func iconKey(for index: Int) -> String {
        "NextMultiBrowser.profile.\(index).icon"
    }

    private func colorKey(for index: Int) -> String {
        "NextMultiBrowser.profile.\(index).color"
    }

    private func environmentKey(for index: Int) -> String {
        "NextMultiBrowser.profile.\(index).environment"
    }

    private func cookieCountKey(for index: Int) -> String {
        "NextMultiBrowser.profile.\(index).cookieCount"
    }

    private func googleSessionKey(for index: Int) -> String {
        "NextMultiBrowser.profile.\(index).hasGoogleSession"
    }

    private func lastUpdatedKey(for index: Int) -> String {
        "NextMultiBrowser.profile.\(index).lastUpdated"
    }

    private func lastUsedKey(for index: Int) -> String {
        "NextMultiBrowser.profile.\(index).lastUsed"
    }

    private func lastURLKey(for index: Int) -> String {
        "NextMultiBrowser.profile.\(index).lastURL"
    }

    private func cachedStorageSizeKey(for index: Int) -> String {
        "NextMultiBrowser.profile.\(index).cachedStorageSize"
    }

    private func lastBackupDateKey(for index: Int) -> String {
        "NextMultiBrowser.profile.\(index).lastBackupDate"
    }

    private func permissionsKey(for index: Int) -> String {
        "NextMultiBrowser.profile.\(index).permissions"
    }
}

final class BrowserProfileSession: NSObject, WKHTTPCookieStoreObserver {
    private enum PersistenceMode {
        case namedStore
        case profileDirectory
        case cookieArchiveFallback

        var usesPersistentWebsiteDataStore: Bool {
            self != .cookieArchiveFallback
        }

        var description: String {
            switch self {
            case .namedStore, .profileDirectory:
                return "Persistent profile"
            case .cookieArchiveFallback:
                return "Cookie fallback"
            }
        }
    }

    let index: Int
    let dataStore: WKWebsiteDataStore
    let processPool = WKProcessPool()

    var persistenceDescription: String {
        persistenceMode.description
    }

    private weak var profileStore: BrowserProfileStore?
    private let persistenceMode: PersistenceMode
    private let profilesRootDirectory: URL
    private var readyBlocks: [() -> Void] = []
    private var isReady = false
    private var saveWorkItem: DispatchWorkItem?

    init(
        index: Int,
        persistentIdentifier: UUID,
        profilesRootDirectory: URL,
        useNamedDataStoreWhenAvailable: Bool,
        profileStore: BrowserProfileStore
    ) {
        self.index = index
        self.profileStore = profileStore
        self.profilesRootDirectory = profilesRootDirectory

        if #available(iOS 17.0, *), useNamedDataStoreWhenAvailable {
            dataStore = WKWebsiteDataStore(forIdentifier: persistentIdentifier)
            persistenceMode = .namedStore
        } else if let persistentStore = NMBCreatePersistentWebsiteDataStore(
            BrowserProfileDirectories.websiteDataDirectory(
                profilesRootDirectory: profilesRootDirectory,
                profileIndex: index
            )
        ) {
            dataStore = persistentStore
            persistenceMode = .profileDirectory
        } else {
            dataStore = WKWebsiteDataStore.nonPersistent()
            persistenceMode = .cookieArchiveFallback
        }

        super.init()
        dataStore.httpCookieStore.add(self)
        restoreCookiesIfNeeded()
    }

    deinit {
        saveWorkItem?.cancel()
        dataStore.httpCookieStore.remove(self)
    }

    func whenReady(_ block: @escaping () -> Void) {
        let work = {
            if self.isReady {
                block()
            } else {
                self.readyBlocks.append(block)
            }
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        scheduleCookieSnapshot()
    }

    func flushCookies(completion: @escaping () -> Void = {}) {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        captureCookies(completion: completion)
    }

    func getAllCookies(completion: @escaping ([HTTPCookie]) -> Void) {
        dataStore.httpCookieStore.getAllCookies { cookies in
            DispatchQueue.main.async {
                completion(cookies)
            }
        }
    }

    func replaceCookies(_ cookies: [HTTPCookie], completion: @escaping () -> Void) {
        dataStore.httpCookieStore.getAllCookies { [weak self] currentCookies in
            guard let self else {
                DispatchQueue.main.async(execute: completion)
                return
            }
            let deleteGroup = DispatchGroup()
            currentCookies.forEach { cookie in
                deleteGroup.enter()
                self.dataStore.httpCookieStore.delete(cookie) {
                    deleteGroup.leave()
                }
            }
            deleteGroup.notify(queue: .main) {
                let setGroup = DispatchGroup()
                cookies.forEach { cookie in
                    setGroup.enter()
                    self.dataStore.httpCookieStore.setCookie(cookie) {
                        setGroup.leave()
                    }
                }
                setGroup.notify(queue: .main) {
                    self.profileStore?.recordCookies(cookies, for: self.index)
                    completion()
                }
            }
        }
    }

    func clearWebsiteData(completion: @escaping () -> Void) {
        saveWorkItem?.cancel()
        saveWorkItem = nil

        dataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) { [weak self] in
            guard let self else {
                DispatchQueue.main.async(execute: completion)
                return
            }

            let finish = {
                self.profileStore?.recordCookies([], for: self.index)
                DispatchQueue.main.async(execute: completion)
            }
            BrowserCookieArchive.remove(
                profileIndex: self.index,
                profilesRootDirectory: self.profilesRootDirectory,
                completion: finish
            )
        }
    }

    private func restoreCookiesIfNeeded() {
        let archivedCookies = BrowserCookieArchive.load(
            profileIndex: index,
            profilesRootDirectory: profilesRootDirectory
        )
        guard !archivedCookies.isEmpty else {
            finishPreparing()
            captureCookies()
            return
        }

        let group = DispatchGroup()
        for cookie in archivedCookies {
            group.enter()
            dataStore.httpCookieStore.setCookie(cookie) {
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.profileStore?.recordCookies(archivedCookies, for: self.index)

            guard self.persistenceMode.usesPersistentWebsiteDataStore else {
                self.finishPreparing()
                return
            }

            BrowserCookieArchive.remove(
                profileIndex: self.index,
                profilesRootDirectory: self.profilesRootDirectory
            ) { [weak self] in
                DispatchQueue.main.async {
                    self?.finishPreparing()
                    self?.captureCookies()
                }
            }
        }
    }

    private func finishPreparing() {
        let finish = {
            guard !self.isReady else { return }
            self.isReady = true
            let blocks = self.readyBlocks
            self.readyBlocks.removeAll()
            blocks.forEach { $0() }
        }

        if Thread.isMainThread {
            finish()
        } else {
            DispatchQueue.main.async(execute: finish)
        }
    }

    private func scheduleCookieSnapshot() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.captureCookies()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func captureCookies(completion: @escaping () -> Void = {}) {
        dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else {
                DispatchQueue.main.async(execute: completion)
                return
            }
            let finish = {
                self.profileStore?.recordCookies(cookies, for: self.index)
                DispatchQueue.main.async(execute: completion)
            }
            if !self.persistenceMode.usesPersistentWebsiteDataStore {
                BrowserCookieArchive.save(
                    cookies,
                    profileIndex: self.index,
                    profilesRootDirectory: self.profilesRootDirectory,
                    completion: finish
                )
            } else {
                finish()
            }
        }
    }
}

enum BrowserProfileDirectories {
    static var defaultRootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("BrowserProfiles", isDirectory: true)
    }

    static func profileDirectory(profilesRootDirectory: URL, profileIndex: Int) -> URL {
        profilesRootDirectory.appendingPathComponent(
            String(format: "Profile-%02d", profileIndex),
            isDirectory: true
        )
    }

    static func websiteDataDirectory(profilesRootDirectory: URL, profileIndex: Int) -> URL {
        profileDirectory(
            profilesRootDirectory: profilesRootDirectory,
            profileIndex: profileIndex
        ).appendingPathComponent("WebsiteData", isDirectory: true)
    }

    static func relativeWebsiteDataPath(profileIndex: Int) -> String {
        "Application Support/BrowserProfiles/" +
            String(format: "Profile-%02d/WebsiteData", profileIndex)
    }

    static func profileHasWebsiteData(profilesRootDirectory: URL, profileIndex: Int) -> Bool {
        let url = profileDirectory(
            profilesRootDirectory: profilesRootDirectory,
            profileIndex: profileIndex
        )
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true, (values?.fileSize ?? 0) > 0 {
                return true
            }
        }
        return false
    }
}

enum BrowserCookieArchive {
    private static let ioQueue = DispatchQueue(label: "com.nextsolution.multibrowser.cookie-archive")

    static func load(profileIndex: Int, profilesRootDirectory: URL) -> [HTTPCookie] {
        guard let data = try? Data(contentsOf: fileURL(
            profileIndex: profileIndex,
            profilesRootDirectory: profilesRootDirectory
        )) else {
            return []
        }
        return cookies(from: data)
    }

    static func cookies(from data: Data) -> [HTTPCookie] {
        guard let propertyList = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ), let dictionaries = propertyList as? [[String: Any]] else {
            return []
        }

        let now = Date()
        return dictionaries.compactMap { dictionary in
            var properties: [HTTPCookiePropertyKey: Any] = [:]
            dictionary.forEach { key, value in
                properties[HTTPCookiePropertyKey(rawValue: key)] = value
            }
            guard let cookie = HTTPCookie(properties: properties) else { return nil }
            if let expiresDate = cookie.expiresDate, expiresDate <= now {
                return nil
            }
            return cookie
        }
    }

    static func serializedData(for cookies: [HTTPCookie]) -> Data? {
        let validCookies = cookies.filter { cookie in
            guard let expiresDate = cookie.expiresDate else { return true }
            return expiresDate > Date()
        }

        let dictionaries: [[String: Any]] = validCookies.compactMap { cookie in
            guard let source = cookie.properties else { return nil }
            var destination: [String: Any] = [:]
            source.forEach { key, value in
                switch value {
                case let string as String:
                    destination[key.rawValue] = string
                case let number as NSNumber:
                    destination[key.rawValue] = number
                case let date as Date:
                    destination[key.rawValue] = date
                case let data as Data:
                    destination[key.rawValue] = data
                case let url as URL:
                    destination[key.rawValue] = url.absoluteString
                default:
                    destination[key.rawValue] = String(describing: value)
                }
            }
            return destination
        }

        return try? PropertyListSerialization.data(
            fromPropertyList: dictionaries,
            format: .binary,
            options: 0
        )
    }

    static func save(
        _ cookies: [HTTPCookie],
        profileIndex: Int,
        profilesRootDirectory: URL,
        completion: @escaping () -> Void = {}
    ) {
        guard let data = serializedData(for: cookies) else {
            completion()
            return
        }

        ioQueue.async {
            do {
                try FileManager.default.createDirectory(
                    at: profilesRootDirectory,
                    withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
                )
                let destination = fileURL(
                    profileIndex: profileIndex,
                    profilesRootDirectory: profilesRootDirectory
                )
                try data.write(
                    to: destination,
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
            } catch {
                // The live profile remains usable even if a snapshot cannot be written.
            }
            completion()
        }
    }

    static func remove(
        profileIndex: Int,
        profilesRootDirectory: URL,
        completion: @escaping () -> Void = {}
    ) {
        ioQueue.async {
            try? FileManager.default.removeItem(
                at: fileURL(
                    profileIndex: profileIndex,
                    profilesRootDirectory: profilesRootDirectory
                )
            )
            completion()
        }
    }

    static func fileURL(profileIndex: Int, profilesRootDirectory: URL) -> URL {
        profilesRootDirectory.appendingPathComponent(
            String(format: "Profile-%02d-Cookies.plist", profileIndex)
        )
    }
}
