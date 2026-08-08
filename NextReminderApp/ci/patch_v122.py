#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:120]!r}")
    path.write_text(text.replace(old, new, 1))


# MARK: Notification tracking and app-icon badge
services = SOURCES / "Services.swift"
replace_once(
    services,
    "    enum Kind: String, Codable { case complete, snooze }",
    "    enum Kind: String, Codable { case open, complete, snooze }"
)

replace_once(
    services,
    "final class NotificationManager {",
    '''final class UnattendedReminderTracker {
    static let shared = UnattendedReminderTracker()
    private let defaultsKey = "NextReminder.OpenedReminderDates.v1"
    private init() {}

    private var openedDates: [String: Double] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: defaultsKey) ?? [:]
            return raw.reduce(into: [:]) { result, entry in
                if let value = entry.value as? Double {
                    result[entry.key] = value
                } else if let value = entry.value as? NSNumber {
                    result[entry.key] = value.doubleValue
                }
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    func markOpened(_ reminderID: UUID, at date: Date = Date()) {
        var values = openedDates
        values[reminderID.uuidString] = date.timeIntervalSince1970
        openedDates = values
    }

    func wasOpenedAfterDueTime(_ reminder: ReminderItem) -> Bool {
        guard let value = openedDates[reminder.id.uuidString] else { return false }
        return Date(timeIntervalSince1970: value) >= reminder.dueDate
    }

    func remove(_ reminderID: UUID) {
        var values = openedDates
        values.removeValue(forKey: reminderID.uuidString)
        openedDates = values
    }
}

final class NotificationManager {'''
)

replace_once(
    services,
    "            content.sound = .default\n            content.categoryIdentifier = Self.categoryIdentifier",
    "            content.sound = .default\n            content.badge = NSNumber(value: 1)\n            content.categoryIdentifier = Self.categoryIdentifier"
)
replace_once(
    services,
    "        content.sound = .default\n        content.categoryIdentifier = Self.categoryIdentifier",
    "        content.sound = .default\n        content.badge = NSNumber(value: 1)\n        content.categoryIdentifier = Self.categoryIdentifier"
)
replace_once(
    services,
    "    func openSystemSettings() {",
    '''    func clearDelivered(reminderID: UUID) async {
        let prefix = reminderID.uuidString
        let delivered = await center.deliveredNotifications()
        let identifiers = delivered.map(\\.request.identifier).filter { $0.hasPrefix(prefix) }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func openSystemSettings() {'''
)

replace_once(
    services,
    "    @Published private(set) var categories: [ReminderCategory] = []\n    @Published var lastErrorMessage: String?",
    "    @Published private(set) var categories: [ReminderCategory] = []\n    @Published private(set) var unattendedCount = 0\n    @Published var lastErrorMessage: String?"
)
replace_once(
    services,
    "        processPendingNotificationAction()\n\n        let existing = pendingReminders",
    '''        processPendingNotificationAction()

        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshUnattendedBadge() }
            .store(in: &cancellables)
        refreshUnattendedBadge()

        let existing = pendingReminders'''
)
replace_once(
    services,
    "    func category(for id: UUID) -> ReminderCategory {\n        categories.first(where: { $0.id == id }) ?? .general\n    }",
    '''    func category(for id: UUID) -> ReminderCategory {
        categories.first(where: { $0.id == id }) ?? .general
    }

    func isUnattended(_ reminder: ReminderItem, now: Date = Date()) -> Bool {
        guard !reminder.isCompleted, reminder.dueDate <= now else { return false }
        return !UnattendedReminderTracker.shared.wasOpenedAfterDueTime(reminder)
    }

    func markAttended(_ reminder: ReminderItem) {
        UnattendedReminderTracker.shared.markOpened(reminder.id)
        Task { await NotificationManager.shared.clearDelivered(reminderID: reminder.id) }
        refreshUnattendedBadge()
    }

    func refreshUnattendedBadge() {
        unattendedCount = reminders.filter { isUnattended($0) }.count
        UIApplication.shared.applicationIconBadgeNumber = unattendedCount
    }'''
)
replace_once(
    services,
    "        reminders.append(reminder)\n        persistAndSchedule(reminder)",
    "        reminders.append(reminder)\n        persistAndSchedule(reminder)\n        refreshUnattendedBadge()"
)
replace_once(
    services,
    "        reminders[index] = updated\n        persistAndSchedule(updated)",
    "        reminders[index] = updated\n        persistAndSchedule(updated)\n        refreshUnattendedBadge()"
)
replace_once(
    services,
    "        SelectedDayScheduleStore.shared.remove(for: reminder.id)\n    }\n\n    func complete",
    "        SelectedDayScheduleStore.shared.remove(for: reminder.id)\n        UnattendedReminderTracker.shared.remove(reminder.id)\n        refreshUnattendedBadge()\n    }\n\n    func complete"
)
replace_once(
    services,
    "        Task {\n            await NotificationManager.shared.cancel(reminderID: reminder.id)\n            await EmailAutomationManager.shared.cancel(reminderID: reminder.id)\n        }\n    }\n\n    func extend",
    "        Task {\n            await NotificationManager.shared.cancel(reminderID: reminder.id)\n            await EmailAutomationManager.shared.cancel(reminderID: reminder.id)\n        }\n        refreshUnattendedBadge()\n    }\n\n    func extend"
)
replace_once(
    services,
    "        scheduleServices(for: reminder)\n    }",
    "        scheduleServices(for: reminder)\n        refreshUnattendedBadge()\n    }"
)
replace_once(
    services,
    "        switch action.kind {\n        case .complete:",
    "        switch action.kind {\n        case .open:\n            markAttended(reminder)\n        case .complete:"
)

# MARK: Notification response behavior and foreground badges
app = SOURCES / "App.swift"
replace_once(
    app,
    "        completionHandler([.banner, .list, .sound])",
    "        completionHandler([.banner, .list, .sound, .badge])"
)
replace_once(
    app,
    "        default:\n            break",
    '''        default:
            NotificationActionCoordinator.shared.store(
                .init(reminderID: id, kind: .open, comment: "")
            )'''
)
replace_once(
    app,
    "                    automationStore.refreshDueStatuses()",
    "                    automationStore.refreshDueStatuses()\n                    store.refreshUnattendedBadge()"
)

# MARK: In-app notification bubbles
root = SOURCES / "RootReminders.swift"
replace_once(
    root,
    '            .tabItem { Label("Reminders", systemImage: "bell.badge.fill") }\n            .tag(AppTab.reminders)',
    '            .tabItem { Label("Reminders", systemImage: "bell.badge.fill") }\n            .badge(reminderStore.unattendedCount)\n            .tag(AppTab.reminders)'
)
replace_once(
    root,
    "                        .buttonStyle(.plain)\n                        .contextMenu {",
    '''                        .buttonStyle(.plain)
                        .overlay(alignment: .topTrailing) {
                            if store.isUnattended(reminder) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(Color.nextCard, lineWidth: 2))
                                    .offset(x: 2, y: -2)
                            }
                        }
                        .simultaneousGesture(
                            TapGesture().onEnded { store.markAttended(reminder) }
                        )
                        .contextMenu {'''
)
replace_once(
    root,
    "            .frame(width: 48, height: 48)\n        }",
    '''            .frame(width: 48, height: 48)
            .overlay(alignment: .topTrailing) {
                if store.unattendedCount > 0 {
                    Text(store.unattendedCount > 99 ? "99+" : "\\(store.unattendedCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Color.red, in: Capsule())
                        .offset(x: 6, y: -6)
                }
            }
        }'''
)

# MARK: Always email urgent reminders
email_core = SOURCES / "EmailAutomationCore.swift"
replace_once(
    email_core,
    "    static let composeActionIdentifier = \"NEXT_EMAIL_REMINDER_COMPOSE\"",
    "    static let composeActionIdentifier = \"NEXT_EMAIL_REMINDER_COMPOSE\"\n    static let urgentAutoEmailKey = \"NextReminder.EmailUrgentAutomatically\""
)
replace_once(
    email_core,
    '''        guard reminder.emailWhenDue,
              !reminder.isCompleted,
              settings.enabled,
              settings.hasValidRecipient else {''',
    '''        let urgentEmailEnabled = UserDefaults.standard.object(forKey: Self.urgentAutoEmailKey) as? Bool ?? true
        let shouldSendEmail = reminder.emailWhenDue
            || (urgentEmailEnabled && reminder.priority == .urgent)

        guard shouldSendEmail,
              !reminder.isCompleted,
              settings.enabled,
              settings.hasValidRecipient else {'''
)
replace_once(
    email_core,
    'request.setValue("NextReminder-iOS/1.2.1", forHTTPHeaderField: "User-Agent")',
    'request.setValue("NextReminder-iOS/1.2.2", forHTTPHeaderField: "User-Agent")'
)

email_view = SOURCES / "EmailAutomationSettingsView.swift"
replace_once(
    email_view,
    "    @State private var draft = EmailAutomationSettings()",
    "    @State private var draft = EmailAutomationSettings()\n    @AppStorage(EmailAutomationManager.urgentAutoEmailKey) private var urgentEmailAutomatically = true"
)
replace_once(
    email_view,
    "        .onAppear { draft = emailStore.settings }",
    '''        .onAppear { draft = emailStore.settings }
        .onChange(of: urgentEmailAutomatically) { _ in
            reschedulePendingReminders()
        }'''
)
replace_once(
    email_view,
    '''            Toggle("Enable reminder email automation", isOn: $draft.enabled)
                .padding(14)
                .nextCard()
            Text("Each reminder can independently choose whether an email should be prepared or sent at its reminder time.")''',
    '''            Toggle("Enable reminder email automation", isOn: $draft.enabled)
                .padding(14)
                .nextCard()
            Toggle("Always email urgent reminders", isOn: $urgentEmailAutomatically)
                .padding(14)
                .nextCard()
            Text("Urgent reminders are emailed automatically when this option is enabled. Other reminders can independently choose whether an email should be sent at reminder time.")'''
)
replace_once(
    email_view,
    '''    private func saveAndReschedule() {
        emailStore.save(draft)
        let reminders = reminderStore.pendingReminders
        Task {
            for reminder in reminders {
                await EmailAutomationManager.shared.sync(reminder)
            }
        }
    }''',
    '''    private func saveAndReschedule() {
        emailStore.save(draft)
        reschedulePendingReminders()
    }

    private func reschedulePendingReminders() {
        let reminders = reminderStore.pendingReminders
        Task {
            for reminder in reminders {
                await EmailAutomationManager.shared.sync(reminder)
            }
        }
    }'''
)

# MARK: Version metadata
project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.2.1"', 'CFBundleShortVersionString: "1.2.2"')
project_text = project_text.replace('CFBundleVersion: "5"', 'CFBundleVersion: "6"')
project_text = project_text.replace('MARKETING_VERSION: "1.2.1"', 'MARKETING_VERSION: "1.2.2"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "5"', 'CURRENT_PROJECT_VERSION: "6"')
project.write_text(project_text)

settings = SOURCES / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.2.1 • iOS 16.0+", "Version 1.2.2 • iOS 16.0+"))

print("Next Reminder v1.2.2 patches applied successfully.")
