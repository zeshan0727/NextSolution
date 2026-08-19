import Foundation

@MainActor
enum ReminderLiveActionHandler {
    static func handle(_ url: URL, store: ReminderStore) async -> Bool {
        guard url.scheme?.lowercased() == "nextreminder",
              url.host?.lowercased() == "live-action" else {
            return false
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let values = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        guard let rawID = values["id"], let id = UUID(uuidString: rawID) else { return true }
        guard let reminder = store.reminders.first(where: { $0.id == id }) else {
            await ReminderLiveActivityManager.shared.end(reminderID: id)
            return true
        }

        switch values["action"]?.lowercased() {
        case "complete":
            store.completeFinally(reminder, comment: "Completed from Lock Screen")
            await ReminderLiveActivityManager.shared.end(reminderID: id)
        case "extend":
            await ReminderLiveActivityManager.shared.end(reminderID: id)
            store.extend(
                reminder,
                to: Date().addingTimeInterval(10 * 60),
                comment: "Extended 10 minutes from Lock Screen"
            )
        default:
            break
        }
        return true
    }
}
