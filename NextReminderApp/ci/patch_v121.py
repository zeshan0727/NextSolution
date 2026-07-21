#!/usr/bin/env python3
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:100]!r}")
    path.write_text(text.replace(old, new, 1))


def regex_once(path: Path, pattern: str, replacement: str) -> None:
    text = path.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"Expected one regex match in {path}, found {count}: {pattern}")
    path.write_text(updated)


# MARK: Reminder editor — selected days and Gmail readiness
editor = SOURCES / "Editor.swift"
replace_once(
    editor,
    "    @State private var repeatRule: ReminderRepeat\n    @State private var alertOffsets: Set<ReminderAlertOffset>",
    "    @State private var repeatRule: ReminderRepeat\n    @State private var selectedWeekdays: Set<Int>\n    @State private var alertOffsets: Set<ReminderAlertOffset>"
)
replace_once(
    editor,
    "        _repeatRule = State(initialValue: reminder?.repeatRule ?? .never)\n        _alertOffsets = State(initialValue: reminder?.alertOffsets ?? [.thirtyMinutes])",
    "        _repeatRule = State(initialValue: reminder?.repeatRule ?? .never)\n        _selectedWeekdays = State(\n            initialValue: SelectedDayScheduleStore.shared.weekdays(for: reminder?.id)\n        )\n        _alertOffsets = State(initialValue: reminder?.alertOffsets ?? [.thirtyMinutes])"
)
replace_once(
    editor,
    "        let validDeadline = !hasDeadline || deadlineDate > dueDate\n        return hasTitle && validReminderTime && validDeadline",
    "        let validDeadline = !hasDeadline || deadlineDate > dueDate\n        let validRepeat = repeatRule != .daily || !selectedWeekdays.isEmpty\n        return hasTitle && validReminderTime && validDeadline && validRepeat"
)
replace_once(
    editor,
    "        return settings.enabled && settings.hasValidRecipient && settings.automaticConnectorReady",
    "        return settings.enabled && settings.fullyConfigured"
)
regex_once(
    editor,
    r"    private var repeatSection: some View \{.*?\n    \}\n\n    private func requestPermissionIfNeeded",
    '''    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Repeat")
            Menu {
                Button("Selected Days") { repeatRule = .daily }
                ForEach(ReminderRepeat.allCases.filter { $0 != .daily }) { rule in
                    Button(rule.title) { repeatRule = rule }
                }
            } label: {
                HStack {
                    Image(systemName: "repeat")
                        .foregroundStyle(.nextOrange)
                    Text(repeatRule == .daily ? "Selected Days" : repeatRule.title)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .nextCard()
            }
            .buttonStyle(.plain)

            if repeatRule == .daily {
                SelectedWeekdaysPicker(selection: $selectedWeekdays)
            }
        }
    }

    private func requestPermissionIfNeeded'''
)
regex_once(
    editor,
    r"    private func saveReminder\(\) \{.*?\n    \}\n\}",
    '''    private func saveReminder() {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedAlerts: Set<ReminderAlertOffset> = notificationsEnabled && alertOffsets.isEmpty
            ? [.atTime]
            : alertOffsets
        let finalDeadline = hasDeadline ? deadlineDate : nil

        if var existing = reminder {
            existing.title = cleanedTitle
            existing.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.dueDate = dueDate
            existing.deadlineDate = finalDeadline
            existing.priority = priority
            existing.categoryID = categoryID
            existing.repeatRule = repeatRule
            existing.alertOffsets = selectedAlerts
            existing.notificationsEnabled = notificationsEnabled
            existing.emailWhenDue = emailWhenDue && emailSetupReady

            if repeatRule == .daily {
                SelectedDayScheduleStore.shared.save(selectedWeekdays, for: existing.id)
            } else {
                SelectedDayScheduleStore.shared.remove(for: existing.id)
            }
            store.update(existing)
        } else {
            let newID = UUID()
            let newReminder = ReminderItem(
                id: newID,
                title: cleanedTitle,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                dueDate: dueDate,
                deadlineDate: finalDeadline,
                priority: priority,
                categoryID: categoryID,
                repeatRule: repeatRule,
                alertOffsets: selectedAlerts,
                notificationsEnabled: notificationsEnabled,
                emailWhenDue: emailWhenDue && emailSetupReady
            )

            if repeatRule == .daily {
                SelectedDayScheduleStore.shared.save(selectedWeekdays, for: newID)
            }
            store.add(newReminder)
        }
        dismiss()
    }
}'''
)

# MARK: Recurring service behavior
services = SOURCES / "Services.swift"
replace_once(
    services,
    "            await EmailAutomationManager.shared.cancel(reminderID: reminder.id)\n        }\n    }\n\n    func complete",
    "            await EmailAutomationManager.shared.cancel(reminderID: reminder.id)\n        }\n        SelectedDayScheduleStore.shared.remove(for: reminder.id)\n    }\n\n    func complete"
)
replace_once(
    services,
    "        if let nextDate = reminder.repeatRule.nextDate(after: reminder.dueDate) {",
    "        if let nextDate = RepeatScheduleEngine.nextDate(for: reminder, after: reminder.dueDate) {"
)
replace_once(
    services,
    "            reminders.append(nextReminder)\n            scheduleServices(for: nextReminder)",
    "            if reminder.repeatRule == .daily {\n                SelectedDayScheduleStore.shared.copy(from: reminder.id, to: nextReminder.id)\n            }\n            reminders.append(nextReminder)\n            scheduleServices(for: nextReminder)"
)

# MARK: Dashboard performance card
root = SOURCES / "RootReminders.swift"
replace_once(
    root,
    "                header\n                quickFilters",
    "                header\n                WorkweekPerformanceCard()\n                quickFilters"
)

# MARK: Reminder details repeat description
detail = SOURCES / "Detail.swift"
replace_once(
    detail,
    'detailRow(icon: "repeat", title: "Repeat", value: reminder.repeatRule.title)',
    'detailRow(\n                icon: "repeat",\n                title: "Repeat",\n                value: SelectedDayScheduleStore.shared.description(for: reminder)\n            )'
)

# MARK: Email settings — real Gmail connection button
email_view = SOURCES / "EmailAutomationSettingsView.swift"
replace_once(
    email_view,
    "        !draft.enabled || (draft.hasValidRecipient && draft.automaticConnectorReady)",
    "        !draft.enabled || draft.fullyConfigured"
)
regex_once(
    email_view,
    r"    @ViewBuilder\n    private var connectorSection: some View \{.*?\n    \}\n\n    private var templateSection",
    '''    @ViewBuilder
    private var connectorSection: some View {
        if draft.deliveryMethod == .gmailAutomatic {
            GmailConnectionCard(draft: $draft)
        } else if draft.deliveryMethod.isAutomatic {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Automatic Sender Connection")
                TextField("Sender label, e.g. Work Mail", text: $draft.senderLabel)
                    .padding(14)
                    .nextCard()
                TextField("Remote connector ID", text: $draft.remoteConnectorID)
                    .textInputAutocapitalization(.never)
                    .padding(14)
                    .nextCard()

                HStack(spacing: 10) {
                    Image(
                        systemName: automationStore.cloudConfiguration.isConfigured
                            ? "checkmark.shield.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    Text(
                        automationStore.cloudConfiguration.isConfigured
                            ? "Scheduler connected"
                            : "Configure the HTTPS scheduler in Automation Connections"
                    )
                }
                .font(.caption.bold())
                .foregroundStyle(
                    automationStore.cloudConfiguration.isConfigured ? Color.green : Color.orange
                )

                Text("For iCloud Mail or another SMTP service, the connector ID is generated by your secure scheduler after that sender is connected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var templateSection'''
)

# Require a verified Gmail connection inside the email manager.
email_core = SOURCES / "EmailAutomationCore.swift"
replace_once(
    email_core,
    "        guard settings.automaticConnectorReady else { throw EmailAutomationError.missingConnector }",
    "        guard settings.fullyConfigured else { throw EmailAutomationError.missingConnector }"
)
replace_once(
    email_core,
    'request.setValue("NextReminder-iOS/1.2", forHTTPHeaderField: "User-Agent")',
    'request.setValue("NextReminder-iOS/1.2.1", forHTTPHeaderField: "User-Agent")'
)

# MARK: Version and callback URL scheme
project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.2.0"', 'CFBundleShortVersionString: "1.2.1"')
project_text = project_text.replace('CFBundleVersion: "4"', 'CFBundleVersion: "5"')
project_text = project_text.replace('MARKETING_VERSION: "1.2.0"', 'MARKETING_VERSION: "1.2.1"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "4"', 'CURRENT_PROJECT_VERSION: "5"')
if "CFBundleURLTypes:" not in project_text:
    project_text = project_text.replace(
        "        LSApplicationQueriesSchemes:\n          - whatsapp\n          - instagram\n          - twitter\n",
        "        LSApplicationQueriesSchemes:\n          - whatsapp\n          - instagram\n          - twitter\n        CFBundleURLTypes:\n          - CFBundleURLName: com.nextsolution.nextreminder.oauth\n            CFBundleURLSchemes:\n              - nextreminder\n"
    )
project.write_text(project_text)

settings = SOURCES / "Settings.swift"
settings_text = settings.read_text().replace("Version 1.2.0 • iOS 16.0+", "Version 1.2.1 • iOS 16.0+")
settings.write_text(settings_text)

info = ROOT / "NextReminder" / "Resources" / "Info.plist"
with info.open("rb") as handle:
    plist = plistlib.load(handle)
plist["CFBundleURLTypes"] = [
    {
        "CFBundleURLName": "com.nextsolution.nextreminder.oauth",
        "CFBundleURLSchemes": ["nextreminder"],
    }
]
with info.open("wb") as handle:
    plistlib.dump(plist, handle, sort_keys=False)

print("Next Reminder v1.2.1 patches applied successfully.")
