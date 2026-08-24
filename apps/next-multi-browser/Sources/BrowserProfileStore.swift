import Foundation
import WebKit

extension Notification.Name {
    static let nextMultiBrowserProfileDidChange = Notification.Name("NextMultiBrowserProfileDidChange")
}

struct BrowserProfileSnapshot {
    let index: Int
    let displayName: String
    let cookieCount: Int
    let hasGoogleSession: Bool
    let lastUpdated: Date?

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

final class BrowserProfileStore {
    static let shared = BrowserProfileStore()
    static let profileCount = 20

    private let defaults = UserDefaults.standard
    private var sessions: [Int: BrowserProfileSession] = [:]

    private init() {}

    func session(for index: Int) -> BrowserProfileSession {
        precondition((1...Self.profileCount).contains(index))
        if let session = sessions[index] {
            return session
        }

        let session = BrowserProfileSession(
            index: index,
            persistentIdentifier: persistentIdentifier(for: index),
            profileStore: self
        )
        sessions[index] = session
        return session
    }

    func snapshot(for index: Int) -> BrowserProfileSnapshot {
        BrowserProfileSnapshot(
            index: index,
            displayName: displayName(for: index),
            cookieCount: defaults.integer(forKey: cookieCountKey(for: index)),
            hasGoogleSession: defaults.bool(forKey: googleSessionKey(for: index)),
            lastUpdated: defaults.object(forKey: lastUpdatedKey(for: index)) as? Date
        )
    }

    func displayName(for index: Int) -> String {
        let saved = defaults.string(forKey: displayNameKey(for: index))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return saved?.isEmpty == false ? saved! : "Browser \(index)"
    }

    func setDisplayName(_ name: String, for index: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Browser \(index)" {
            defaults.removeObject(forKey: displayNameKey(for: index))
        } else {
            defaults.set(trimmed, forKey: displayNameKey(for: index))
        }
        postProfileChanged(index)
    }

    func setLastURL(_ url: URL, for index: Int) {
        guard url.scheme == "http" || url.scheme == "https" else { return }
        defaults.set(url.absoluteString, forKey: lastURLKey(for: index))
    }

    func lastURL(for index: Int) -> URL? {
        guard let value = defaults.string(forKey: lastURLKey(for: index)) else { return nil }
        return URL(string: value)
    }

    func clearProfile(_ index: Int, completion: @escaping () -> Void) {
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
                self.postProfileChanged(index)
                completion()
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

    fileprivate func recordCookies(_ cookies: [HTTPCookie], for index: Int) {
        defaults.set(cookies.count, forKey: cookieCountKey(for: index))
        defaults.set(Self.containsGoogleSession(cookies), forKey: googleSessionKey(for: index))
        defaults.set(Date(), forKey: lastUpdatedKey(for: index))
        postProfileChanged(index)
    }

    private func persistentIdentifier(for index: Int) -> UUID {
        let key = "NextMultiBrowser.profile.\(index).websiteDataStoreIdentifier"
        if let value = defaults.string(forKey: key), let identifier = UUID(uuidString: value) {
            return identifier
        }

        let identifier = UUID()
        defaults.set(identifier.uuidString, forKey: key)
        return identifier
    }

    private func postProfileChanged(_ index: Int) {
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

    private func displayNameKey(for index: Int) -> String {
        "NextMultiBrowser.profile.\(index).displayName"
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

    private func lastURLKey(for index: Int) -> String {
        "NextMultiBrowser.profile.\(index).lastURL"
    }
}

final class BrowserProfileSession: NSObject, WKHTTPCookieStoreObserver {
    let index: Int
    let dataStore: WKWebsiteDataStore
    let processPool = WKProcessPool()
    let usesNativePersistentStore: Bool

    private weak var profileStore: BrowserProfileStore?
    private var readyBlocks: [() -> Void] = []
    private var isReady = false
    private var saveWorkItem: DispatchWorkItem?

    init(index: Int, persistentIdentifier: UUID, profileStore: BrowserProfileStore) {
        self.index = index
        self.profileStore = profileStore

        if #available(iOS 17.0, *) {
            dataStore = WKWebsiteDataStore(forIdentifier: persistentIdentifier)
            usesNativePersistentStore = true
        } else {
            dataStore = WKWebsiteDataStore.nonPersistent()
            usesNativePersistentStore = false
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
            if self.usesNativePersistentStore {
                finish()
            } else {
                BrowserCookieArchive.remove(profileIndex: self.index, completion: finish)
            }
        }
    }

    private func restoreCookiesIfNeeded() {
        guard !usesNativePersistentStore else {
            finishPreparing()
            captureCookies()
            return
        }

        let cookies = BrowserCookieArchive.load(profileIndex: index)
        guard !cookies.isEmpty else {
            finishPreparing()
            profileStore?.recordCookies([], for: index)
            return
        }

        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            dataStore.httpCookieStore.setCookie(cookie) {
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.profileStore?.recordCookies(cookies, for: self.index)
            self.finishPreparing()
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
            if !self.usesNativePersistentStore {
                BrowserCookieArchive.save(cookies, profileIndex: self.index, completion: finish)
            } else {
                finish()
            }
        }
    }
}

private enum BrowserCookieArchive {
    private static let ioQueue = DispatchQueue(label: "com.nextsolution.multibrowser.cookie-archive")

    static func load(profileIndex: Int) -> [HTTPCookie] {
        guard let data = try? Data(contentsOf: fileURL(profileIndex: profileIndex)),
              let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionaries = propertyList as? [[String: Any]] else {
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

    static func save(_ cookies: [HTTPCookie], profileIndex: Int, completion: @escaping () -> Void = {}) {
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

        ioQueue.async {
            do {
                let directory = directoryURL()
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
                )
                let data = try PropertyListSerialization.data(
                    fromPropertyList: dictionaries,
                    format: .binary,
                    options: 0
                )
                let destination = fileURL(profileIndex: profileIndex)
                try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                // The live profile remains usable even if a snapshot cannot be written.
            }
            completion()
        }
    }

    static func remove(profileIndex: Int, completion: @escaping () -> Void = {}) {
        ioQueue.async {
            try? FileManager.default.removeItem(at: fileURL(profileIndex: profileIndex))
            completion()
        }
    }

    private static func directoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("BrowserProfiles", isDirectory: true)
    }

    private static func fileURL(profileIndex: Int) -> URL {
        directoryURL().appendingPathComponent(String(format: "Profile-%02d-Cookies.plist", profileIndex))
    }
}
