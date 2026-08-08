import Foundation
import SwiftUI
import Combine
import UserNotifications
import UIKit

// MARK: - CalendarRemindersView
struct CalendarRemindersView: View {
    @EnvironmentObject private var store: ReminderStore
    @State private var selectedDate = Date()

    private var remindersForDate: [ReminderItem] {
        store.pendingReminders.filter { Calendar.current.isDate($0.dueDate, inSameDayAs: selectedDate) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                DatePicker("Select date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(10)
                    .nextCard()

                SectionHeader(
                    title: selectedDate.formatted(date: .complete, time: .omitted),
                    trailing: "\(remindersForDate.count) reminder\(remindersForDate.count == 1 ? "" : "s")"
                )

                if remindersForDate.isEmpty {
                    EmptyStateView(
                        icon: "calendar.badge.checkmark",
                        title: "No reminders",
                        message: "There are no active reminders on this date."
                    )
                } else {
                    ForEach(remindersForDate) { reminder in
                        NavigationLink(value: reminder.id) {
                            ReminderCard(reminder: reminder, category: store.category(for: reminder.categoryID))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { id in
            ReminderDetailView(reminderID: id)
        }
    }
}

// MARK: - CategoryManagementView
struct CategoryManagementView: View {
    @EnvironmentObject private var store: ReminderStore
    @State private var editingCategory: ReminderCategory?
    @State private var isAdding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Personal and General are included by default. Rename them or add filters such as Company, Work, Health, Finance, or anything else.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                ForEach(store.categories) { category in
                    Button {
                        editingCategory = category
                    } label: {
                        HStack(spacing: 13) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(hex: category.colorHex).opacity(0.16))
                                Image(systemName: category.icon)
                                    .foregroundStyle(Color(hex: category.colorHex))
                            }
                            .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.name).font(.headline)
                                Text(category.isProtected ? "Default filter • Renamable" : "Custom filter")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .nextCard()
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    isAdding = true
                } label: {
                    Label("Add New Filter", systemImage: "plus.circle.fill")
                }
                .buttonStyle(OrangeActionButtonStyle())
                .padding(.top, 6)
            }
            .padding(16)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("Reminder Filters")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingCategory) { category in
            CategoryEditorView(category: category)
                .environmentObject(store)
        }
        .sheet(isPresented: $isAdding) {
            CategoryEditorView(category: nil)
                .environmentObject(store)
        }
    }
}

struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReminderStore
    let category: ReminderCategory?

    @State private var name: String
    @State private var icon: String
    @State private var colorHex: String

    private let icons = [
        "person.fill", "square.grid.2x2.fill", "building.2.fill", "briefcase.fill",
        "heart.fill", "creditcard.fill", "cart.fill", "house.fill", "car.fill",
        "graduationcap.fill", "dumbbell.fill", "airplane", "star.fill", "tag.fill"
    ]

    private let colors = ["FF7A00", "FF3B30", "32C76A", "0A84FF", "AF52DE", "FFD60A", "5E5CE6", "64D2FF"]

    init(category: ReminderCategory?) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _icon = State(initialValue: category?.icon ?? "tag.fill")
        _colorHex = State(initialValue: category?.colorHex ?? "FF7A00")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color(hex: colorHex).opacity(0.18))
                            Image(systemName: icon)
                                .font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(Color(hex: colorHex))
                        }
                        .frame(width: 100, height: 100)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Filter Name").font(.headline)
                        TextField("e.g. Company", text: $name)
                            .padding(14)
                            .nextCard()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Icon").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))], spacing: 10) {
                            ForEach(icons, id: \.self) { item in
                                Button {
                                    icon = item
                                } label: {
                                    Image(systemName: item)
                                        .font(.title3)
                                        .foregroundStyle(icon == item ? .white : Color(hex: colorHex))
                                        .frame(width: 48, height: 48)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(icon == item ? Color(hex: colorHex) : Color.nextCard)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Color").font(.headline)
                        HStack(spacing: 12) {
                            ForEach(colors, id: \.self) { color in
                                Button {
                                    colorHex = color
                                } label: {
                                    Circle()
                                        .fill(Color(hex: color))
                                        .frame(width: 34, height: 34)
                                        .overlay {
                                            if colorHex == color {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button(category == nil ? "Add Filter" : "Save Filter") {
                        save()
                    }
                    .buttonStyle(OrangeActionButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let category, !category.isProtected {
                        Button("Delete Filter", role: .destructive) {
                            store.deleteCategory(category)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
            .background(Color.nextBackground.ignoresSafeArea())
            .navigationTitle(category == nil ? "New Filter" : "Edit Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func save() {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if var category {
            category.name = cleaned
            category.icon = icon
            category.colorHex = colorHex
            store.updateCategory(category)
        } else {
            store.addCategory(name: cleaned, icon: icon, colorHex: colorHex)
        }
        dismiss()
    }
}
