import Foundation
import UserNotifications

extension Notification.Name {
    static let nextQuickReminderImportResult = Notification.Name("NextReminder.QuickImportResult")
}

private struct QuickReminderPayload: Decodable {
    var version: Int?
    var requestID: String?
    var title: String
    var notes: String?
    var dueTimestamp: TimeInterval
    var notificationsEnabled: Bool
    var emailWhenDue: Bool
    var repeatMode: String
    var source: String?
}

@MainActor
enum QuickReminderImporter {
    private static let processedKey = "NextReminder.ProcessedQuickReminderRequests.v1"

    static func handle(_ url: URL, store: ReminderStore) async {
        guard url.scheme?.lowercased() == "nextreminder",
              url.host?.lowercased() == "quick-add" else {
            return
        }

        do {
            let payload = try decodePayload(from: url)
            let requestID = payload.requestID?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let requestID, !requestID.isEmpty, wasProcessed(requestID) {
                post("This quick reminder was already added.")
                return
            }

            let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw QuickReminderImportError.invalidTitle
            }

            let notes = (payload.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let dueDate = Date(timeIntervalSince1970: payload.dueTimestamp)
            guard dueDate.timeIntervalSinceNow > 3 else {
                throw QuickReminderImportError.invalidDate
            }

            var notificationWarning: String?
            if payload.notificationsEnabled {
                let status = await NotificationManager.shared.authorizationStatus()
                if status == .notDetermined {
                    let granted = await store.requestNotificationPermission()
                    if !granted {
                        notificationWarning = "iPhone notification permission was not granted."
                    }
                } else if status == .denied {
                    notificationWarning = "iPhone notifications are disabled for Next Reminder."
                }
            }

            let emailSettings = EmailAutomationSettings.load()
            let emailEnabled = payload.emailWhenDue && emailSettings.fullyConfigured
            let id = UUID()
            let repeatConfiguration = repeatConfiguration(for: payload.repeatMode)

            if let hourly = repeatConfiguration.hourlyHours {
                HourlyRepeatStore.shared.save(hourly, for: id)
            }
            if repeatConfiguration.rule == .daily {
                SelectedDayScheduleStore.shared.save(Set(1...7), for: id)
            }

            let reminder = ReminderItem(
                id: id,
                title: title,
                notes: notes,
                dueDate: dueDate,
                priority: .medium,
                categoryID: repeatConfiguration.hourlyHours == nil
                    ? ReminderCategory.general.id
                    : ReminderCategory.routines.id,
                repeatRule: repeatConfiguration.rule,
                alertOffsets: payload.notificationsEnabled ? [.atTime] : [],
                notificationsEnabled: payload.notificationsEnabled,
                emailWhenDue: emailEnabled
            )

            store.add(reminder)
            if let requestID, !requestID.isEmpty {
                rememberProcessed(requestID)
            }

            var details = "“\(title)” scheduled for \(dueDate.formatted(date: .abbreviated, time: .shortened))."
            if payload.emailWhenDue && !emailEnabled {
                details += " Email was not enabled because Email Reminder Automations is not fully connected."
            }
            if let notificationWarning {
                details += " \(notificationWarning)"
            }
            post(details)
        } catch {
            post(error.localizedDescription)
        }
    }

    private static func decodePayload(from url: URL) throws -> QuickReminderPayload {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawPayload = components.queryItems?.first(where: { $0.name == "payload" })?.value,
              let data = Data(base64URLEncoded: rawPayload) else {
            throw QuickReminderImportError.invalidPayload
        }
        do {
            return try JSONDecoder().decode(QuickReminderPayload.self, from: data)
        } catch {
            throw QuickReminderImportError.invalidPayload
        }
    }

    private static func repeatConfiguration(for rawValue: String) -> (rule: ReminderRepeat, hourlyHours: Int?) {
        switch rawValue.lowercased() {
        case "daily": return (.daily, nil)
        case "weekly": return (.weekly, nil)
        case "monthly": return (.monthly, nil)
        case "yearly": return (.yearly, nil)
        case "hourly1": return (.never, 1)
        case "hourly2": return (.never, 2)
        case "hourly3": return (.never, 3)
        case "hourly4": return (.never, 4)
        default: return (.never, nil)
        }
    }

    private static func wasProcessed(_ requestID: String) -> Bool {
        processedIDs().contains(requestID)
    }

    private static func rememberProcessed(_ requestID: String) {
        var values = processedIDs().filter { $0 != requestID }
        values.insert(requestID, at: 0)
        UserDefaults.standard.set(Array(values.prefix(50)), forKey: processedKey)
    }

    private static func processedIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: processedKey) ?? []
    }

    private static func post(_ message: String) {
        NotificationCenter.default.post(name: .nextQuickReminderImportResult, object: message)
    }
}

private enum QuickReminderImportError: LocalizedError {
    case invalidPayload
    case invalidTitle
    case invalidDate

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "The quick-reminder request could not be read. Open the tweak diagnostics and review the latest log."
        case .invalidTitle:
            return "Enter a reminder title before scheduling."
        case .invalidDate:
            return "Choose a reminder date and time in the future."
        }
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: normalized)
    }
}
