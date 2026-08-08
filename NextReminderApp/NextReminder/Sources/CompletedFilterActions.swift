import Foundation
import SwiftUI
import Combine
import UserNotifications
import UIKit

// MARK: - CompletedRemindersView
enum CompletionRange: String, CaseIterable, Identifiable {
    case all
    case today
    case week
    case month

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .today: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        }
    }
}

struct CompletedRemindersView: View {
    @EnvironmentObject private var store: ReminderStore
    @State private var range: CompletionRange = .all
    @State private var searchText = ""

    private var filtered: [ReminderItem] {
        store.completedReminders.filter { reminder in
            let matchesSearch = searchText.isEmpty
                || reminder.title.localizedCaseInsensitiveContains(searchText)
                || (reminder.completionComment?.localizedCaseInsensitiveContains(searchText) ?? false)
            guard matchesSearch, let completedAt = reminder.completedAt else { return false }

            switch range {
            case .all:
                return true
            case .today:
                return Calendar.current.isDateInToday(completedAt)
            case .week:
                return Calendar.current.isDate(completedAt, equalTo: Date(), toGranularity: .weekOfYear)
            case .month:
                return Calendar.current.isDate(completedAt, equalTo: Date(), toGranularity: .month)
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                rangePicker

                if filtered.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.circle",
                        title: "Nothing completed yet",
                        message: "Completed reminders and their comments will appear here."
                    )
                } else {
                    ForEach(filtered) { reminder in
                        completedCard(reminder)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("Completed")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search completed reminders")
    }

    private var rangePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CompletionRange.allCases) { item in
                    Button {
                        range = item
                    } label: {
                        Text(item.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(range == item ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(range == item ? Color.nextOrange : Color.nextCard))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func completedCard(_ reminder: ReminderItem) -> some View {
        let category = store.category(for: reminder.categoryID)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text(reminder.title).font(.headline)
                    if let completedAt = reminder.completedAt {
                        Text("Completed \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(category.name)
                    .font(.caption.bold())
                    .foregroundStyle(Color(hex: category.colorHex))
            }

            if let comment = reminder.completionComment, !comment.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "text.bubble.fill")
                        .foregroundStyle(.nextOrange)
                    Text(comment)
                        .font(.subheadline)
                }
                .padding(11)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack {
                Button {
                    store.restore(reminder)
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                Spacer()
                Button(role: .destructive) {
                    store.delete(reminder)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .font(.subheadline.bold())
        }
        .padding(14)
        .nextCard()
    }
}

// MARK: - FilterView
struct FilterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReminderStore
    @Binding var selectedPriorities: Set<ReminderPriority>
    @Binding var selectedCategoryIDs: Set<UUID>

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SectionHeader(title: "Priority")
                    HStack(spacing: 10) {
                        ForEach(ReminderPriority.allCases) { priority in
                            Button {
                                toggle(priority, in: &selectedPriorities)
                            } label: {
                                HStack {
                                    Image(systemName: priority.symbol)
                                    Text(priority.title)
                                }
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(selectedPriorities.contains(priority) ? .white : priority.color)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selectedPriorities.contains(priority) ? priority.color : priority.color.opacity(0.13))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    SectionHeader(title: "Categories", trailing: "Custom filters included")
                    VStack(spacing: 10) {
                        ForEach(store.categories) { category in
                            Button {
                                toggle(category.id, in: &selectedCategoryIDs)
                            } label: {
                                HStack {
                                    Image(systemName: category.icon)
                                        .foregroundStyle(Color(hex: category.colorHex))
                                        .frame(width: 28)
                                    Text(category.name)
                                    Spacer()
                                    Image(systemName: selectedCategoryIDs.contains(category.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedCategoryIDs.contains(category.id) ? .nextOrange : .secondary)
                                }
                                .padding(14)
                                .nextCard()
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button("Apply Filters") { dismiss() }
                        .buttonStyle(OrangeActionButtonStyle())

                    Button("Reset All") {
                        selectedPriorities.removeAll()
                        selectedCategoryIDs.removeAll()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.red)
                }
                .padding(16)
            }
            .background(Color.nextBackground.ignoresSafeArea())
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}

// MARK: - ReminderActionViews
struct CompletionCommentView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReminderStore
    let reminder: ReminderItem
    @State private var comment = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Complete “\(reminder.title)”")
                    .font(.title3.bold())
                Text("Add an optional comment explaining the outcome.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $comment)
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .nextCard()

                Button("Complete Reminder") {
                    store.complete(reminder, comment: comment)
                    dismiss()
                }
                .buttonStyle(OrangeActionButtonStyle())
                Spacer()
            }
            .padding(16)
            .background(Color.nextBackground.ignoresSafeArea())
            .navigationTitle("Completion Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ExtendReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReminderStore
    let reminder: ReminderItem
    @State private var newDate: Date
    @State private var comment = ""

    init(reminder: ReminderItem) {
        self.reminder = reminder
        _newDate = State(initialValue: max(reminder.dueDate.addingTimeInterval(3600), Date().addingTimeInterval(3600)))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Move the deadline and record why it was extended.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                DatePicker(
                    "New deadline",
                    selection: $newDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .padding(14)
                .nextCard()

                TextEditor(text: $comment)
                    .frame(minHeight: 130)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .nextCard()
                    .overlay(alignment: .topLeading) {
                        if comment.isEmpty {
                            Text("Extension comment")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }

                Button("Extend Reminder") {
                    store.extend(reminder, to: newDate, comment: comment)
                    dismiss()
                }
                .buttonStyle(OrangeActionButtonStyle())
                Spacer()
            }
            .padding(16)
            .background(Color.nextBackground.ignoresSafeArea())
            .navigationTitle("Extend Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
