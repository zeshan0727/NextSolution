#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "NextReminder" / "Sources" / "Editor.swift"
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

project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.3.15"', 'CFBundleShortVersionString: "1.3.16"')
project_text = project_text.replace('CFBundleVersion: "25"', 'CFBundleVersion: "26"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.15"', 'MARKETING_VERSION: "1.3.16"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "25"', 'CURRENT_PROJECT_VERSION: "26"')
project.write_text(project_text)

settings = ROOT / "NextReminder" / "Sources" / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.3.15 • iOS 16.0+", "Version 1.3.16 • iOS 16.0+"))
for swift in (ROOT / "NextReminder" / "Sources").glob("*.swift"):
    swift.write_text(swift.read_text().replace("NextReminder-iOS/1.3.15", "NextReminder-iOS/1.3.16"))

print("Next Reminder v1.3.16 repeating reminder edit/save fix applied successfully.")
