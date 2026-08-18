#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'NextReminder' / 'Sources'


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f'Expected text not found in {path}: {old[:220]!r}')
    path.write_text(text.replace(old, new, 1))

# 1) Never re-submit email jobs merely because the app was opened.
services = SOURCES / 'Services.swift'
replace_once(
    services,
    '''        let existing = pendingReminders
        let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        Task {
            let status = await NotificationManager.shared.authorizationStatus()
            if status == .notDetermined {
                _ = await NotificationManager.shared.requestAuthorization()
            }

            for reminder in existing {
                await NotificationManager.shared.schedule(
                    reminder,
                    categoryName: categoryNames[reminder.categoryID] ?? ReminderCategory.general.name
                )
                await EmailAutomationManager.shared.sync(reminder)
            }
        }''',
    '''        // Rebuild local iOS notifications on launch, but never re-submit email
        // automation jobs just because the app was opened. Email jobs are created
        // only when a reminder is created/edited or email settings are explicitly saved.
        let existing = pendingReminders
        let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        Task {
            let status = await NotificationManager.shared.authorizationStatus()
            if status == .notDetermined {
                _ = await NotificationManager.shared.requestAuthorization()
            }

            for reminder in existing {
                await NotificationManager.shared.schedule(
                    reminder,
                    categoryName: categoryNames[reminder.categoryID] ?? ReminderCategory.general.name
                )
            }
        }'''
)

# 2) Explicit repeat controls: cancel recurrence without completing, or finish forever.
replace_once(
    services,
    '''    func complete(_ reminder: ReminderItem, comment: String) {''',
    '''    func cancelRepeat(_ reminder: ReminderItem) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        let wasHourlyRoutine = HourlyRepeatStore.shared.hours(for: reminder.id) != nil

        SelectedDayScheduleStore.shared.remove(for: reminder.id)
        HourlyRepeatStore.shared.remove(for: reminder.id)

        reminders[index].repeatRule = .never
        if wasHourlyRoutine && reminders[index].categoryID == ReminderCategory.routines.id {
            reminders[index].categoryID = ReminderCategory.general.id
        }
        reminders[index].updatedAt = Date()

        // Keep the current occurrence as a normal one-time reminder.
        persistAndSchedule(reminders[index])
        refreshUnattendedBadge()
    }

    func completeFinally(_ reminder: ReminderItem, comment: String) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        let completionDate = Date()
        let cleanedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)

        // Final completion permanently ends every recurrence path before archiving.
        SelectedDayScheduleStore.shared.remove(for: reminder.id)
        HourlyRepeatStore.shared.remove(for: reminder.id)
        reminders[index].repeatRule = .never
        reminders[index].completedAt = completionDate
        reminders[index].completionComment = cleanedComment.isEmpty ? nil : cleanedComment
        reminders[index].updatedAt = completionDate
        reminders[index].history.append(
            ReminderHistoryEntry(
                action: .completed,
                date: completionDate,
                comment: cleanedComment,
                previousDueDate: reminder.dueDate,
                newDueDate: nil
            )
        )

        save()
        Task {
            await NotificationManager.shared.cancel(reminderID: reminder.id)
            await EmailAutomationManager.shared.cancel(reminderID: reminder.id)
        }
        UnattendedReminderTracker.shared.remove(reminder.id)
        refreshUnattendedBadge()
    }

    func complete(_ reminder: ReminderItem, comment: String) {'''
)

# 3) Automatic email is opt-in per reminder only, and future-due only.
email_core = SOURCES / 'EmailAutomationCore.swift'
replace_once(
    email_core,
    '''        let urgentEmailEnabled = UserDefaults.standard.object(forKey: Self.urgentAutoEmailKey) as? Bool ?? true
        let shouldSendEmail = reminder.emailWhenDue
            || (urgentEmailEnabled && reminder.priority == .urgent)

        guard shouldSendEmail,
              !reminder.isCompleted,
              settings.enabled,
              settings.hasValidRecipient else {
            await cancelRemote(reminderID: reminder.id)
            return
        }

        if settings.deliveryMethod.isAutomatic {
            do {''',
    '''        // Strict per-reminder opt-in: priority must never enable email by itself.
        // Also refuse to submit an already-due/overdue reminder, preventing an app
        // edit or settings refresh from turning into an immediate email delivery.
        guard reminder.emailWhenDue,
              !reminder.isCompleted,
              reminder.dueDate > Date().addingTimeInterval(5),
              settings.enabled,
              settings.hasValidRecipient else {
            await cancelRemote(reminderID: reminder.id)
            return
        }

        if settings.deliveryMethod.isAutomatic {
            // Replace any existing server job for this local reminder ID so edits
            // cannot create duplicate scheduled deliveries.
            await cancelRemote(reminderID: reminder.id)
            do {'''
)

# Hide the old global urgent-email override and only reschedule explicitly opted-in reminders.
email_settings = SOURCES / 'EmailAutomationSettingsView.swift'
replace_once(
    email_settings,
    '''    @State private var draft = EmailAutomationSettings()
    @AppStorage(EmailAutomationManager.urgentAutoEmailKey) private var urgentEmailAutomatically = true''',
    '''    @State private var draft = EmailAutomationSettings()'''
)
replace_once(
    email_settings,
    '''        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = emailStore.settings }
        .onChange(of: urgentEmailAutomatically) { _ in
            reschedulePendingReminders()
        }''',
    '''        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = emailStore.settings }'''
)
replace_once(
    email_settings,
    '''            Toggle("Enable reminder email automation", isOn: $draft.enabled)
                .padding(14)
                .nextCard()
            Toggle("Always email urgent reminders", isOn: $urgentEmailAutomatically)
                .padding(14)
                .nextCard()
            Text("Urgent reminders are emailed automatically when this option is enabled. Other reminders can independently choose whether an email should be sent at reminder time.")
                .font(.caption)
                .foregroundStyle(.secondary)''',
    '''            Toggle("Enable reminder email automation", isOn: $draft.enabled)
                .padding(14)
                .nextCard()
            Text("Email is sent only for reminders where ‘Send or prepare an email’ is enabled. Priority alone never sends an email. Automatic delivery is scheduled for the reminder due time.")
                .font(.caption)
                .foregroundStyle(.secondary)'''
)
replace_once(
    email_settings,
    '''    private func reschedulePendingReminders() {
        let reminders = reminderStore.pendingReminders
        Task {
            for reminder in reminders {
                await EmailAutomationManager.shared.sync(reminder)
            }
        }
    }''',
    '''    private func reschedulePendingReminders() {
        let reminders = reminderStore.pendingReminders.filter {
            $0.emailWhenDue && $0.dueDate > Date().addingTimeInterval(5)
        }
        Task {
            for reminder in reminders {
                await EmailAutomationManager.shared.sync(reminder)
            }
        }
    }'''
)

# 4) Detail screen controls for stopping recurrence and final completion.
detail = SOURCES / 'Detail.swift'
replace_once(
    detail,
    '''    @State private var isCompleting = false
    @State private var isExtending = false
    @State private var showDeleteConfirmation = false''',
    '''    @State private var isCompleting = false
    @State private var isFinalCompleting = false
    @State private var isExtending = false
    @State private var showDeleteConfirmation = false
    @State private var showCancelRepeatConfirmation = false'''
)
replace_once(
    detail,
    '''                .sheet(isPresented: $isCompleting) {
                    CompletionCommentView(reminder: reminder)
                        .environmentObject(store)
                }
                .sheet(isPresented: $isExtending) {''',
    '''                .sheet(isPresented: $isCompleting) {
                    CompletionCommentView(reminder: reminder)
                        .environmentObject(store)
                }
                .sheet(isPresented: $isFinalCompleting) {
                    CompletionCommentView(reminder: reminder, finalCompletion: true)
                        .environmentObject(store)
                }
                .sheet(isPresented: $isExtending) {'''
)
replace_once(
    detail,
    '''                .confirmationDialog(
                    "Delete this reminder?",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        store.delete(reminder)
                        dismiss()
                    }
                }''',
    '''                .confirmationDialog(
                    "Cancel repeat?",
                    isPresented: $showCancelRepeatConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Cancel Repeat", role: .destructive) {
                        store.cancelRepeat(reminder)
                    }
                    Button("Keep Repeating", role: .cancel) {}
                } message: {
                    Text("The current reminder stays active as a one-time reminder. No new repeat occurrence will be created.")
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
                }'''
)
old_actions = '''    private func actionButtons(_ reminder: ReminderItem) -> some View {
        HStack(spacing: 12) {
            Button { isExtending = true } label: {
                Label(reminder.deadlineDate == nil ? "Extend" : "Extend Times", systemImage: "arrow.forward.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button { isCompleting = true } label: {
                Label(
                    reminder.isHourlyRoutine ? "Complete Occurrence" : "Complete",
                    systemImage: "checkmark.circle.fill"
                )
            }
            .buttonStyle(OrangeActionButtonStyle())
        }
    }'''
new_actions = '''    private func actionButtons(_ reminder: ReminderItem) -> some View {
        let isRepeating = reminder.repeatRule != .never || reminder.isHourlyRoutine

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button { isExtending = true } label: {
                    Label(reminder.deadlineDate == nil ? "Extend" : "Extend Times", systemImage: "arrow.forward.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button { isCompleting = true } label: {
                    Label(
                        reminder.isHourlyRoutine ? "Complete Occurrence" : "Complete",
                        systemImage: "checkmark.circle.fill"
                    )
                }
                .buttonStyle(OrangeActionButtonStyle())
            }

            if isRepeating {
                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        showCancelRepeatConfirmation = true
                    } label: {
                        Label("Cancel Repeat", systemImage: "repeat.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    Button {
                        isFinalCompleting = true
                    } label: {
                        Label("Final Complete", systemImage: "checkmark.seal.fill")
                    }
                    .buttonStyle(OrangeActionButtonStyle())
                }

                Text("Cancel Repeat keeps this occurrence active as one-time. Final Complete ends the repeat permanently and moves it to Completed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }'''
replace_once(detail, old_actions, new_actions)

# 5) Completion sheet can permanently finish a repeating reminder.
actions = SOURCES / 'CompletedFilterActions.swift'
replace_once(
    actions,
    '''    @EnvironmentObject private var store: ReminderStore
    let reminder: ReminderItem
    @State private var comment = ""''',
    '''    @EnvironmentObject private var store: ReminderStore
    let reminder: ReminderItem
    var finalCompletion: Bool = false
    @State private var comment = ""'''
)
replace_once(
    actions,
    '''                Text(
                    reminder.isHourlyRoutine
                        ? "Complete this occurrence"
                        : "Complete “\(reminder.title)”"
                )
                    .font(.title3.bold())
                Text(
                    reminder.isHourlyRoutine
                        ? "This records the current \(reminder.dueDate.formatted(date: .abbreviated, time: .shortened)) slot. The main routine preset will remain active."
                        : "Add an optional comment explaining the outcome."
                )''',
    '''                Text(
                    finalCompletion
                        ? "Final complete “\(reminder.title)”"
                        : reminder.isHourlyRoutine
                            ? "Complete this occurrence"
                            : "Complete “\(reminder.title)”"
                )
                    .font(.title3.bold())
                Text(
                    finalCompletion
                        ? "This permanently stops the repeat, cancels future alerts/email jobs for this occurrence, and moves the reminder to Completed."
                        : reminder.isHourlyRoutine
                            ? "This records the current \(reminder.dueDate.formatted(date: .abbreviated, time: .shortened)) slot. The main routine preset will remain active."
                            : "Add an optional comment explaining the outcome."
                )'''
)
replace_once(
    actions,
    '''                Button(reminder.isHourlyRoutine ? "Complete This Occurrence" : "Complete Reminder") {
                    store.complete(reminder, comment: comment)
                    dismiss()
                }''',
    '''                Button(
                    finalCompletion
                        ? "Final Complete"
                        : reminder.isHourlyRoutine ? "Complete This Occurrence" : "Complete Reminder"
                ) {
                    if finalCompletion {
                        store.completeFinally(reminder, comment: comment)
                    } else {
                        store.complete(reminder, comment: comment)
                    }
                    dismiss()
                }'''
)
replace_once(
    actions,
    '''            .navigationTitle("Completion Comment")''',
    '''            .navigationTitle(finalCompletion ? "Final Completion" : "Completion Comment")'''
)

# 6) Version metadata.
project = ROOT / 'project.yml'
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.3.17"', 'CFBundleShortVersionString: "1.3.18"')
project_text = project_text.replace('CFBundleVersion: "27"', 'CFBundleVersion: "28"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.17"', 'MARKETING_VERSION: "1.3.18"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "27"', 'CURRENT_PROJECT_VERSION: "28"')
project.write_text(project_text)

settings = SOURCES / 'Settings.swift'
settings.write_text(settings.read_text().replace('Version 1.3.17 • iOS 16.0+', 'Version 1.3.18 • iOS 16.0+'))
for swift in SOURCES.glob('*.swift'):
    swift.write_text(swift.read_text().replace('NextReminder-iOS/1.3.17', 'NextReminder-iOS/1.3.18'))

print('Next Reminder v1.3.18 email timing, repeat controls and final completion patch applied successfully.')
