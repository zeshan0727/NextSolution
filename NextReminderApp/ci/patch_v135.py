#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:260]!r}")
    path.write_text(text.replace(old, new, 1))


def regex_once(path: Path, pattern: str, replacement: str) -> None:
    text = path.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"Expected one regex match in {path}, found {count}: {pattern}")
    path.write_text(updated)


# MARK: - Hourly recurrence storage and scheduling engine.
performance = SOURCES / "PerformanceAndRepeat.swift"
replace_once(
    performance,
    '''    func description(for reminder: ReminderItem) -> String {
        guard reminder.repeatRule == .daily else { return reminder.repeatRule.title }''',
    '''    func description(for reminder: ReminderItem) -> String {
        if let hours = HourlyRepeatStore.shared.hours(for: reminder.id) {
            return hours == 1 ? "Every hour" : "Every \\(hours) hours"
        }
        guard reminder.repeatRule == .daily else { return reminder.repeatRule.title }'''
)
replace_once(
    performance,
    '''enum RepeatScheduleEngine {''',
    '''final class HourlyRepeatStore {
    static let shared = HourlyRepeatStore()

    private let defaultsKey = "NextReminder.HourlyRepeatSchedules.v1"
    private let defaults = UserDefaults.standard

    private init() {}

    func hours(for reminderID: UUID?) -> Int? {
        guard let reminderID else { return nil }
        guard let value = load()[reminderID.uuidString], (1...4).contains(value) else { return nil }
        return value
    }

    func save(_ hours: Int, for reminderID: UUID) {
        guard (1...4).contains(hours) else {
            remove(for: reminderID)
            return
        }
        var schedules = load()
        schedules[reminderID.uuidString] = hours
        persist(schedules)
    }

    func remove(for reminderID: UUID) {
        var schedules = load()
        schedules.removeValue(forKey: reminderID.uuidString)
        persist(schedules)
    }

    func copy(from sourceID: UUID, to destinationID: UUID) {
        if let hours = hours(for: sourceID) {
            save(hours, for: destinationID)
        } else {
            remove(for: destinationID)
        }
    }

    private func load() -> [String: Int] {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return value
    }

    private func persist(_ value: [String: Int]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

enum RepeatScheduleEngine {'''
)
replace_once(
    performance,
    '''    static func nextDate(for reminder: ReminderItem, after date: Date, calendar: Calendar = .current) -> Date? {
        guard reminder.repeatRule == .daily else {''',
    '''    static func nextDate(for reminder: ReminderItem, after date: Date, calendar: Calendar = .current) -> Date? {
        if let hours = HourlyRepeatStore.shared.hours(for: reminder.id) {
            return calendar.date(byAdding: .hour, value: hours, to: date)
        }
        guard reminder.repeatRule == .daily else {'''
)


# MARK: - Reminder editor hourly interval controls.
editor = SOURCES / "Editor.swift"
replace_once(
    editor,
    '''    @State private var repeatRule: ReminderRepeat
    @State private var selectedWeekdays: Set<Int>
    @State private var alertOffsets: Set<ReminderAlertOffset>''',
    '''    @State private var repeatRule: ReminderRepeat
    @State private var selectedWeekdays: Set<Int>
    @State private var hourlyRepeatHours: Int
    @State private var alertOffsets: Set<ReminderAlertOffset>'''
)
replace_once(
    editor,
    '''        _selectedWeekdays = State(
            initialValue: SelectedDayScheduleStore.shared.weekdays(for: reminder?.id)
        )
        _alertOffsets = State(initialValue: reminder?.alertOffsets ?? [.thirtyMinutes])''',
    '''        _selectedWeekdays = State(
            initialValue: SelectedDayScheduleStore.shared.weekdays(for: reminder?.id)
        )
        _hourlyRepeatHours = State(
            initialValue: HourlyRepeatStore.shared.hours(for: reminder?.id) ?? 0
        )
        _alertOffsets = State(initialValue: reminder?.alertOffsets ?? [.thirtyMinutes])'''
)
regex_once(
    editor,
    r'''    private var repeatSection: some View \{.*?\n    \}\n\n    private func requestPermissionIfNeeded''',
    '''    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Repeat")

            Menu {
                Button("Selected Days") {
                    repeatRule = .daily
                    hourlyRepeatHours = 0
                }
                ForEach(ReminderRepeat.allCases.filter { $0 != .daily }) { rule in
                    Button(rule.title) {
                        repeatRule = rule
                        hourlyRepeatHours = 0
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "repeat")
                        .foregroundStyle(.nextOrange)
                    Text(repeatRule == .daily ? "Selected Days" : repeatRule.title)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .nextCard()
            }
            .buttonStyle(.plain)

            if repeatRule == .daily && hourlyRepeatHours == 0 {
                SelectedWeekdaysPicker(selection: $selectedWeekdays)
            }

            Menu {
                Button("Off") { hourlyRepeatHours = 0 }
                ForEach(1...4, id: \.self) { hours in
                    Button(hours == 1 ? "Every 1 Hour" : "Every \\(hours) Hours") {
                        hourlyRepeatHours = hours
                        repeatRule = .never
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .foregroundStyle(.nextOrange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Hourly Repeat")
                            .font(.subheadline.bold())
                        Text(
                            hourlyRepeatHours == 0
                                ? "Off"
                                : hourlyRepeatHours == 1
                                    ? "Every 1 hour"
                                    : "Every \\(hourlyRepeatHours) hours"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .nextCard()
            }
            .buttonStyle(.plain)

            if hourlyRepeatHours > 0 {
                Text("The next occurrence is created after you complete the current one, using the selected hourly interval from its current due time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func requestPermissionIfNeeded'''
)
replace_once(
    editor,
    '''            if repeatRule == .daily {
                SelectedDayScheduleStore.shared.save(selectedWeekdays, for: existing.id)
            } else {
                SelectedDayScheduleStore.shared.remove(for: existing.id)
            }
            store.update(existing)''',
    '''            if repeatRule == .daily && hourlyRepeatHours == 0 {
                SelectedDayScheduleStore.shared.save(selectedWeekdays, for: existing.id)
            } else {
                SelectedDayScheduleStore.shared.remove(for: existing.id)
            }
            if hourlyRepeatHours > 0 {
                HourlyRepeatStore.shared.save(hourlyRepeatHours, for: existing.id)
            } else {
                HourlyRepeatStore.shared.remove(for: existing.id)
            }
            store.update(existing)'''
)
replace_once(
    editor,
    '''            if repeatRule == .daily {
                SelectedDayScheduleStore.shared.save(selectedWeekdays, for: newID)
            }
            store.add(newReminder)''',
    '''            if repeatRule == .daily && hourlyRepeatHours == 0 {
                SelectedDayScheduleStore.shared.save(selectedWeekdays, for: newID)
            }
            if hourlyRepeatHours > 0 {
                HourlyRepeatStore.shared.save(hourlyRepeatHours, for: newID)
            }
            store.add(newReminder)'''
)


# MARK: - Copy/remove hourly schedules with reminder lifecycle.
services = SOURCES / "Services.swift"
replace_once(
    services,
    '''        SelectedDayScheduleStore.shared.remove(for: reminder.id)
    }

    func complete''',
    '''        SelectedDayScheduleStore.shared.remove(for: reminder.id)
        HourlyRepeatStore.shared.remove(for: reminder.id)
    }

    func complete'''
)
replace_once(
    services,
    '''            if reminder.repeatRule == .daily {
                SelectedDayScheduleStore.shared.copy(from: reminder.id, to: nextReminder.id)
            }
            reminders.append(nextReminder)''',
    '''            if reminder.repeatRule == .daily {
                SelectedDayScheduleStore.shared.copy(from: reminder.id, to: nextReminder.id)
            }
            HourlyRepeatStore.shared.copy(from: reminder.id, to: nextReminder.id)
            reminders.append(nextReminder)'''
)


# MARK: - Version metadata.
project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.3.4"', 'CFBundleShortVersionString: "1.3.5"')
project_text = project_text.replace('CFBundleVersion: "14"', 'CFBundleVersion: "15"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.4"', 'MARKETING_VERSION: "1.3.5"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "14"', 'CURRENT_PROJECT_VERSION: "15"')
project.write_text(project_text)

settings = SOURCES / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.3.4 • iOS 16.0+", "Version 1.3.5 • iOS 16.0+"))

for path in SOURCES.glob("*.swift"):
    path.write_text(path.read_text().replace("NextReminder-iOS/1.3.4", "NextReminder-iOS/1.3.5"))

print("Next Reminder v1.3.5 hourly repeat feature applied successfully.")
