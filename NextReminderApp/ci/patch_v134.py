#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:240]!r}")
    path.write_text(text.replace(old, new, 1))


actions = SOURCES / "CompletedFilterActions.swift"

replace_once(
    actions,
    '''        let base = Self.originalDueDate(for: reminder)
        _newDate = State(initialValue: base.addingTimeInterval(3600))''',
    '''        let base = reminder.dueDate
        _newDate = State(initialValue: base.addingTimeInterval(3600))'''
)
replace_once(
    actions,
    '''                    Text("Quick options always use the reminder's first/original due date and time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Original due: \(originalDueDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption.bold())
                        .foregroundStyle(.nextOrange)''',
    '''                    Text("Quick options extend from the reminder's current due date and time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Current due: \(reminder.dueDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption.bold())
                        .foregroundStyle(.nextOrange)'''
)
replace_once(
    actions,
    '''                        Text("+1 Hour, +2 Hours, and +1 Day are calculated from the first due time, even after the reminder has already been extended.")''',
    '''                        Text("Each quick extension is added to the latest due time, so repeated extensions accumulate correctly.")'''
)
replace_once(
    actions,
    '''    private static func originalDueDate(for reminder: ReminderItem) -> Date {
        reminder.history
            .filter { $0.action == .extended && $0.previousDueDate != nil }
            .sorted { $0.date < $1.date }
            .first?.previousDueDate ?? reminder.dueDate
    }

    private var originalDueDate: Date {
        Self.originalDueDate(for: reminder)
    }

    private func quickButton(title: String, seconds: TimeInterval) -> some View {
        Button {
            newDate = originalDueDate.addingTimeInterval(seconds)''',
    '''    private func quickButton(title: String, seconds: TimeInterval) -> some View {
        Button {
            newDate = reminder.dueDate.addingTimeInterval(seconds)'''
)

project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.3.3"', 'CFBundleShortVersionString: "1.3.4"')
project_text = project_text.replace('CFBundleVersion: "13"', 'CFBundleVersion: "14"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.3"', 'MARKETING_VERSION: "1.3.4"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "13"', 'CURRENT_PROJECT_VERSION: "14"')
project.write_text(project_text)

settings = SOURCES / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.3.3 • iOS 16.0+", "Version 1.3.4 • iOS 16.0+"))

for path in SOURCES.glob("*.swift"):
    path.write_text(path.read_text().replace("NextReminder-iOS/1.3.3", "NextReminder-iOS/1.3.4"))

print("Next Reminder v1.3.4 cumulative extension fix applied successfully.")
