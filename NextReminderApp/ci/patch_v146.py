#!/usr/bin/env python3
from pathlib import Path
import re

path = Path(__file__).parents[1] / "NextReminder" / "Sources" / "Editor.swift"
text = path.read_text()

replacement = '''    private var canSave: Bool {
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

pattern = re.compile(
    r"    private var canSave: Bool \{.*?\n    \}\n\n(?=    private var emailSetupReady: Bool \{)",
    re.S,
)
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit("canSave section not found")

picker_pattern = re.compile(
    r"(DatePicker\(\s*\n\s*\"Alert date and time\",\s*\n\s*selection: \$dueDate,\s*\n\s*)in: [^\n]+,",
    re.S,
)
text, count = picker_pattern.subn(r"\1in: reminderDateRange,", text, count=1)
if count != 1:
    raise SystemExit("reminder DatePicker range not found")

path.write_text(text)
print("Next Reminder v1.3.16 repeating reminder edit/save fix applied successfully.")
