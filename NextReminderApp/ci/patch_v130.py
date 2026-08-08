#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:200]!r}")
    path.write_text(text.replace(old, new, 1))


def regex_once(path: Path, pattern: str, replacement: str) -> None:
    text = path.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"Expected one regex match in {path}, found {count}: {pattern}")
    path.write_text(updated)


# MARK: Replace the bottom Automations tab with DeepSeek AI.
root = SOURCES / "RootReminders.swift"
replace_once(root, "    case automations", "    case ai")
replace_once(
    root,
    '''            NavigationStack {
                AutomationsView()
            }
            .tabItem { Label("Automations", systemImage: "paperplane.fill") }
            .tag(AppTab.automations)''',
    '''            NavigationStack {
                DeepSeekAIView()
            }
            .tabItem { Label("AI", systemImage: "sparkles") }
            .tag(AppTab.ai)'''
)
replace_once(
    root,
    '''            selectedTab = .automations
            openedAutomation = IdentifiedAutomationID(id: id)''',
    '''            selectedTab = .settings
            openedAutomation = IdentifiedAutomationID(id: id)'''
)


# MARK: Add complete restore support to ReminderStore.
services = SOURCES / "Services.swift"
replace_once(
    services,
    '''    func category(for id: UUID) -> ReminderCategory {
        categories.first(where: { $0.id == id }) ?? .general
    }

    func isUnattended''',
    '''    func category(for id: UUID) -> ReminderCategory {
        categories.first(where: { $0.id == id }) ?? .general
    }

    func replaceAll(reminders newReminders: [ReminderItem], categories newCategories: [ReminderCategory]) {
        let previousReminders = reminders
        reminders = newReminders
        categories = newCategories
        ensureDefaultCategories()
        save()
        refreshUnattendedBadge()

        let restoredSchedule = reminders
            .filter { !$0.isCompleted }
            .map { ($0, category(for: $0.categoryID).name) }

        Task {
            for reminder in previousReminders {
                await NotificationManager.shared.cancel(reminderID: reminder.id)
                await EmailAutomationManager.shared.cancel(reminderID: reminder.id)
            }
            for (reminder, categoryName) in restoredSchedule {
                await NotificationManager.shared.schedule(reminder, categoryName: categoryName)
                await EmailAutomationManager.shared.sync(reminder)
            }
        }
    }

    func isUnattended'''
)


# MARK: Reload restored email settings without rebuilding the app object graph.
email_core = SOURCES / "EmailAutomationCore.swift"
replace_once(
    email_core,
    '''    func save(_ value: EmailAutomationSettings) {
        var cleaned = value''',
    '''    func reloadFromDisk() {
        settings = EmailAutomationSettings.load()
        statusMessage = "Email settings restored. Reconnect the sender account if required."
        NotificationCenter.default.post(name: .nextEmailAutomationSettingsChanged, object: nil)
    }

    func save(_ value: EmailAutomationSettings) {
        var cleaned = value'''
)


# MARK: Move the complete automation center into Settings and add backup + AI setup.
settings = SOURCES / "Settings.swift"
replace_once(
    settings,
    '''                notificationSection
                managementSection
                automationSection
                aboutSection''',
    '''                notificationSection
                managementSection
                backupSection
                automationSection
                aiSection
                aboutSection'''
)
replace_once(
    settings,
    '''    private var automationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Automations")

            NavigationLink {
                EmailAutomationSettingsView()''',
    '''    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Data Protection")
            NavigationLink {
                BackupRestoreView()
            } label: {
                settingsRow(
                    icon: "externaldrive.badge.icloud.fill",
                    title: "Backup & Restore",
                    subtitle: "Save reminders and settings to iCloud Drive, Google Drive, or Dropbox"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var automationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Automations")

            NavigationLink {
                AutomationsView()
            } label: {
                settingsRow(
                    icon: "paperplane.circle.fill",
                    title: "Automation Center",
                    subtitle: "Create, review, pause, and manage social automations"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                EmailAutomationSettingsView()'''
)
replace_once(
    settings,
    '''    private var aboutSection: some View {''',
    '''    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "AI Assistant")
            NavigationLink {
                DeepSeekSettingsView()
            } label: {
                settingsRow(
                    icon: "sparkles",
                    title: "DeepSeek AI Settings",
                    subtitle: "Secure API key, V4 model selection, thinking mode, and reminder context"
                )
            }
            .buttonStyle(.plain)

            Text("The AI tab can analyze active reminders only when reminder context is enabled. It never completes or changes reminders automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var aboutSection: some View {'''
)


# MARK: Fix DeepSeek file access levels for shared request values in the same module.
ai = SOURCES / "DeepSeekAI.swift"
ai_text = ai.read_text()
ai_text = ai_text.replace("private struct DeepSeekAPIMessage", "struct DeepSeekAPIMessage")
ai_text = ai_text.replace("private struct DeepSeekThinking", "struct DeepSeekThinking")
ai_text = ai_text.replace("private struct DeepSeekChatRequest", "struct DeepSeekChatRequest")
ai_text = ai_text.replace("private struct DeepSeekChatResponse", "struct DeepSeekChatResponse")
ai_text = ai_text.replace("private struct DeepSeekErrorResponse", "struct DeepSeekErrorResponse")
ai.write_text(ai_text)


# MARK: Version metadata and user-agent identifiers.
project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.2.5"', 'CFBundleShortVersionString: "1.3.0"')
project_text = project_text.replace('CFBundleVersion: "9"', 'CFBundleVersion: "10"')
project_text = project_text.replace('MARKETING_VERSION: "1.2.5"', 'MARKETING_VERSION: "1.3.0"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "9"', 'CURRENT_PROJECT_VERSION: "10"')
project.write_text(project_text)

settings.write_text(settings.read_text().replace("Version 1.2.5 • iOS 16.0+", "Version 1.3.0 • iOS 16.0+"))

for path in SOURCES.glob("*.swift"):
    text = path.read_text().replace("NextReminder-iOS/1.2.5", "NextReminder-iOS/1.3.0")
    path.write_text(text)

print("Next Reminder v1.3.0 patches applied successfully.")
