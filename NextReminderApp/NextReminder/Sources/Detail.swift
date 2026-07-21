import SwiftUI

// MARK: - ReminderDetailView
struct ReminderDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReminderStore
    @EnvironmentObject private var emailStore: EmailAutomationStore
    let reminderID: UUID

    @State private var isEditing = false
    @State private var isCompleting = false
    @State private var isExtending = false
    @State private var showDeleteConfirmation = false

    private var reminder: ReminderItem? {
        store.reminders.first(where: { $0.id == reminderID })
    }

    var body: some View {
        Group {
            if let reminder {
                ScrollView {
                    VStack(spacing: 18) {
                        countdownCard(reminder)
                        informationCard(reminder)
                        actionButtons(reminder)
                        historySection(reminder)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .background(Color.nextBackground.ignoresSafeArea())
                .navigationTitle("Reminder Details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button { isEditing = true } label: { Image(systemName: "pencil") }
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                .sheet(isPresented: $isEditing) {
                    NavigationStack { ReminderEditorView(reminder: reminder) }
                }
                .sheet(isPresented: $isCompleting) {
                    CompletionCommentView(reminder: reminder)
                        .environmentObject(store)
                }
                .sheet(isPresented: $isExtending) {
                    ExtendReminderView(reminder: reminder)
                        .environmentObject(store)
                }
                .confirmationDialog(
                    "Delete this reminder?",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        store.delete(reminder)
                        dismiss()
                    }
                }
            } else {
                EmptyStateView(
                    icon: "questionmark.circle",
                    title: "Reminder not found",
                    message: "This reminder may have been deleted."
                )
            }
        }
    }

    private func countdownCard(_ reminder: ReminderItem) -> some View {
        let category = store.category(for: reminder.categoryID)
        let urgency = reminder.urgency
        let color = urgency.color

        return VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.nextCardBorder, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress(for: reminder))
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.45), color, .nextOrange],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 7) {
                    Image(systemName: urgency.symbol)
                        .font(.title2)
                        .foregroundStyle(color)
                    Text(reminder.timeRemaining())
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(reminder.deadlineDate == nil ? "Reminder time" : "Final deadline")
                        .font(.caption2.bold())
                        .foregroundStyle(color)
                    Text(reminder.effectiveDeadline.compactDateTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .frame(width: 220, height: 220)

            VStack(spacing: 8) {
                Text(reminder.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    UrgencyBadge(urgency: urgency)
                    PriorityBadge(priority: reminder.priority)
                    Text(category.name)
                        .font(.caption.bold())
                        .foregroundStyle(color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(color.opacity(0.14), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            LinearGradient(
                colors: [color.opacity(0.18), Color.nextCard],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }

    private func informationCard(_ reminder: ReminderItem) -> some View {
        VStack(spacing: 0) {
            detailRow(
                icon: "bell.fill",
                title: "Reminder time",
                value: reminder.dueDate.formatted(date: .long, time: .shortened)
            )

            if let deadline = reminder.deadlineDate {
                Divider().opacity(0.2)
                detailRow(
                    icon: "flag.checkered",
                    title: "Final deadline",
                    value: deadline.formatted(date: .long, time: .shortened)
                )
            }

            Divider().opacity(0.2)
            detailRow(icon: "alarm.fill", title: "Alerts", value: alertText(reminder))

            Divider().opacity(0.2)
            detailRow(icon: "repeat", title: "Repeat", value: reminder.repeatRule.title)

            Divider().opacity(0.2)
            detailRow(
                icon: "envelope.badge.fill",
                title: "Email at reminder time",
                value: emailText(reminder)
            )

            if !reminder.notes.isEmpty {
                Divider().opacity(0.2)
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "note.text")
                        .foregroundStyle(.nextOrange)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Notes").font(.caption).foregroundStyle(.secondary)
                        Text(reminder.notes).font(.subheadline)
                    }
                    Spacer()
                }
                .padding(14)
            }
        }
        .nextCard()
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.nextOrange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.medium))
            }
            Spacer()
        }
        .padding(14)
    }

    private func actionButtons(_ reminder: ReminderItem) -> some View {
        HStack(spacing: 12) {
            Button { isExtending = true } label: {
                Label(reminder.deadlineDate == nil ? "Extend" : "Extend Times", systemImage: "arrow.forward.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button { isCompleting = true } label: {
                Label("Complete", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(OrangeActionButtonStyle())
        }
    }

    @ViewBuilder
    private func historySection(_ reminder: ReminderItem) -> some View {
        if !reminder.history.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "History")
                ForEach(reminder.history.reversed()) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: historyIcon(entry.action))
                            .foregroundStyle(.nextOrange)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(historyTitle(entry.action)).font(.subheadline.bold())
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !entry.comment.isEmpty {
                                Text(entry.comment)
                                    .font(.subheadline)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                    .padding(14)
                    .nextCard()
                }
            }
        }
    }

    private func progress(for reminder: ReminderItem) -> CGFloat {
        let remaining = reminder.effectiveDeadline.timeIntervalSinceNow
        if remaining <= 0 { return 1 }
        let window = max(reminder.effectiveDeadline.timeIntervalSince(reminder.createdAt), 3600)
        return CGFloat(min(max(1 - remaining / window, 0.05), 1))
    }

    private func alertText(_ reminder: ReminderItem) -> String {
        guard reminder.notificationsEnabled else { return "Off" }
        return reminder.alertOffsets
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.title)
            .joined(separator: ", ")
    }

    private func emailText(_ reminder: ReminderItem) -> String {
        guard reminder.emailWhenDue else { return "Off" }
        let settings = emailStore.settings
        guard settings.enabled, settings.hasValidRecipient else { return "Setup required" }
        return "\(settings.deliveryMethod.shortTitle) to \(settings.recipient)"
    }

    private func historyIcon(_ action: ReminderHistoryEntry.Action) -> String {
        switch action {
        case .completed: return "checkmark.circle.fill"
        case .extended: return "arrow.forward.circle.fill"
        case .restored: return "arrow.uturn.backward.circle.fill"
        }
    }

    private func historyTitle(_ action: ReminderHistoryEntry.Action) -> String {
        switch action {
        case .completed: return "Completed"
        case .extended: return "Reminder and deadline extended"
        case .restored: return "Restored"
        }
    }
}
