import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct ReminderLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReminderActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bell.badge.fill")
                        .font(.title3.bold())
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.attributes.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(context.state.statusText)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(context.state.dueDate, style: .timer)
                        .font(.subheadline.monospacedDigit().bold())
                }

                if !context.attributes.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(context.attributes.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Link(destination: actionURL(action: "complete", id: context.attributes.reminderID)) {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)

                    Link(destination: actionURL(action: "extend", id: context.attributes.reminderID)) {
                        Label("Extend 10m", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(14)
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.dueDate, style: .timer)
                        .font(.caption.monospacedDigit().bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(context.attributes.title)
                            .font(.subheadline.bold())
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Link("Completed", destination: actionURL(action: "complete", id: context.attributes.reminderID))
                            Spacer()
                            Link("Extend 10m", destination: actionURL(action: "extend", id: context.attributes.reminderID))
                        }
                        .font(.caption.bold())
                    }
                }
            } compactLeading: {
                Image(systemName: "bell.fill").foregroundStyle(.orange)
            } compactTrailing: {
                Text(context.state.dueDate, style: .timer)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "bell.fill").foregroundStyle(.orange)
            }
            .widgetURL(URL(string: "nextreminder://live-action?action=open&id=\(context.attributes.reminderID)"))
            .keylineTint(.orange)
        }
    }

    private func actionURL(action: String, id: String) -> URL {
        var components = URLComponents()
        components.scheme = "nextreminder"
        components.host = "live-action"
        components.queryItems = [
            URLQueryItem(name: "action", value: action),
            URLQueryItem(name: "id", value: id)
        ]
        return components.url ?? URL(string: "nextreminder://live-action")!
    }
}

@available(iOS 16.1, *)
@main
struct NextReminderLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        ReminderLiveActivityWidget()
    }
}
