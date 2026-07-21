import Foundation
import SwiftUI
import Combine
import UserNotifications
import UIKit

// MARK: - AppComponents
struct NextCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.nextCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
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
                .stroke(selected ? Color.clear : Color.white.opacity(0.06), lineWidth: 1)
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

// MARK: - ReminderCard
struct ReminderCard: View {
    let reminder: ReminderItem
    let category: ReminderCategory

    private var accentColor: Color {
        reminder.isOverdue ? .red : Color(hex: category.colorHex)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(accentColor.opacity(0.18))
                Image(systemName: category.icon)
                    .font(.title3.bold())
                    .foregroundStyle(accentColor)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 6) {
                Text(reminder.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(reminder.dueDate.compactDateTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(reminder.isOverdue ? .red : accentColor)
                    .multilineTextAlignment(.trailing)
                PriorityBadge(priority: reminder.priority)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [accentColor.opacity(0.20), Color.nextCard.opacity(0.96)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accentColor.opacity(0.25), lineWidth: 1)
        )
    }
}
