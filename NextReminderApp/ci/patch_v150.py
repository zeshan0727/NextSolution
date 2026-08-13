#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:260]!r}")
    path.write_text(text.replace(old, new, 1))

# Make standalone email scheduling impossible to miss: expose it directly from
# the center Add button and from a dedicated envelope-clock toolbar button.
root_view = SOURCES / "RootReminders.swift"
replace_once(
    root_view,
    '''    @EnvironmentObject private var emailAutomationStore: EmailAutomationStore

    @State private var selectedTab: AppTab = .reminders''',
    '''    @EnvironmentObject private var emailAutomationStore: EmailAutomationStore
    @EnvironmentObject private var scheduledEmailStore: ScheduledEmailStore

    @State private var selectedTab: AppTab = .reminders'''
)
replace_once(
    root_view,
    '''    @State private var openedEmailReminder: IdentifiedReminderID?
''',
    '''    @State private var openedEmailReminder: IdentifiedReminderID?
    @State private var showNewScheduledEmail = false
'''
)
replace_once(
    root_view,
    '''            Button("New Reminder") { addFlow = .reminder }
            Button("New Social Automation") { addFlow = .automation }
            Button("Cancel", role: .cancel) {}''',
    '''            Button("New Reminder") { addFlow = .reminder }
            Button("New Scheduled Email") { showNewScheduledEmail = true }
            Button("New Social Automation") { addFlow = .automation }
            Button("Cancel", role: .cancel) {}'''
)
replace_once(
    root_view,
    '''        .sheet(item: $openedAutomation) { item in
''',
    '''        .sheet(isPresented: $showNewScheduledEmail) {
            NavigationStack {
                EmailScheduleEditorView(item: nil)
            }
            .environmentObject(scheduledEmailStore)
        }
        .sheet(item: $openedAutomation) { item in
'''
)
replace_once(
    root_view,
    '''struct RemindersView: View {
    @EnvironmentObject private var store: ReminderStore
''',
    '''struct RemindersView: View {
    @EnvironmentObject private var store: ReminderStore
    @EnvironmentObject private var scheduledEmailStore: ScheduledEmailStore
'''
)
replace_once(
    root_view,
    '''            ToolbarItemGroup(placement: .navigationBarTrailing) {
                NavigationLink {
                    CalendarRemindersView()
                } label: {
                    Image(systemName: "calendar")
                }
''',
    '''            ToolbarItemGroup(placement: .navigationBarTrailing) {
                NavigationLink {
                    EmailSchedulesView()
                        .environmentObject(scheduledEmailStore)
                } label: {
                    Image(systemName: "envelope.badge.clock.fill")
                }
                .accessibilityLabel("Email schedules")
                NavigationLink {
                    CalendarRemindersView()
                } label: {
                    Image(systemName: "calendar")
                }
'''
)

# The iOS 16.0 RootHide live-card fallback updates the same JSON database from
# SpringBoard. Refresh from disk when the app becomes active so Completed / Extend
# changes are immediately reflected in the app without requiring a force quit.
services = SOURCES / "Services.swift"
anchor = '''    var pendingReminders: [ReminderItem] {
'''
method = '''    func refreshFromDisk() {
        do {
            let database = try persistence.load()
            reminders = database.reminders
            categories = database.categories.isEmpty ? [.personal, .general] : database.categories
            let pending = pendingReminders
            Task {
                for reminder in pending {
                    await NotificationManager.shared.schedule(
                        reminder,
                        categoryName: category(for: reminder.categoryID).name
                    )
                    await EmailAutomationManager.shared.sync(reminder)
                }
            }
        } catch {
            lastErrorMessage = "Could not refresh reminder changes from the Lock Screen: \(error.localizedDescription)"
        }
    }

'''
if anchor not in services.read_text():
    raise SystemExit("ReminderStore pendingReminders anchor not found")
services.write_text(services.read_text().replace(anchor, method + anchor, 1))

app = SOURCES / "App.swift"
replace_once(
    app,
    '''                    automationStore.refreshDueStatuses()
                    scheduledEmailStore.refresh()
''',
    '''                    store.refreshFromDisk()
                    automationStore.refreshDueStatuses()
                    scheduledEmailStore.refresh()
'''
)

# Version 1.3.20 build 30.
project = ROOT / "project.yml"
text = project.read_text()
text = text.replace('CFBundleShortVersionString: "1.3.19"', 'CFBundleShortVersionString: "1.3.20"')
text = text.replace('CFBundleVersion: "29"', 'CFBundleVersion: "30"')
text = text.replace('MARKETING_VERSION: "1.3.19"', 'MARKETING_VERSION: "1.3.20"')
text = text.replace('CURRENT_PROJECT_VERSION: "29"', 'CURRENT_PROJECT_VERSION: "30"')
project.write_text(text)

ext_plist = ROOT / "NextReminderLiveActivity" / "Info.plist"
plist_text = ext_plist.read_text().replace('<string>1.3.19</string>', '<string>1.3.20</string>').replace('<string>29</string>', '<string>30</string>')
ext_plist.write_text(plist_text)

settings = SOURCES / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.3.19 • iOS 16.0+", "Version 1.3.20 • iOS 16.0+"))
for swift in SOURCES.glob("*.swift"):
    swift.write_text(swift.read_text().replace("NextReminder-iOS/1.3.19", "NextReminder-iOS/1.3.20"))

print("Next Reminder v1.3.20 visible email scheduler and RootHide live-card sync patch applied successfully.")
