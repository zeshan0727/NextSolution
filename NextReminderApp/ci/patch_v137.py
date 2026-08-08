#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:260]!r}")
    path.write_text(text.replace(old, new, 1))


services = SOURCES / "Services.swift"

# Routine presets must always alert at the actual occurrence time.
replace_once(
    services,
    '''        for offset in reminder.alertOffsets {
            let fireDate = reminder.dueDate.addingTimeInterval(-offset.seconds)''',
    '''        var effectiveOffsets = reminder.alertOffsets
        if reminder.isHourlyRoutine {
            effectiveOffsets.insert(.atTime)
        }

        for offset in effectiveOffsets {
            let fireDate = reminder.dueDate.addingTimeInterval(-offset.seconds)'''
)

replace_once(
    services,
    '''            guard fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()''',
    '''            let content = UNMutableNotificationContent()'''
)

replace_once(
    services,
    '''            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = requestIdentifier(reminderID: reminder.id, offset: offset.rawValue)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)''',
    '''            let trigger: UNNotificationTrigger
            if fireDate > Date() {
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: fireDate
                )
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            } else if reminder.isHourlyRoutine && offset == .atTime {
                // Restore an already-due routine alert immediately when an app
                // update/reinstall cleared the previous pending request.
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            } else {
                continue
            }

            let identifier = requestIdentifier(reminderID: reminder.id, offset: offset.rawValue)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)'''
)

# Rebuild local notification requests on every app launch. TrollStore over-installs
# may preserve reminder data while removing iOS pending notification requests.
replace_once(
    services,
    '''        let existing = pendingReminders
        Task {
            for reminder in existing {
                await EmailAutomationManager.shared.sync(reminder)
            }
        }''',
    '''        let existing = pendingReminders
        let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        Task {
            let status = await NotificationManager.shared.authorizationStatus()
            if status == .notDetermined {
                _ = await NotificationManager.shared.requestAuthorization()
            }

            for reminder in existing {
                await NotificationManager.shared.schedule(
                    reminder,
                    categoryName: categoryNames[reminder.categoryID] ?? ReminderCategory.general.name
                )
                await EmailAutomationManager.shared.sync(reminder)
            }
        }'''
)

project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.3.6"', 'CFBundleShortVersionString: "1.3.7"')
project_text = project_text.replace('CFBundleVersion: "16"', 'CFBundleVersion: "17"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.6"', 'MARKETING_VERSION: "1.3.7"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "16"', 'CURRENT_PROJECT_VERSION: "17"')
project.write_text(project_text)

settings = SOURCES / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.3.6 • iOS 16.0+", "Version 1.3.7 • iOS 16.0+"))

for path in SOURCES.glob("*.swift"):
    path.write_text(path.read_text().replace("NextReminder-iOS/1.3.6", "NextReminder-iOS/1.3.7"))

print("Next Reminder v1.3.7 notification reliability patch applied successfully.")
