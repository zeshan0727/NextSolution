import Foundation
import ActivityKit

@MainActor
final class ReminderLiveActivityManager {
    static let shared = ReminderLiveActivityManager()
    private init() {}

    func sync(_ reminder: ReminderItem, categoryName: String) async {
        guard #available(iOS 16.1, *) else { return }
        await end(reminderID: reminder.id)
        guard reminder.notificationsEnabled, !reminder.isCompleted else { return }

        // On iOS 16.1–25, ActivityKit can't schedule a future start while the app
        // is suspended. Start only close to the due time so the card behaves like
        // a due reminder instead of a long-running countdown. The normal actionable
        // lock-screen notification remains the exact-time fallback on iOS 16.0+.
        let now = Date()
        let secondsUntilDue = reminder.dueDate.timeIntervalSince(now)
        guard secondsUntilDue <= 120 else { return }

        let attributes = ReminderActivityAttributes(
            reminderID: reminder.id.uuidString,
            title: reminder.title,
            notes: reminder.notes,
            categoryName: categoryName
        )
        let state = ReminderActivityAttributes.ContentState(
            statusText: secondsUntilDue <= 0 ? "Due now" : "Due soon",
            dueDate: reminder.dueDate
        )

        do {
            _ = try Activity<ReminderActivityAttributes>.request(
                attributes: attributes,
                contentState: state,
                pushType: nil
            )
        } catch {
            // Local notification remains available even when Live Activities are disabled.
        }
    }

    func syncDueActivities(reminders: [ReminderItem], categoryName: (UUID) -> String) async {
        guard #available(iOS 16.1, *) else { return }
        let liveIDs = Set(reminders.filter { !$0.isCompleted }.map { $0.id })
        for activity in Activity<ReminderActivityAttributes>.activities {
            guard let id = UUID(uuidString: activity.attributes.reminderID), liveIDs.contains(id) else {
                await activity.end(dismissalPolicy: .immediate)
                continue
            }
        }
        for reminder in reminders where !reminder.isCompleted {
            await sync(reminder, categoryName: categoryName(reminder.categoryID))
        }
    }

    func end(reminderID: UUID) async {
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<ReminderActivityAttributes>.activities
        where activity.attributes.reminderID == reminderID.uuidString {
            await activity.end(dismissalPolicy: .immediate)
        }
    }
}
