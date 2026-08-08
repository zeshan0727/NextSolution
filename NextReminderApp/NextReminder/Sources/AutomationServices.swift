import Combine
import Foundation
import Security
import SwiftUI
import UIKit
import UserNotifications

struct AutomationPersistence: @unchecked Sendable {
    private let fileManager = FileManager.default

    private var folder: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextReminder", isDirectory: true)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private var databaseURL: URL {
        folder.appendingPathComponent("NextReminderAutomations.json")
    }

    private var mediaFolder: URL {
        let url = folder.appendingPathComponent("AutomationMedia", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func load() throws -> AutomationDatabase {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return AutomationDatabase(automations: [], accounts: [])
        }
        let data = try Data(contentsOf: databaseURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AutomationDatabase.self, from: data)
    }

    func save(_ value: AutomationDatabase) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: databaseURL, options: .atomic)
    }

    func saveImage(_ data: Data) throws -> AutomationMediaAttachment {
        let fileName = "\(UUID().uuidString).jpg"
        try data.write(to: mediaFolder.appendingPathComponent(fileName), options: .atomic)
        return AutomationMediaAttachment(fileName: fileName, byteCount: data.count)
    }

    func url(for media: AutomationMediaAttachment) -> URL {
        mediaFolder.appendingPathComponent(media.fileName)
    }

    func data(for media: AutomationMediaAttachment) -> Data? {
        try? Data(contentsOf: url(for: media))
    }

    func remove(_ media: AutomationMediaAttachment?) {
        guard let media else { return }
        try? fileManager.removeItem(at: url(for: media))
    }
}

enum AutomationKeychain {
    private static let service = "com.nextsolution.nextreminder.automations"
    private static let account = "scheduler-api-key"

    static func save(_ value: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw AutomationError.secureStorage
        }
    }

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func remove() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum AutomationError: LocalizedError {
    case invalidEndpoint
    case server(String)
    case invalidResponse
    case mediaTooLarge
    case secureStorage

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Enter a valid HTTPS automation server address."
        case .server(let message):
            return message
        case .invalidResponse:
            return "The automation server returned an invalid response."
        case .mediaTooLarge:
            return "The image is larger than 10 MB."
        case .secureStorage:
            return "The secure API key could not be saved."
        }
    }
}

struct AutomationCloudClient {
    struct ServerResponse: Decodable {
        var id: String?
        var message: String?
    }

    struct Payload: Encodable {
        var localID: String
        var remoteJobID: String?
        var platform: String
        var mode: String
        var scheduledAt: String
        var timeZone: String
        var repeatRule: String
        var accountType: String?
        var remoteAccountID: String?
        var recipient: String
        var text: String
        var altText: String
        var linkURL: String
        var retryEnabled: Bool
        var maxRetries: Int
        var mediaMimeType: String?
        var mediaBase64: String?
        var publishNow: Bool
    }

    func test(_ configuration: AutomationCloudConfiguration) async throws -> String {
        let request = try makeRequest(configuration, path: "v1/health", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        return (try? JSONDecoder().decode(ServerResponse.self, from: data).message)
            ?? "Connection successful"
    }

    func submit(
        _ automation: SocialAutomation,
        account: AutomationAccount?,
        media: Data?,
        configuration: AutomationCloudConfiguration,
        publishNow: Bool
    ) async throws -> String {
        if let media, media.count > 10_000_000 {
            throw AutomationError.mediaTooLarge
        }

        let path = publishNow ? "v1/automations/publish" : "v1/automations"
        var request = try makeRequest(configuration, path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let formatter = ISO8601DateFormatter()
        let payload = Payload(
            localID: automation.id.uuidString,
            remoteJobID: automation.remoteJobID,
            platform: automation.platform.rawValue,
            mode: automation.deliveryMode.rawValue,
            scheduledAt: formatter.string(from: automation.scheduledAt),
            timeZone: automation.timeZoneIdentifier,
            repeatRule: automation.repeatRule.rawValue,
            accountType: account?.accountType.rawValue,
            remoteAccountID: account?.remoteAccountID,
            recipient: automation.recipient,
            text: automation.contentText,
            altText: automation.altText,
            linkURL: automation.linkURL,
            retryEnabled: automation.retryEnabled,
            maxRetries: automation.maxRetries,
            mediaMimeType: automation.media?.mimeType,
            mediaBase64: media?.base64EncodedString(),
            publishNow: publishNow
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        let result = try JSONDecoder().decode(ServerResponse.self, from: data)
        guard let id = result.id ?? automation.remoteJobID else {
            throw AutomationError.invalidResponse
        }
        return id
    }

    private func makeRequest(
        _ configuration: AutomationCloudConfiguration,
        path: String,
        method: String
    ) throws -> URLRequest {
        guard configuration.isConfigured,
              let baseURL = URL(string: configuration.endpoint),
              baseURL.scheme?.lowercased() == "https" else {
            throw AutomationError.invalidEndpoint
        }

        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("NextReminder-iOS/1.1", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AutomationError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ServerResponse.self, from: data).message)
                ?? "Server request failed (\(http.statusCode))."
            throw AutomationError.server(message)
        }
    }
}

struct PendingAutomationAction: Codable {
    enum Kind: String, Codable {
        case open
        case skip
    }

    var automationID: UUID
    var kind: Kind
}

extension Notification.Name {
    static let nextAutomationAction = Notification.Name("nextAutomationAction")
}

final class AutomationActionCoordinator {
    static let shared = AutomationActionCoordinator()
    private let key = "NextReminder.PendingAutomationAction"

    private init() {}

    func store(_ action: PendingAutomationAction) {
        if let data = try? JSONEncoder().encode(action) {
            UserDefaults.standard.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: .nextAutomationAction, object: nil)
    }

    func consume() -> PendingAutomationAction? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let action = try? JSONDecoder().decode(PendingAutomationAction.self, from: data) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: key)
        return action
    }
}

final class AutomationNotificationCenter {
    static let shared = AutomationNotificationCenter()
    static let category = "NEXT_AUTOMATION_CATEGORY"
    static let openAction = "NEXT_AUTOMATION_OPEN"
    static let skipAction = "NEXT_AUTOMATION_SKIP"

    private let center = UNUserNotificationCenter.current()

    private init() {}

    func install() {
        let complete = UNTextInputNotificationAction(
            identifier: NotificationManager.completeActionIdentifier,
            title: "Complete with Comment",
            options: [],
            textInputButtonTitle: "Complete",
            textInputPlaceholder: "Optional completion comment"
        )
        let snooze = UNNotificationAction(
            identifier: NotificationManager.snoozeActionIdentifier,
            title: "Snooze 10 Minutes",
            options: []
        )
        let reminderCategory = UNNotificationCategory(
            identifier: NotificationManager.categoryIdentifier,
            actions: [complete, snooze],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let open = UNNotificationAction(
            identifier: Self.openAction,
            title: "Review & Publish",
            options: [.foreground]
        )
        let skip = UNNotificationAction(
            identifier: Self.skipAction,
            title: "Skip",
            options: [.destructive]
        )
        let automationCategory = UNNotificationCategory(
            identifier: Self.category,
            actions: [open, skip],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([reminderCategory, automationCategory])
    }

    func schedule(_ automation: SocialAutomation) async {
        await cancel(automation.id)
        guard automation.status != .paused, !automation.status.isFinished else { return }

        for offset in automation.alertOffsets {
            let date = automation.scheduledAt.addingTimeInterval(-offset.seconds)
            guard date > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = automation.title
            content.subtitle = automation.deliveryMode == .automaticCloud
                ? "Automatic \(automation.platform.shortTitle) job"
                : "\(automation.platform.shortTitle) automation is ready"
            content.body = automation.deliveryMode == .automaticCloud
                ? "Open Next Reminder to check the cloud publishing status."
                : "Review the prepared content and publish or send it."
            content.sound = .default
            content.categoryIdentifier = Self.category
            content.threadIdentifier = "automations"
            content.interruptionLevel = .timeSensitive
            content.userInfo = ["automationID": automation.id.uuidString]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: date
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "automation-\(automation.id.uuidString)-\(offset.rawValue)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    func cancel(_ id: UUID) async {
        let prefix = "automation-\(id.uuidString)"
        let requests = await center.pendingNotificationRequests()
        let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

@MainActor
final class AutomationStore: ObservableObject {
    @Published private(set) var automations: [SocialAutomation] = []
    @Published private(set) var accounts: [AutomationAccount] = []
    @Published var lastErrorMessage: String?
    @Published var requestedAutomationID: UUID?
    @Published var connectionMessage: String?
    @Published var isTesting = false

    private let disk = AutomationPersistence()
    private let cloud = AutomationCloudClient()
    private var cancellables = Set<AnyCancellable>()
    private let endpointKey = "NextReminder.AutomationCloudEndpoint"
    private static let saveQueue = DispatchQueue(
        label: "com.nextsolution.nextreminder.automations",
        qos: .utility
    )

    init() {
        do {
            let database = try disk.load()
            automations = database.automations
            accounts = database.accounts
        } catch {
            lastErrorMessage = "Could not load saved automations."
        }

        NotificationCenter.default.publisher(for: .nextAutomationAction)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.processPendingAction() }
            .store(in: &cancellables)

        processPendingAction()
        refreshDueStatuses()
    }

    var cloudEndpoint: String {
        UserDefaults.standard.string(forKey: endpointKey) ?? ""
    }

    var cloudAPIKey: String {
        AutomationKeychain.load()
    }

    var cloudConfiguration: AutomationCloudConfiguration {
        AutomationCloudConfiguration(endpoint: cloudEndpoint, apiKey: cloudAPIKey)
    }

    var active: [SocialAutomation] {
        automations
            .filter { !$0.status.isFinished }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    func automation(_ id: UUID) -> SocialAutomation? {
        automations.first { $0.id == id }
    }

    func account(_ id: UUID?) -> AutomationAccount? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    func compatible(_ platform: AutomationPlatform) -> [AutomationAccount] {
        accounts.filter { $0.accountType.supports(platform) }
    }

    func saveCloud(endpoint: String, key: String) {
        UserDefaults.standard.set(
            endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: endpointKey
        )
        do {
            if key.isEmpty {
                AutomationKeychain.remove()
            } else {
                try AutomationKeychain.save(key)
            }
            connectionMessage = "Configuration saved securely."
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func testCloud(endpoint: String, key: String) async {
        isTesting = true
        defer { isTesting = false }
        do {
            connectionMessage = try await cloud.test(
                AutomationCloudConfiguration(endpoint: endpoint, apiKey: key)
            )
        } catch {
            connectionMessage = error.localizedDescription
        }
    }

    func addAccount(_ account: AutomationAccount) {
        accounts.append(account)
        save()
    }

    func updateAccount(_ account: AutomationAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        save()
    }

    func deleteAccount(_ account: AutomationAccount) {
        for index in automations.indices where automations[index].accountID == account.id {
            automations[index].accountID = nil
            if automations[index].deliveryMode == .automaticCloud {
                automations[index].status = .needsSetup
            }
        }
        accounts.removeAll { $0.id == account.id }
        save()
    }

    func add(_ automation: SocialAutomation, image: Data?) {
        var item = automation
        if let image {
            item.media = try? disk.saveImage(image)
        }
        prepareStatus(for: &item)
        item.history.append(
            AutomationHistoryEntry(date: Date(), status: item.status, comment: "Automation created")
        )
        automations.append(item)
        schedule(item)
    }

    func update(_ automation: SocialAutomation, image: Data?, removeMedia: Bool) {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }
        var item = automation
        let previousMedia = automations[index].media

        if removeMedia {
            disk.remove(previousMedia)
            item.media = nil
        }
        if let image {
            disk.remove(previousMedia)
            item.media = try? disk.saveImage(image)
        }

        item.updatedAt = Date()
        prepareStatus(for: &item)
        item.history.append(
            AutomationHistoryEntry(date: Date(), status: item.status, comment: "Automation updated")
        )
        automations[index] = item
        schedule(item)
    }

    func delete(_ automation: SocialAutomation) {
        automations.removeAll { $0.id == automation.id }
        disk.remove(automation.media)
        save()
        Task { await AutomationNotificationCenter.shared.cancel(automation.id) }
    }

    func duplicate(_ automation: SocialAutomation) {
        var copy = automation
        copy.id = UUID()
        copy.title += " Copy"
        copy.scheduledAt = max(
            Date().addingTimeInterval(3600),
            automation.scheduledAt.addingTimeInterval(3600)
        )
        copy.status = .scheduled
        copy.remoteJobID = nil
        copy.completedAt = nil
        copy.lastError = nil
        copy.retryCount = 0
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.history = [
            AutomationHistoryEntry(date: Date(), status: .scheduled, comment: "Duplicated")
        ]
        if let media = automation.media, let data = disk.data(for: media) {
            copy.media = try? disk.saveImage(data)
        }
        automations.append(copy)
        schedule(copy)
    }

    func pause(_ automation: SocialAutomation) {
        change(automation.id) { item in
            item.status = .paused
            item.history.append(
                AutomationHistoryEntry(date: Date(), status: .paused, comment: "Paused")
            )
        }
        Task { await AutomationNotificationCenter.shared.cancel(automation.id) }
    }

    func resume(_ automation: SocialAutomation) {
        change(automation.id) { item in
            item.status = item.scheduledAt <= Date() ? .awaitingApproval : .scheduled
        }
        if let item = self.automation(automation.id) {
            schedule(item)
        }
    }

    func skip(_ automation: SocialAutomation) {
        finish(automation, status: .skipped, comment: "Skipped")
    }

    func markAssistedComplete(_ automation: SocialAutomation) {
        let status: AutomationStatus = automation.platform == .whatsapp ? .sent : .published
        finish(automation, status: status, comment: "Confirmed after assisted publishing")
    }

    func submit(_ automation: SocialAutomation, publishNow: Bool = false) async {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }

        guard cloudConfiguration.isConfigured else {
            automations[index].status = .needsSetup
            automations[index].lastError = "Connect an HTTPS scheduler in Settings."
            save()
            return
        }

        guard let account = account(automation.accountID),
              account.isReadyForAutomaticPublishing,
              account.accountType.supports(automation.platform) else {
            automations[index].status = .needsSetup
            automations[index].lastError = "Select a compatible automatic account."
            save()
            return
        }

        automations[index].status = .processing
        save()

        do {
            let mediaData = automation.media.flatMap { disk.data(for: $0) }
            let remoteID = try await cloud.submit(
                automations[index],
                account: account,
                media: mediaData,
                configuration: cloudConfiguration,
                publishNow: publishNow
            )
            automations[index].remoteJobID = remoteID

            if publishNow {
                let status: AutomationStatus = automation.platform == .whatsapp ? .sent : .published
                finishAt(index, status: status, comment: "Cloud publisher accepted the request")
            } else {
                automations[index].status = .scheduled
                automations[index].history.append(
                    AutomationHistoryEntry(
                        date: Date(),
                        status: .scheduled,
                        comment: "Cloud schedule accepted"
                    )
                )
                save()
            }
        } catch {
            automations[index].status = .failed
            automations[index].lastError = error.localizedDescription
            automations[index].retryCount += 1
            automations[index].history.append(
                AutomationHistoryEntry(
                    date: Date(),
                    status: .failed,
                    comment: error.localizedDescription
                )
            )
            save()
        }
    }

    func mediaURL(_ automation: SocialAutomation) -> URL? {
        automation.media.map { disk.url(for: $0) }
    }

    func mediaData(_ automation: SocialAutomation) -> Data? {
        automation.media.flatMap { disk.data(for: $0) }
    }

    func refreshDueStatuses() {
        var changed = false
        for index in automations.indices
        where automations[index].status == .scheduled
            && automations[index].scheduledAt <= Date()
            && automations[index].deliveryMode != .automaticCloud {
            automations[index].status = .awaitingApproval
            automations[index].history.append(
                AutomationHistoryEntry(
                    date: Date(),
                    status: .awaitingApproval,
                    comment: "Scheduled time arrived"
                )
            )
            changed = true
        }
        if changed { save() }
    }

    func clearRequested() {
        requestedAutomationID = nil
    }

    private func prepareStatus(for automation: inout SocialAutomation) {
        if automation.deliveryMode == .automaticCloud {
            let selectedAccount = account(automation.accountID)
            let isReady = cloudConfiguration.isConfigured
                && selectedAccount?.isReadyForAutomaticPublishing == true
            automation.status = isReady ? .scheduled : .needsSetup
        } else {
            automation.status = automation.scheduledAt <= Date() ? .awaitingApproval : .scheduled
        }
        automation.lastError = automation.status == .needsSetup
            ? "Complete automatic publishing setup."
            : nil
    }

    private func schedule(_ automation: SocialAutomation) {
        save()
        Task {
            await AutomationNotificationCenter.shared.schedule(automation)
            if automation.deliveryMode == .automaticCloud {
                await submit(automation)
            }
        }
    }

    private func finish(
        _ automation: SocialAutomation,
        status: AutomationStatus,
        comment: String
    ) {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }
        finishAt(index, status: status, comment: comment)
    }

    private func finishAt(_ index: Int, status: AutomationStatus, comment: String) {
        let previous = automations[index]
        automations[index].status = status
        automations[index].completedAt = Date()
        automations[index].updatedAt = Date()
        automations[index].history.append(
            AutomationHistoryEntry(date: Date(), status: status, comment: comment)
        )
        Task { await AutomationNotificationCenter.shared.cancel(previous.id) }

        if let nextDate = previous.repeatRule.nextDate(after: previous.scheduledAt),
           status != .skipped {
            var next = previous
            next.id = UUID()
            next.scheduledAt = nextDate
            next.status = .scheduled
            next.remoteJobID = nil
            next.completedAt = nil
            next.retryCount = 0
            next.createdAt = Date()
            next.updatedAt = Date()
            next.history = [
                AutomationHistoryEntry(
                    date: Date(),
                    status: .scheduled,
                    comment: "Next recurring automation"
                )
            ]
            if let media = previous.media, let data = disk.data(for: media) {
                next.media = try? disk.saveImage(data)
            }
            automations.append(next)
            schedule(next)
        }
        save()
    }

    private func change(_ id: UUID, update: (inout SocialAutomation) -> Void) {
        guard let index = automations.firstIndex(where: { $0.id == id }) else { return }
        update(&automations[index])
        automations[index].updatedAt = Date()
        save()
    }

    private func save() {
        let database = AutomationDatabase(automations: automations, accounts: accounts)
        let persistence = disk
        Self.saveQueue.async {
            try? persistence.save(database)
        }
    }

    private func processPendingAction() {
        guard let action = AutomationActionCoordinator.shared.consume(),
              let automation = automation(action.automationID) else {
            return
        }

        switch action.kind {
        case .skip:
            skip(automation)
        case .open:
            refreshDueStatuses()
            requestedAutomationID = automation.id
        }
    }
}

@MainActor
enum AssistedAutomationPublisher {
    static func text(_ automation: SocialAutomation) -> String {
        [automation.contentText, automation.linkURL]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static func url(_ automation: SocialAutomation) -> URL? {
        let encoded = text(automation)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if automation.platform == .whatsapp, automation.media == nil {
            let number = automation.recipient.filter(\.isNumber)
            return URL(string: "https://wa.me/\(number)?text=\(encoded)")
        }
        if automation.platform == .xPost, automation.media == nil {
            return URL(string: "https://twitter.com/intent/tweet?text=\(encoded)")
        }
        return nil
    }

    static func items(_ automation: SocialAutomation, media: Data?) -> [Any] {
        var items: [Any] = []
        if let media, let image = UIImage(data: media) {
            items.append(image)
        }
        let content = text(automation)
        if !content.isEmpty {
            items.append(content)
        }
        return items
    }
}
