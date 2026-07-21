import Foundation
import SwiftUI
import Combine
import UserNotifications
import UIKit

// MARK: - ReminderModels
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
        case .never:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
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
        case .atTime: return "Due now"
        case .fiveMinutes: return "Due in 5 minutes"
        case .fifteenMinutes: return "Due in 15 minutes"
        case .thirtyMinutes: return "Due in 30 minutes"
        case .oneHour: return "Due in 1 hour"
        case .threeHours: return "Due in 3 hours"
        case .oneDay: return "Due tomorrow"
        }
    }
}

struct ReminderCategory: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var isProtected: Bool

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "tag.fill",
        colorHex: String = "FF7A00",
        isProtected: Bool = false
    ) {
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
    var dueDate: Date
    var priority: ReminderPriority
    var categoryID: UUID
    var repeatRule: ReminderRepeat
    var alertOffsets: Set<ReminderAlertOffset>
    var notificationsEnabled: Bool
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
        priority: ReminderPriority = .medium,
        categoryID: UUID = ReminderCategory.general.id,
        repeatRule: ReminderRepeat = .never,
        alertOffsets: Set<ReminderAlertOffset> = [.thirtyMinutes],
        notificationsEnabled: Bool = true,
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
        self.priority = priority
        self.categoryID = categoryID
        self.repeatRule = repeatRule
        self.alertOffsets = alertOffsets
        self.notificationsEnabled = notificationsEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.completionComment = completionComment
        self.history = history
    }

    var isCompleted: Bool { completedAt != nil }
    var isOverdue: Bool { !isCompleted && dueDate < Date() }

    func timeRemaining(now: Date = Date()) -> String {
        if isCompleted { return "Completed" }
        let interval = dueDate.timeIntervalSince(now)
        let absolute = abs(interval)
        let prefix = interval < 0 ? "Overdue by " : ""

        if absolute < 60 {
            return interval < 0 ? "Overdue" : "Due now"
        }
        if absolute < 3600 {
            return "\(prefix)\(Int(absolute / 60))m"
        }
        if absolute < 86400 {
            let hours = Int(absolute / 3600)
            let minutes = Int((absolute.truncatingRemainder(dividingBy: 3600)) / 60)
            return minutes > 0 ? "\(prefix)\(hours)h \(minutes)m" : "\(prefix)\(hours)h"
        }
        let days = Int(absolute / 86400)
        return "\(prefix)\(days)d"
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

// MARK: - Color+Hex
extension Color {
    static let nextOrange = Color(red: 1.0, green: 0.43, blue: 0.0)
    static let nextBackground = Color(red: 0.035, green: 0.045, blue: 0.06)
    static let nextCard = Color(red: 0.075, green: 0.085, blue: 0.105)

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

// MARK: - Date+Helpers
extension Date {
    var isToday: Bool { Calendar.current.isDateInToday(self) }
    var isTomorrow: Bool { Calendar.current.isDateInTomorrow(self) }

    var compactDateTime: String {
        if isToday {
            return "Today, \(formatted(date: .omitted, time: .shortened))"
        }
        if isTomorrow {
            return "Tomorrow, \(formatted(date: .omitted, time: .shortened))"
        }
        return formatted(date: .abbreviated, time: .shortened)
    }
}
