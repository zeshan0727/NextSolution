#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).parents[1] / "NextReminder" / "Sources" / "Editor.swift"
text = path.read_text()

old_can_save = '''    private var canSave: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let validReminderTime = dueDate > Date().addingTimeInterval(-60)
        let validDeadline = !hasDeadline || deadlineDate > dueDate
        return hasTitle && validReminderTime && validDeadline
    }
'''
new_can_save = '''    private var canSave: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isExistingRepeatingReminder = reminder != nil && repeatRule != .never
        let validReminderTime = dueDate > Date().addingTimeInterval(-60) || isExistingRepeatingReminder
        let validDeadline = !hasDeadline || deadlineDate > dueDate
        return hasTitle && validReminderTime && validDeadline
    }

    private var reminderDateRange: ClosedRange<Date> {
        if reminder != nil && repeatRule != .never {
            return Date.distantPast...Date.distantFuture
        }
        return Date()...Date.distantFuture
    }
'''

old_picker = '''                selection: $dueDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
'''
new_picker = '''                selection: $dueDate,
                in: reminderDateRange,
                displayedComponents: [.date, .hourAndMinute]
'''

if old_can_save not in text:
    raise SystemExit("canSave block not found")
if old_picker not in text:
    raise SystemExit("reminder DatePicker range not found")

text = text.replace(old_can_save, new_can_save, 1)
text = text.replace(old_picker, new_picker, 1)
path.write_text(text)
print("Next Reminder v1.3.16 repeating reminder edit/save fix applied successfully.")
