#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:260]!r}")
    path.write_text(text.replace(old, new, 1))


editor = SOURCES / "Editor.swift"

replace_once(
    editor,
    '''    @State private var permissionDenied = false''',
    '''    @State private var permissionDenied = false
    @State private var showStopRoutineConfirmation = false'''
)

replace_once(
    editor,
    '''                Button("Off") { hourlyRepeatHours = 0 }''',
    '''                Button("Off") {
                    hourlyRepeatHours = 0
                    repeatRule = .never
                    if categoryID == ReminderCategory.routines.id {
                        categoryID = ReminderCategory.general.id
                    }
                    if dueDate <= Date() {
                        dueDate = Date().addingTimeInterval(60)
                    }
                }'''
)

replace_once(
    editor,
    '''            if hourlyRepeatHours > 0 {
                VStack(alignment: .leading, spacing: 5) {''',
    '''            if reminder?.isHourlyRoutine == true {
                Button(role: .destructive) {
                    showStopRoutineConfirmation = true
                } label: {
                    Label("Stop Routine & Cancel Alerts", systemImage: "stop.circle.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Text("Stops the hourly cycle immediately and removes every pending alert for this routine. Completed occurrence history stays inside the reminder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if hourlyRepeatHours > 0 {
                VStack(alignment: .leading, spacing: 5) {'''
)

replace_once(
    editor,
    '''        .alert("Notifications Are Disabled", isPresented: $permissionDenied) {''',
    '''        .confirmationDialog(
            "Stop this routine?",
            isPresented: $showStopRoutineConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop Routine & Cancel Alerts", role: .destructive) {
                stopRoutineImmediately()
            }
            Button("Keep Routine", role: .cancel) {}
        } message: {
            Text("The preset will stop repeating. Its completed occurrence history will remain saved.")
        }
        .alert("Notifications Are Disabled", isPresented: $permissionDenied) {'''
)

replace_once(
    editor,
    '''    private func saveReminder() {''',
    '''    private func stopRoutineImmediately() {
        guard var existing = reminder else { return }

        HourlyRepeatStore.shared.remove(for: existing.id)
        SelectedDayScheduleStore.shared.remove(for: existing.id)
        existing.repeatRule = .never
        existing.notificationsEnabled = false
        existing.alertOffsets = []
        existing.deadlineDate = nil
        existing.categoryID = ReminderCategory.general.id
        existing.updatedAt = Date()
        store.update(existing)

        Task {
            await NotificationManager.shared.cancel(reminderID: existing.id)
            await EmailAutomationManager.shared.sync(existing)
        }
        dismiss()
    }

    private func saveReminder() {'''
)

replace_once(
    editor,
    '''            if hourlyRepeatHours > 0 {
                HourlyRepeatStore.shared.save(hourlyRepeatHours, for: existing.id)
            } else {
                HourlyRepeatStore.shared.remove(for: existing.id)
            }
            store.update(existing)''',
    '''            if hourlyRepeatHours > 0 {
                HourlyRepeatStore.shared.save(hourlyRepeatHours, for: existing.id)
            } else {
                HourlyRepeatStore.shared.remove(for: existing.id)
                if reminder?.isHourlyRoutine == true {
                    existing.repeatRule = .never
                    existing.categoryID = ReminderCategory.general.id
                }
            }
            store.update(existing)
            if hourlyRepeatHours == 0 && reminder?.isHourlyRoutine == true {
                Task { await NotificationManager.shared.cancel(reminderID: existing.id) }
            }'''
)

project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.3.8"', 'CFBundleShortVersionString: "1.3.9"')
project_text = project_text.replace('CFBundleVersion: "18"', 'CFBundleVersion: "19"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.8"', 'MARKETING_VERSION: "1.3.9"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "18"', 'CURRENT_PROJECT_VERSION: "19"')
project.write_text(project_text)

settings = SOURCES / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.3.8 • iOS 16.0+", "Version 1.3.9 • iOS 16.0+"))

for path in SOURCES.glob("*.swift"):
    path.write_text(path.read_text().replace("NextReminder-iOS/1.3.8", "NextReminder-iOS/1.3.9"))

print("Next Reminder v1.3.9 routine stop controls applied successfully.")
