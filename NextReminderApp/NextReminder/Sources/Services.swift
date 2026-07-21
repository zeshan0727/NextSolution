import Foundation
import SwiftUI
import Combine
import UserNotifications
import UIKit

// MARK: - PersistenceService
struct PersistenceService {
    private let fileManager = FileManager.default
    private let fileName = "NextReminderDatabase.json"

    private var fileURL: URL {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appFolder = supportURL.appendingPathComponent("NextReminder", isDirectory: true)
        try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        return appFolder.appendingPathComponent(fileName)
    }

    func load() throws -> ReminderDatabase {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return ReminderDatabase(reminders: [], categories: [.personal, .general])
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ReminderDatabase.self, from: data)
    }

    func save(_ database: ReminderDatabase) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(database)
        try data.write(to: fileURL, options: [.atomic])
    }
}

// MARK: - NotificationActionCoordinator
struct PendingNotificationAction: Codable {
    enum Kind: String, Codable {
        case complete
        case snooze
    }

    var reminderID: UUID
    var kind: Kind
    var comment: String
}

extension Notification.Name {
    static let nextReminderActionReceived = Notification.Name("nextReminderActionReceived")
}

final class NotificationActionCoordinator {
    static let shared = NotificationActionCoordinator()

    private let defaultsKey = "NextReminder.PendingNotificationAction"

    private init() {}

    func store(_ action: PendingNotificationAction) {
        if let data = try? JSONEncoder().encode(action) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        NotificationCenter.default.post(name: .nextReminderActionReceived, object: nil)
    }

    func consume() -> PendingNotificationAction? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let action = try? JSONDecoder().decode(PendingNotificationAction.self, from: data) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        return action
    }
}

// MARK: - NotificationManager
final class NotificationManager {
    static let shared = NotificationManager()

    static let categoryIdentifier = "NEXT_REMINDER_CATEGORY"
    static let completeActionIdentifier = "NEXT_REMINDER_COMPLETE"
    static let snoozeActionIdentifier = "NEXT_REMINDER_SNOOZE"

    private let center = UNUserNotificationCenter.current()

    private init() {}

    func configureCategories() {
        let complete = UNTextInputNotificationAction(
            identifier: Self.completeActionIdentifier,
            title: "Complete with Comment",
            options: [],
            textInputButtonTitle: "Complete",
            textInputPlaceholder: "Optional completion comment"
        )
        let snooze = UNNotificationAction(
            identifier: Self.snoozeActionIdentifier,
            title: "Snooze 10 Minutes",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [complete, snooze],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func schedule(_ reminder: ReminderItem, categoryName: String) async {
        await cancel(reminderID: reminder.id)
        guard reminder.notificationsEnabled, !reminder.isCompleted else { return }

        for offset in reminder.alertOffsets {
            let fireDate = reminder.dueDate.addingTimeInterval(-offset.seconds)
            guard fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.subtitle = offset.notificationText
            content.body = notificationBody(for: reminder, categoryName: categoryName)
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.threadIdentifier = categoryName
            content.interruptionLevel = reminder.priority == .urgent ? .timeSensitive : .active
            content.userInfo = ["reminderID": reminder.id.uuidString]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = requestIdentifier(reminderID: reminder.id, offset: offset.rawValue)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func scheduleSnooze(reminder: ReminderItem, minutes: Int = 10) async {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.subtitle = "Snoozed reminder"
        content.body = reminder.notes.isEmpty ? "This reminder is due." : reminder.notes
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["reminderID": reminder.id.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        let identifier = "\(reminder.id.uuidString)-snooze-\(Date().timeIntervalSince1970)"
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func cancel(reminderID: UUID) async {
        let prefix = reminderID.uuidString
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func requestIdentifier(reminderID: UUID, offset: Int) -> String {
        "\(reminderID.uuidString)-alert-\(offset)"
    }

    private func notificationBody(for reminder: ReminderItem, categoryName: String) -> String {
        let note = reminder.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty {
            return "\(categoryName) • \(reminder.priority.title) priority"
        }
        return note
    }
}

// MARK: - ReminderStore
@MainActor
final class ReminderStore: ObservableObject {
    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var categories: [ReminderCategory] = []
    @Published var lastErrorMessage: String?

    private let persistence = PersistenceService()
    private var cancellables = Set<AnyCancellable>()

    init() {
        load()
        NotificationCenter.default.publisher(for: .nextReminderActionReceived)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.processPendingNotificationAction() }
            .store(in: &cancellables)
        processPendingNotificationAction()
    }

    var pendingReminders: [ReminderItem] {
        reminders.filter { !$0.isCompleted }.sorted { $0.dueDate < $1.dueDate }
    }

    var completedReminders: [ReminderItem] {
        reminders.filter(\.isCompleted).sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
    }

    func category(for id: UUID) -> ReminderCategory {
        categories.first(where: { $0.id == id }) ?? .general
    }

    func add(_ reminder: ReminderItem) {
        reminders.append(reminder)
        persistAndSchedule(reminder)
    }

    func update(_ reminder: ReminderItem) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        var updated = reminder
        updated.updatedAt = Date()
        reminders[index] = updated
        persistAndSchedule(updated)
    }

    func delete(_ reminder: ReminderItem) {
        reminders.removeAll { $0.id == reminder.id }
        save()
        Task { await NotificationManager.shared.cancel(reminderID: reminder.id) }
    }

    func complete(_ reminder: ReminderItem, comment: String) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        let completionDate = Date()
        let cleanedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        reminders[index].completedAt = completionDate
        reminders[index].completionComment = cleanedComment.isEmpty ? nil : cleanedComment
        reminders[index].updatedAt = completionDate
        reminders[index].history.append(
            ReminderHistoryEntry(
                action: .completed,
                date: completionDate,
                comment: cleanedComment,
                previousDueDate: reminder.dueDate,
                newDueDate: nil
            )
        )

        if let nextDate = reminder.repeatRule.nextDate(after: reminder.dueDate) {
            let nextReminder = ReminderItem(
                title: reminder.title,
                notes: reminder.notes,
                dueDate: nextDate,
                priority: reminder.priority,
                categoryID: reminder.categoryID,
                repeatRule: reminder.repeatRule,
                alertOffsets: reminder.alertOffsets,
                notificationsEnabled: reminder.notificationsEnabled
            )
            reminders.append(nextReminder)
            Task {
                await NotificationManager.shared.schedule(
                    nextReminder,
                    categoryName: category(for: nextReminder.categoryID).name
                )
            }
        }

        save()
        Task { await NotificationManager.shared.cancel(reminderID: reminder.id) }
    }

    func extend(_ reminder: ReminderItem, to newDate: Date, comment: String) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        let cleanedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldDate = reminders[index].dueDate
        reminders[index].dueDate = newDate
        reminders[index].updatedAt = Date()
        reminders[index].history.append(
            ReminderHistoryEntry(
                action: .extended,
                date: Date(),
                comment: cleanedComment,
                previousDueDate: oldDate,
                newDueDate: newDate
            )
        )
        let updated = reminders[index]
        persistAndSchedule(updated)
    }

    func restore(_ reminder: ReminderItem) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[index].completedAt = nil
        reminders[index].completionComment = nil
        reminders[index].updatedAt = Date()
        reminders[index].history.append(
            ReminderHistoryEntry(action: .restored, date: Date(), comment: "", previousDueDate: nil, newDueDate: reminder.dueDate)
        )
        let updated = reminders[index]
        persistAndSchedule(updated)
    }

    func addCategory(name: String, icon: String, colorHex: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        categories.append(ReminderCategory(name: cleaned, icon: icon, colorHex: colorHex))
        save()
    }

    func updateCategory(_ category: ReminderCategory) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[index] = category
        save()
    }

    func deleteCategory(_ category: ReminderCategory) {
        guard !category.isProtected else { return }
        let fallback = ReminderCategory.general.id
        for index in reminders.indices where reminders[index].categoryID == category.id {
            reminders[index].categoryID = fallback
        }
        categories.removeAll { $0.id == category.id }
        save()
    }

    func requestNotificationPermission() async -> Bool {
        await NotificationManager.shared.requestAuthorization()
    }

    private func load() {
        do {
            let database = try persistence.load()
            reminders = database.reminders
            categories = database.categories
            ensureDefaultCategories()
        } catch {
            reminders = []
            categories = [.personal, .general]
            lastErrorMessage = "Could not load saved reminders."
        }
    }

    private func ensureDefaultCategories() {
        if !categories.contains(where: { $0.id == ReminderCategory.personal.id }) {
            categories.insert(.personal, at: 0)
        }
        if !categories.contains(where: { $0.id == ReminderCategory.general.id }) {
            categories.insert(.general, at: min(1, categories.count))
        }
    }

    private func save() {
        do {
            try persistence.save(ReminderDatabase(reminders: reminders, categories: categories))
        } catch {
            lastErrorMessage = "Changes could not be saved."
        }
    }

    private func persistAndSchedule(_ reminder: ReminderItem) {
        save()
        Task {
            await NotificationManager.shared.schedule(
                reminder,
                categoryName: category(for: reminder.categoryID).name
            )
        }
    }

    private func processPendingNotificationAction() {
        guard let action = NotificationActionCoordinator.shared.consume(),
              let reminder = reminders.first(where: { $0.id == action.reminderID }) else { return }

        switch action.kind {
        case .complete:
            complete(reminder, comment: action.comment)
        case .snooze:
            Task { await NotificationManager.shared.scheduleSnooze(reminder: reminder) }
        }
    }
}
