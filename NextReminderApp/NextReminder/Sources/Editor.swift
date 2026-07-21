import Foundation
import SwiftUI
import Combine
import UserNotifications
import UIKit

// MARK: - ReminderEditorView
struct ReminderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReminderStore

    let reminder: ReminderItem?

    @State private var title: String
    @State private var notes: String
    @State private var dueDate: Date
    @State private var priority: ReminderPriority
    @State private var categoryID: UUID
    @State private var repeatRule: ReminderRepeat
    @State private var alertOffsets: Set<ReminderAlertOffset>
    @State private var notificationsEnabled: Bool
    @State private var isRequestingPermission = false
    @State private var permissionDenied = false

    init(reminder: ReminderItem?) {
        self.reminder = reminder
        _title = State(initialValue: reminder?.title ?? "")
        _notes = State(initialValue: reminder?.notes ?? "")
        _dueDate = State(initialValue: reminder?.dueDate ?? Date().addingTimeInterval(3600))
        _priority = State(initialValue: reminder?.priority ?? .medium)
        _categoryID = State(initialValue: reminder?.categoryID ?? ReminderCategory.general.id)
        _repeatRule = State(initialValue: reminder?.repeatRule ?? .never)
        _alertOffsets = State(initialValue: reminder?.alertOffsets ?? [.thirtyMinutes])
        _notificationsEnabled = State(initialValue: reminder?.notificationsEnabled ?? true)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && dueDate > Date().addingTimeInterval(-60)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                inputSection
                dateSection
                prioritySection
                categorySection
                notificationSection
                repeatSection

                Button(reminder == nil ? "Create Reminder" : "Save Changes") {
                    saveReminder()
                }
                .buttonStyle(OrangeActionButtonStyle())
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
                .padding(.top, 4)
            }
            .padding(16)
            .padding(.bottom, 30)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle(reminder == nil ? "Add Reminder" : "Edit Reminder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .alert("Notifications Are Disabled", isPresented: $permissionDenied) {
            Button("Open Settings") { NotificationManager.shared.openSystemSettings() }
            Button("Continue Without Alerts", role: .cancel) {
                notificationsEnabled = false
            }
        } message: {
            Text("Enable notifications in Settings to receive reminder alerts.")
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Reminder")
            TextField("Title", text: $title)
                .font(.headline)
                .padding(14)
                .nextCard()

            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Notes or details")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.clear)
            }
            .nextCard()
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Deadline")
            DatePicker(
                "Date and time",
                selection: $dueDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .padding(14)
            .nextCard()
        }
    }

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Priority")
            HStack(spacing: 10) {
                ForEach(ReminderPriority.allCases) { item in
                    Button {
                        priority = item
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: item.symbol)
                            Text(item.title)
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(priority == item ? .white : item.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(priority == item ? item.color : item.color.opacity(0.13))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Filter / Category", trailing: "Renamable in Settings")
            Menu {
                ForEach(store.categories) { category in
                    Button {
                        categoryID = category.id
                    } label: {
                        Label(category.name, systemImage: category.icon)
                    }
                }
            } label: {
                let category = store.category(for: categoryID)
                HStack {
                    Image(systemName: category.icon)
                        .foregroundStyle(Color(hex: category.colorHex))
                    Text(category.name)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .nextCard()
            }
            .buttonStyle(.plain)
        }
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Notifications")
                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
                    .onChange(of: notificationsEnabled) { enabled in
                        guard enabled else { return }
                        Task { await requestPermissionIfNeeded() }
                    }
            }

            if notificationsEnabled {
                Text("Receive one or more alerts before the deadline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 9)], spacing: 9) {
                    ForEach(ReminderAlertOffset.allCases) { offset in
                        Button {
                            if alertOffsets.contains(offset) {
                                alertOffsets.remove(offset)
                            } else {
                                alertOffsets.insert(offset)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: alertOffsets.contains(offset) ? "checkmark.circle.fill" : "bell")
                                Text(offset.title)
                            }
                            .font(.caption.bold())
                            .foregroundStyle(alertOffsets.contains(offset) ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(alertOffsets.contains(offset) ? Color.nextOrange : Color.nextCard)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Repeat")
            Menu {
                ForEach(ReminderRepeat.allCases) { rule in
                    Button(rule.title) { repeatRule = rule }
                }
            } label: {
                HStack {
                    Image(systemName: "repeat")
                        .foregroundStyle(.nextOrange)
                    Text(repeatRule.title)
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
    }

    private func requestPermissionIfNeeded() async {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        let granted = await store.requestNotificationPermission()
        isRequestingPermission = false
        if !granted { permissionDenied = true }
    }

    private func saveReminder() {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedAlerts: Set<ReminderAlertOffset> = notificationsEnabled && alertOffsets.isEmpty ? [.atTime] : alertOffsets

        if var existing = reminder {
            existing.title = cleanedTitle
            existing.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.dueDate = dueDate
            existing.priority = priority
            existing.categoryID = categoryID
            existing.repeatRule = repeatRule
            existing.alertOffsets = selectedAlerts
            existing.notificationsEnabled = notificationsEnabled
            store.update(existing)
        } else {
            store.add(
                ReminderItem(
                    title: cleanedTitle,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    dueDate: dueDate,
                    priority: priority,
                    categoryID: categoryID,
                    repeatRule: repeatRule,
                    alertOffsets: selectedAlerts,
                    notificationsEnabled: notificationsEnabled
                )
            )
        }
        dismiss()
    }
}
