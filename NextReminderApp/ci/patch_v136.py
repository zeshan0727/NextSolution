#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:260]!r}")
    path.write_text(text.replace(old, new, 1))


# MARK: - Dedicated protected category for routine presets.
models = SOURCES / "ModelsUtilities.swift"
replace_once(
    models,
    '''    static let general = ReminderCategory(
        id: UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!,
        name: "General",
        icon: "square.grid.2x2.fill",
        colorHex: "FF8A00",
        isProtected: true
    )
}''',
    '''    static let general = ReminderCategory(
        id: UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!,
        name: "General",
        icon: "square.grid.2x2.fill",
        colorHex: "FF8A00",
        isProtected: true
    )

    static let routines = ReminderCategory(
        id: UUID(uuidString: "A1000000-0000-0000-0000-000000000003")!,
        name: "Routine Reminders",
        icon: "clock.arrow.2.circlepath",
        colorHex: "7C5CFC",
        isProtected: true
    )
}'''
)

# MARK: - Routine scheduling window and helper properties.
routine_file = SOURCES / "RoutineReminders.swift"
routine_file.write_text('''import Foundation

enum RoutineWindowSchedule {
    static let startHour = 8
    static let endHour = 23
    static let endMinute = 59
    static let windowText = "8:00 AM–11:59 PM"

    static func normalizedStart(_ date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.date(
            bySettingHour: startHour,
            minute: 0,
            second: 0,
            of: date
        ) ?? date
        let end = calendar.date(
            bySettingHour: endHour,
            minute: endMinute,
            second: 59,
            of: date
        ) ?? date

        if date < start { return start }
        if date <= end { return date }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        return calendar.date(
            bySettingHour: startHour,
            minute: 0,
            second: 0,
            of: tomorrow
        ) ?? tomorrow
    }

    static func nextDate(
        after scheduledDate: Date,
        every hours: Int,
        calendar: Calendar = .current
    ) -> Date {
        let safeHours = min(max(hours, 1), 4)
        let base = normalizedStart(scheduledDate, calendar: calendar)
        let candidate = calendar.date(byAdding: .hour, value: safeHours, to: base) ?? base
        let end = calendar.date(
            bySettingHour: endHour,
            minute: endMinute,
            second: 59,
            of: base
        ) ?? base

        if candidate <= end { return candidate }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: base) ?? candidate
        return calendar.date(
            bySettingHour: startHour,
            minute: 0,
            second: 0,
            of: tomorrow
        ) ?? tomorrow
    }
}

extension ReminderItem {
    var isHourlyRoutine: Bool {
        HourlyRepeatStore.shared.hours(for: id) != nil
    }

    var routineOccurrenceHistory: [ReminderHistoryEntry] {
        history.filter { entry in
            entry.action == .completed && entry.previousDueDate != nil && entry.newDueDate != nil
        }
    }
}
''')

# MARK: - Hourly engine obeys the fixed daytime window.
performance = SOURCES / "PerformanceAndRepeat.swift"
replace_once(
    performance,
    '''        if let hours = HourlyRepeatStore.shared.hours(for: reminder.id) {
            return calendar.date(byAdding: .hour, value: hours, to: date)
        }''',
    '''        if let hours = HourlyRepeatStore.shared.hours(for: reminder.id) {
            return RoutineWindowSchedule.nextDate(
                after: date,
                every: hours,
                calendar: calendar
            )
        }'''
)
replace_once(
    performance,
    '''            return hours == 1 ? "Every hour" : "Every \\(hours) hours"''',
    '''            let interval = hours == 1 ? "Every hour" : "Every \\(hours) hours"
            return "\\(interval) • \\(RoutineWindowSchedule.windowText)"'''
)

# MARK: - Editor presents Routine Reminder as a separate mode and category.
editor = SOURCES / "Editor.swift"
replace_once(
    editor,
    '''                    Button(hours == 1 ? "Every 1 Hour" : "Every \\(hours) Hours") {
                        hourlyRepeatHours = hours
                        repeatRule = .never
                    }''',
    '''                    Button(hours == 1 ? "Every 1 Hour" : "Every \\(hours) Hours") {
                        hourlyRepeatHours = hours
                        repeatRule = .never
                        categoryID = ReminderCategory.routines.id
                    }'''
)
replace_once(
    editor,
    '''                        Text("Hourly Repeat")
                            .font(.subheadline.bold())''',
    '''                        Text("Routine Reminder")
                            .font(.subheadline.bold())'''
)
replace_once(
    editor,
    '''                Text("The next occurrence is created after you complete the current one, using the selected hourly interval from its current due time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)''',
    '''                VStack(alignment: .leading, spacing: 5) {
                    Label("Active daily: 8:00 AM–11:59 PM", systemImage: "sun.and.horizon.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.nextOrange)
                    Text("Completing an alert records only that time slot. The main preset stays active and advances to the next slot. After the final slot, it resumes at 8:00 AM the next day.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Saved automatically under Routine Reminders.")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }'''
)
replace_once(
    editor,
    '''        let finalDeadline = hasDeadline ? deadlineDate : nil

        if var existing = reminder {''',
    '''        let isRoutine = hourlyRepeatHours > 0
        let finalDueDate = isRoutine
            ? RoutineWindowSchedule.normalizedStart(dueDate)
            : dueDate
        let finalDeadline = isRoutine ? nil : (hasDeadline ? deadlineDate : nil)
        let finalCategoryID = isRoutine ? ReminderCategory.routines.id : categoryID

        if var existing = reminder {'''
)
replace_once(editor, '            existing.dueDate = dueDate', '            existing.dueDate = finalDueDate')
replace_once(editor, '            existing.categoryID = categoryID', '            existing.categoryID = finalCategoryID')
replace_once(editor, '                dueDate: dueDate,', '                dueDate: finalDueDate,')
replace_once(editor, '                categoryID: categoryID,', '                categoryID: finalCategoryID,')

# MARK: - Completing a routine occurrence advances the same preset.
services = SOURCES / "Services.swift"
replace_once(
    services,
    '''        let completionDate = Date()
        let cleanedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)

        reminders[index].completedAt = completionDate''',
    '''        let completionDate = Date()
        let cleanedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)

        if let hours = HourlyRepeatStore.shared.hours(for: reminder.id) {
            let scheduledDate = reminders[index].dueDate
            let nextDate = RoutineWindowSchedule.nextDate(
                after: scheduledDate,
                every: hours
            )

            reminders[index].dueDate = nextDate
            reminders[index].deadlineDate = nil
            reminders[index].completedAt = nil
            reminders[index].completionComment = nil
            reminders[index].updatedAt = completionDate
            reminders[index].categoryID = ReminderCategory.routines.id
            reminders[index].history.append(
                ReminderHistoryEntry(
                    action: .completed,
                    date: completionDate,
                    comment: cleanedComment,
                    previousDueDate: scheduledDate,
                    newDueDate: nextDate
                )
            )

            UnattendedReminderTracker.shared.markOpened(reminder.id, at: completionDate)
            persistAndSchedule(reminders[index])
            refreshUnattendedBadge()
            return
        }

        reminders[index].completedAt = completionDate'''
)
replace_once(
    services,
    '''            categories = [.personal, .general]
            lastErrorMessage = "Could not load saved reminders."''',
    '''            categories = [.personal, .general, .routines]
            lastErrorMessage = "Could not load saved reminders."'''
)
replace_once(
    services,
    '''        if !categories.contains(where: { $0.id == ReminderCategory.general.id }) {
            categories.insert(.general, at: min(1, categories.count))
        }
    }''',
    '''        if !categories.contains(where: { $0.id == ReminderCategory.general.id }) {
            categories.insert(.general, at: min(1, categories.count))
        }
        if !categories.contains(where: { $0.id == ReminderCategory.routines.id }) {
            categories.insert(.routines, at: min(2, categories.count))
        }
    }'''
)

# MARK: - Detail screen clearly treats completions as occurrence records.
detail = SOURCES / "Detail.swift"
replace_once(
    detail,
    '''                        informationCard(reminder)
                        actionButtons(reminder)
                        historySection(reminder)''',
    '''                        informationCard(reminder)
                        if reminder.isHourlyRoutine {
                            routineSummaryCard(reminder)
                        }
                        actionButtons(reminder)
                        historySection(reminder)'''
)
replace_once(
    detail,
    '''            Button { isCompleting = true } label: {
                Label("Complete", systemImage: "checkmark.circle.fill")
            }''',
    '''            Button { isCompleting = true } label: {
                Label(
                    reminder.isHourlyRoutine ? "Complete Occurrence" : "Complete",
                    systemImage: "checkmark.circle.fill"
                )
            }'''
)
replace_once(
    detail,
    '''    @ViewBuilder
    private func historySection(_ reminder: ReminderItem) -> some View {''',
    '''    private func routineSummaryCard(_ reminder: ReminderItem) -> some View {
        let hours = HourlyRepeatStore.shared.hours(for: reminder.id) ?? 1
        let completedCount = reminder.routineOccurrenceHistory.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Routine Preset", systemImage: "clock.arrow.2.circlepath")
                    .font(.headline)
                    .foregroundStyle(.nextOrange)
                Spacer()
                Text("ACTIVE")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.14), in: Capsule())
            }
            HStack(spacing: 10) {
                routineMetric(
                    value: hours == 1 ? "1 hr" : "\\(hours) hrs",
                    title: "Interval",
                    symbol: "timer"
                )
                routineMetric(
                    value: "\\(completedCount)",
                    title: "Completed slots",
                    symbol: "checkmark.circle.fill"
                )
            }
            Label("Daily window: \\(RoutineWindowSchedule.windowText)", systemImage: "sun.max.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("Marking complete records only the current scheduled slot. This preset remains active for the next occurrence.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .nextCard()
    }

    private func routineMetric(value: String, title: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.nextOrange)
            Text(value).font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(Color.nextSecondaryFill, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func historySection(_ reminder: ReminderItem) -> some View {'''
)
replace_once(
    detail,
    '''                SectionHeader(title: "History")''',
    '''                SectionHeader(title: reminder.isHourlyRoutine ? "Occurrence History" : "History")'''
)
replace_once(
    detail,
    '''                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !entry.comment.isEmpty {''',
    '''                            if reminder.isHourlyRoutine,
                               entry.action == .completed,
                               let scheduled = entry.previousDueDate {
                                Text("Scheduled \\(scheduled.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Text("Completed \\(entry.date.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !entry.comment.isEmpty {'''
)

# MARK: - Completion sheet wording for one time-slot only.
actions = SOURCES / "CompletedFilterActions.swift"
replace_once(
    actions,
    '''                Text("Complete “\\(reminder.title)”")
                    .font(.title3.bold())
                Text("Add an optional comment explaining the outcome.")''',
    '''                Text(
                    reminder.isHourlyRoutine
                        ? "Complete this occurrence"
                        : "Complete “\\(reminder.title)”"
                )
                    .font(.title3.bold())
                Text(
                    reminder.isHourlyRoutine
                        ? "This records the current \\(reminder.dueDate.formatted(date: .abbreviated, time: .shortened)) slot. The main routine preset will remain active."
                        : "Add an optional comment explaining the outcome."
                )'''
)
replace_once(
    actions,
    '''                Button("Complete Reminder") {
                    store.complete(reminder, comment: comment)''',
    '''                Button(reminder.isHourlyRoutine ? "Complete This Occurrence" : "Complete Reminder") {
                    store.complete(reminder, comment: comment)'''
)

# MARK: - Version metadata.
project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.3.5"', 'CFBundleShortVersionString: "1.3.6"')
project_text = project_text.replace('CFBundleVersion: "15"', 'CFBundleVersion: "16"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.5"', 'MARKETING_VERSION: "1.3.6"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "15"', 'CURRENT_PROJECT_VERSION: "16"')
project.write_text(project_text)

settings = SOURCES / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.3.5 • iOS 16.0+", "Version 1.3.6 • iOS 16.0+"))

for path in SOURCES.glob("*.swift"):
    path.write_text(path.read_text().replace("NextReminder-iOS/1.3.5", "NextReminder-iOS/1.3.6"))

print("Next Reminder v1.3.6 routine preset behavior applied successfully.")
