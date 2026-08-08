import SwiftUI

// MARK: - AppComponents
struct NextCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.nextCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.nextCardBorder, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func nextCard() -> some View { modifier(NextCardModifier()) }
}

struct OrangeActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [.nextOrange, Color(red: 1, green: 0.25, blue: 0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.nextOrange)
            Text(title)
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CategoryPill: View {
    let category: ReminderCategory
    let selected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: category.icon)
            Text(category.name)
                .lineLimit(1)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(selected ? Color(hex: category.colorHex) : Color.nextCard)
        )
        .overlay(
            Capsule()
                .stroke(selected ? Color.clear : Color.nextCardBorder, lineWidth: 1)
        )
    }
}

struct PriorityBadge: View {
    let priority: ReminderPriority

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: priority.symbol)
            Text(priority.title)
        }
        .font(.caption2.bold())
        .foregroundStyle(priority.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(priority.color.opacity(0.14), in: Capsule())
    }
}

struct UrgencyBadge: View {
    let urgency: ReminderUrgency

    var body: some View {
        Label(urgency.title, systemImage: urgency.symbol)
            .font(.caption2.bold())
            .foregroundStyle(urgency.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(urgency.color.opacity(0.14), in: Capsule())
    }
}

// MARK: - ReminderCard
struct ReminderCard: View {
    let reminder: ReminderItem
    let category: ReminderCategory

    private var urgency: ReminderUrgency { reminder.urgency }
    private var accentColor: Color { urgency.color }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(accentColor.opacity(0.18))
                Image(systemName: urgency.symbol)
                    .font(.title3.bold())
                    .foregroundStyle(accentColor)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 6) {
                Text(reminder.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Label(reminder.dueDate.compactDateTime, systemImage: "bell.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let deadline = reminder.deadlineDate {
                    Label("Deadline: \(deadline.compactDateTime)", systemImage: "flag.checkered")
                        .font(.caption)
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                }

                if !reminder.notes.isEmpty {
                    Text(reminder.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                Text(reminder.timeRemaining())
                    .font(.caption.bold())
                    .foregroundStyle(accentColor)
                    .multilineTextAlignment(.trailing)
                UrgencyBadge(urgency: urgency)
                HStack(spacing: 5) {
                    Image(systemName: category.icon)
                    Text(category.name)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [accentColor.opacity(0.26), accentColor.opacity(0.08), Color.nextCard.opacity(0.98)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accentColor.opacity(0.38), lineWidth: 1)
        )
        .shadow(color: accentColor.opacity(0.08), radius: 8, y: 3)
    }
}
