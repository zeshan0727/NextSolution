import Foundation
import SwiftUI
import UIKit

enum ReminderPriority: String, Codable, CaseIterable, Identifiable {
    case urgent
    case medium
    case low

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .urgent: return "exclamationmark.triangle.fill"
        case .medium: return "clock.fill"
        case .low: return "leaf.fill"
        }
    }

    var color: Color {
        switch self {
        case .urgent: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }
}

enum ReminderUrgency: String, CaseIterable, Identifiable {
    case criticalOverdue
    case overdue
    case urgent
    case dueToday
    case dueSoon
    case upcoming
    case planned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .criticalOverdue: return "Overdue > 1 day"
        case .overdue: return "Overdue"
        case .urgent: return "Urgent"
        case .dueToday: return "Due today"
        case .dueSoon: return "Due within 24h"
        case .upcoming: return "Upcoming"
        case .planned: return "Planned"
        }
    }

    var symbol: String {
        switch self {
        case .criticalOverdue: return "exclamationmark.octagon.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        case .urgent: return "flame.fill"
        case .dueToday: return "sun.max.fill"
        case .dueSoon: return "clock.badge.exclamationmark.fill"
        case .upcoming: return "calendar.badge.clock"
        case .planned: return "calendar.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .criticalOverdue: return Color(red: 0.82, green: 0.04, blue: 0.10)
        case .overdue: return Color(red: 0.96, green: 0.20, blue: 0.14)
        case .urgent: return Color(red: 0.95, green: 0.10, blue: 0.28)
        case .dueToday: return .orange
        case .dueSoon: return Color(red: 0.93, green: 0.68, blue: 0.03)
        case .upcoming: return Color(red: 0.10, green: 0.70, blue: 0.42)
        case .planned: return Color(red: 0.12, green: 0.50, blue: 0.96)
        }
    }
}

enum ReminderRepeat: String, Codable, CaseIterable, Identifiable {
    case never
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .never: return nil
        case .daily: return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly: return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly: return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}

enum ReminderAlertOffset: Int, Codable, CaseIterable, Identifiable, Hashable {
    case atTime = 0
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case oneHour = 3600
    case threeHours = 10800
    case oneDay = 86400

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var title: String {
        switch self {
        case .atTime: return "At time"
        case .fiveMinutes: return "5 min"
        case .fifteenMinutes: return "15 min"
        case .thirtyMinutes: return "30 min"
        case .oneHour: return "1 hour"
        case .threeHours: return "3 hours"
        case .oneDay: return "1 day"
        }
    }

    var notificationText: String {
        switch self {
        case .atTime: return "Reminder time"
        case .fiveMinutes: return "Reminder in 5 minutes"
        case .fifteenMinutes: return "Reminder in 15 minutes"
        case .thirtyMinutes: return "Reminder in 30 minutes"
        case .oneHour: return "Reminder in 1 hour"
        case .threeHours: return "Reminder in 3 hours"
        case .oneDay: return "Reminder tomorrow"
        }
    }
}

struct ReminderCategory: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var isProtected: Bool

    init(id: UUID = UUID(), name: String, icon: String = "tag.fill", colorHex: String = "FF7A00", isProtected: Bool = false) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.isProtected = isProtected
    }

    static let personal = ReminderCategory(
        id: UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!,
        name: "Personal",
        icon: "person.fill",
        colorHex: "32C76A",
        isProtected: true
    )

    static let general = ReminderCategory(
        id: UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!,
        name: "General",
        icon: "square.grid.2x2.fill",
        colorHex: "FF8A00",
        isProtected: true
    )
}

struct ReminderHistoryEntry: Identifiable, Codable, Hashable {
    enum Action: String, Codable {
        case extended
        case completed
        case restored
    }

    var id: UUID = UUID()
    var action: Action
    var date: Date
    var comment: String
    var previousDueDate: Date?
    var newDueDate: Date?
}

struct ReminderItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var notes: String
    /// The time at which the reminder alert and optional email should occur.
    var dueDate: Date
    /// Optional final completion deadline, which can be later than the reminder time.
    var deadlineDate: Date?
    var priority: ReminderPriority
    var categoryID: UUID
    var repeatRule: ReminderRepeat
    var alertOffsets: Set<ReminderAlertOffset>
    var notificationsEnabled: Bool
    var emailWhenDue: Bool
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var completionComment: String?
    var history: [ReminderHistoryEntry]

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueDate: Date,
        deadlineDate: Date? = nil,
        priority: ReminderPriority = .medium,
        categoryID: UUID = ReminderCategory.general.id,
        repeatRule: ReminderRepeat = .never,
        alertOffsets: Set<ReminderAlertOffset> = [.thirtyMinutes],
        notificationsEnabled: Bool = true,
        emailWhenDue: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        completionComment: String? = nil,
        history: [ReminderHistoryEntry] = []
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.deadlineDate = deadlineDate
        self.priority = priority
        self.categoryID = categoryID
        self.repeatRule = repeatRule
        self.alertOffsets = alertOffsets
        self.notificationsEnabled = notificationsEnabled
        self.emailWhenDue = emailWhenDue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.completionComment = completionComment
        self.history = history
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, dueDate, deadlineDate, priority, categoryID, repeatRule
        case alertOffsets, notificationsEnabled, emailWhenDue, createdAt, updatedAt
        case completedAt, completionComment, history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        dueDate = try container.decode(Date.self, forKey: .dueDate)
        deadlineDate = try container.decodeIfPresent(Date.self, forKey: .deadlineDate)
        priority = try container.decodeIfPresent(ReminderPriority.self, forKey: .priority) ?? .medium
        categoryID = try container.decodeIfPresent(UUID.self, forKey: .categoryID) ?? ReminderCategory.general.id
        repeatRule = try container.decodeIfPresent(ReminderRepeat.self, forKey: .repeatRule) ?? .never
        alertOffsets = try container.decodeIfPresent(Set<ReminderAlertOffset>.self, forKey: .alertOffsets) ?? [.thirtyMinutes]
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        emailWhenDue = try container.decodeIfPresent(Bool.self, forKey: .emailWhenDue) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        completionComment = try container.decodeIfPresent(String.self, forKey: .completionComment)
        history = try container.decodeIfPresent([ReminderHistoryEntry].self, forKey: .history) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(deadlineDate, forKey: .deadlineDate)
        try container.encode(priority, forKey: .priority)
        try container.encode(categoryID, forKey: .categoryID)
        try container.encode(repeatRule, forKey: .repeatRule)
        try container.encode(alertOffsets, forKey: .alertOffsets)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(emailWhenDue, forKey: .emailWhenDue)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(completionComment, forKey: .completionComment)
        try container.encode(history, forKey: .history)
    }

    var isCompleted: Bool { completedAt != nil }
    var effectiveDeadline: Date { deadlineDate ?? dueDate }
    var isOverdue: Bool { !isCompleted && effectiveDeadline < Date() }
    var urgency: ReminderUrgency { urgency(at: Date()) }

    func urgency(at now: Date) -> ReminderUrgency {
        guard !isCompleted else { return .planned }
        let interval = effectiveDeadline.timeIntervalSince(now)
        if interval < -86_400 { return .criticalOverdue }
        if interval < 0 { return .overdue }
        if priority == .urgent { return .urgent }
        if Calendar.current.isDateInToday(effectiveDeadline) { return .dueToday }
        if interval <= 86_400 { return .dueSoon }
        if interval <= 259_200 { return .upcoming }
        return .planned
    }

    func timeRemaining(now: Date = Date()) -> String {
        if isCompleted { return "Completed" }
        return Self.remainingText(until: effectiveDeadline, now: now)
    }

    func reminderTimeRemaining(now: Date = Date()) -> String {
        Self.remainingText(until: dueDate, now: now)
    }

    private static func remainingText(until date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        let absolute = abs(interval)
        let prefix = interval < 0 ? "Overdue by " : ""
        if absolute < 60 { return interval < 0 ? "Overdue" : "Due now" }
        if absolute < 3600 { return "\(prefix)\(Int(absolute / 60))m" }
        if absolute < 86_400 {
            let hours = Int(absolute / 3600)
            let minutes = Int((absolute.truncatingRemainder(dividingBy: 3600)) / 60)
            return minutes > 0 ? "\(prefix)\(hours)h \(minutes)m" : "\(prefix)\(hours)h"
        }
        return "\(prefix)\(Int(absolute / 86_400))d"
    }
}

struct ReminderDatabase: Codable {
    var reminders: [ReminderItem]
    var categories: [ReminderCategory]
}

enum AppThemeMode: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .system: return "iphone"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

extension Color {
    static let nextOrange = Color(red: 1.0, green: 0.43, blue: 0.0)

    static let nextBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.035, green: 0.045, blue: 0.060, alpha: 1.0)
            : UIColor(red: 0.962, green: 0.970, blue: 0.982, alpha: 1.0)
    })

    static let nextCard = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.085, blue: 0.105, alpha: 1.0)
            : UIColor.white
    })

    static let nextCardBorder = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.06)
            : UIColor(red: 0.874, green: 0.898, blue: 0.933, alpha: 1.0)
    })

    static let nextSecondaryFill = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.04)
            : UIColor(red: 0.945, green: 0.955, blue: 0.972, alpha: 1.0)
    })

    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red, green, blue, alpha: UInt64
        switch sanitized.count {
        case 3:
            (red, green, blue, alpha) = (((value >> 8) * 17), ((value >> 4 & 0xF) * 17), ((value & 0xF) * 17), 255)
        case 6:
            (red, green, blue, alpha) = (value >> 16, value >> 8 & 0xFF, value & 0xFF, 255)
        case 8:
            (red, green, blue, alpha) = (value >> 24, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default:
            (red, green, blue, alpha) = (255, 122, 0, 255)
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}

extension Date {
    var isToday: Bool { Calendar.current.isDateInToday(self) }
    var isTomorrow: Bool { Calendar.current.isDateInTomorrow(self) }

    var compactDateTime: String {
        if isToday { return "Today, \(formatted(date: .omitted, time: .shortened))" }
        if isTomorrow { return "Tomorrow, \(formatted(date: .omitted, time: .shortened))" }
        return formatted(date: .abbreviated, time: .shortened)
    }
}
