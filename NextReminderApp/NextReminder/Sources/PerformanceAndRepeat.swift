import Foundation
import SwiftUI

struct ReminderWeekday: Identifiable, Hashable {
    let id: Int
    let shortTitle: String
    let fullTitle: String

    static let all: [ReminderWeekday] = [
        ReminderWeekday(id: 1, shortTitle: "Sun", fullTitle: "Sunday"),
        ReminderWeekday(id: 2, shortTitle: "Mon", fullTitle: "Monday"),
        ReminderWeekday(id: 3, shortTitle: "Tue", fullTitle: "Tuesday"),
        ReminderWeekday(id: 4, shortTitle: "Wed", fullTitle: "Wednesday"),
        ReminderWeekday(id: 5, shortTitle: "Thu", fullTitle: "Thursday"),
        ReminderWeekday(id: 6, shortTitle: "Fri", fullTitle: "Friday"),
        ReminderWeekday(id: 7, shortTitle: "Sat", fullTitle: "Saturday")
    ]
}

final class SelectedDayScheduleStore {
    static let shared = SelectedDayScheduleStore()

    private let defaultsKey = "NextReminder.SelectedDaySchedules.v1"
    private let defaults = UserDefaults.standard
    private let officeWeekdays: Set<Int> = [1, 2, 3, 4, 5]
    private let everyDay: Set<Int> = Set(1...7)

    private init() {}

    func weekdays(for reminderID: UUID?) -> Set<Int> {
        guard let reminderID else { return officeWeekdays }
        let schedules = load()
        guard let stored = schedules[reminderID.uuidString] else {
            // Existing Daily reminders from older versions remain truly daily.
            return everyDay
        }
        return Set(stored)
    }

    func save(_ weekdays: Set<Int>, for reminderID: UUID) {
        var schedules = load()
        schedules[reminderID.uuidString] = weekdays.sorted()
        persist(schedules)
    }

    func remove(for reminderID: UUID) {
        var schedules = load()
        schedules.removeValue(forKey: reminderID.uuidString)
        persist(schedules)
    }

    func copy(from sourceID: UUID, to destinationID: UUID) {
        save(weekdays(for: sourceID), for: destinationID)
    }

    func description(for reminder: ReminderItem) -> String {
        guard reminder.repeatRule == .daily else { return reminder.repeatRule.title }
        let selected = weekdays(for: reminder.id)
        if selected == everyDay { return "Every day" }
        if selected == officeWeekdays { return "Sun–Thu" }
        return ReminderWeekday.all
            .filter { selected.contains($0.id) }
            .map(\.shortTitle)
            .joined(separator: ", ")
    }

    private func load() -> [String: [Int]] {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode([String: [Int]].self, from: data) else {
            return [:]
        }
        return value
    }

    private func persist(_ value: [String: [Int]]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

enum RepeatScheduleEngine {
    static func nextDate(for reminder: ReminderItem, after date: Date, calendar: Calendar = .current) -> Date? {
        guard reminder.repeatRule == .daily else {
            return reminder.repeatRule.nextDate(after: date, calendar: calendar)
        }

        let selected = SelectedDayScheduleStore.shared.weekdays(for: reminder.id)
        guard !selected.isEmpty else { return nil }

        for dayOffset in 1...14 {
            guard let candidate = calendar.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            let weekday = calendar.component(.weekday, from: candidate)
            if selected.contains(weekday) { return candidate }
        }
        return nil
    }
}

struct SelectedWeekdaysPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose the days this reminder should repeat")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
                ForEach(ReminderWeekday.all) { day in
                    Button {
                        if selection.contains(day.id) {
                            selection.remove(day.id)
                        } else {
                            selection.insert(day.id)
                        }
                    } label: {
                        Text(day.shortTitle)
                            .font(.caption.bold())
                            .foregroundStyle(selection.contains(day.id) ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selection.contains(day.id) ? Color.nextOrange : Color.nextCard)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.fullTitle)
                }
            }

            HStack {
                Button("Office days") { selection = [1, 2, 3, 4, 5] }
                Spacer()
                Button("Every day") { selection = Set(1...7) }
            }
            .font(.caption.bold())
        }
    }
}

struct WorkweekPerformanceMetrics {
    let completedToday: Int
    let completedThisWeek: Int
    let onTimeThisWeek: Int
    let dailyCounts: [Int]
    let weekStart: Date
    let weekEnd: Date

    var onTimeRate: Int {
        guard completedThisWeek > 0 else { return 0 }
        return Int((Double(onTimeThisWeek) / Double(completedThisWeek) * 100).rounded())
    }

    var systemComment: String {
        guard completedThisWeek > 0 else {
            return "No completed tasks are recorded for this workweek yet. Start with one priority task to build momentum."
        }

        if onTimeRate < 50 {
            return "You are completing tasks, but several were finished after their deadlines. Focus on urgent items earlier in the day."
        }

        switch completedThisWeek {
        case 1...2:
            return "A steady start. Completing another priority task will improve your Sunday–Thursday momentum."
        case 3...5:
            return "Good progress this workweek. Your completion pace is consistent and most finished tasks are on time."
        case 6...9:
            return "Strong performance. You are maintaining good productivity across the office workweek."
        default:
            return "Excellent productivity. You completed a high number of tasks with strong deadline discipline."
        }
    }

    static func calculate(from reminders: [ReminderItem], now: Date = Date()) -> WorkweekPerformanceMetrics {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        let todayStart = calendar.startOfDay(for: now)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let weekday = calendar.component(.weekday, from: todayStart)
        let daysSinceSunday = weekday - 1
        let weekStart = calendar.date(byAdding: .day, value: -daysSinceSunday, to: todayStart) ?? todayStart
        let weekEnd = calendar.date(byAdding: .day, value: 5, to: weekStart) ?? todayEnd

        let completed = reminders.compactMap { reminder -> (ReminderItem, Date)? in
            guard let date = reminder.completedAt else { return nil }
            return (reminder, date)
        }

        let completedToday = completed.filter { $0.1 >= todayStart && $0.1 < todayEnd }.count
        let workweekCompleted = completed.filter { $0.1 >= weekStart && $0.1 < weekEnd }
        let onTime = workweekCompleted.filter { $0.1 <= $0.0.effectiveDeadline }.count

        let dailyCounts = (0..<5).map { offset -> Int in
            let start = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? weekEnd
            return workweekCompleted.filter { $0.1 >= start && $0.1 < end }.count
        }

        return WorkweekPerformanceMetrics(
            completedToday: completedToday,
            completedThisWeek: workweekCompleted.count,
            onTimeThisWeek: onTime,
            dailyCounts: dailyCounts,
            weekStart: weekStart,
            weekEnd: weekEnd
        )
    }
}

struct WorkweekPerformanceCard: View {
    @EnvironmentObject private var store: ReminderStore

    private var metrics: WorkweekPerformanceMetrics {
        WorkweekPerformanceMetrics.calculate(from: store.reminders)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Performance Summary")
                        .font(.headline)
                    Text("Office week: Sunday–Thursday")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.nextOrange)
            }

            HStack(spacing: 10) {
                metricBox(value: metrics.completedToday, title: "Today", symbol: "checkmark.circle.fill")
                metricBox(value: metrics.completedThisWeek, title: "This week", symbol: "calendar.badge.checkmark")
                metricBox(value: metrics.onTimeRate, title: "On time %", symbol: "clock.badge.checkmark.fill")
            }

            HStack(spacing: 8) {
                ForEach(Array(zip(ReminderWeekday.all.prefix(5), metrics.dailyCounts)), id: \.0.id) { day, count in
                    VStack(spacing: 6) {
                        Text("\(count)")
                            .font(.subheadline.bold())
                        Text(day.shortTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.nextSecondaryFill, in: RoundedRectangle(cornerRadius: 10))
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Label("System evaluation", systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(.nextOrange)
                Text(metrics.systemComment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.nextOrange.opacity(0.14), Color.nextCard],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.nextOrange.opacity(0.18), lineWidth: 1)
        )
    }

    private func metricBox(value: Int, title: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.nextOrange)
            Text("\(value)")
                .font(.title3.bold())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.nextSecondaryFill, in: RoundedRectangle(cornerRadius: 12))
    }
}
