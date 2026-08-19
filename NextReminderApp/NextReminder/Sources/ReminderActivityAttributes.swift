import Foundation
import ActivityKit

@available(iOS 16.1, *)
struct ReminderActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var statusText: String
        var dueDate: Date
    }

    var reminderID: String
    var title: String
    var notes: String
    var categoryName: String
}
