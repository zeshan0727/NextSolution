#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:260]!r}")
    path.write_text(text.replace(old, new, 1))

# 1) Make standalone email scheduling obvious from the normal Reminders screen.
# The cumulative app no longer has a center Add tab, so expose both a dedicated
# envelope-clock shortcut and a New Scheduled Email item in the existing + menu.
root_view = SOURCES / "RootReminders.swift"
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
    '''    @State private var isAddingReminder = false
''',
    '''    @State private var isAddingReminder = false
    @State private var isAddingScheduledEmail = false
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
                Button {
                    isShowingFilters = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Advanced filters")
                Button {
                    isAddingReminder = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New reminder")
            }''',
    '''            ToolbarItemGroup(placement: .navigationBarTrailing) {
                NavigationLink {
                    EmailSchedulesView()
                        .environmentObject(scheduledEmailStore)
                } label: {
                    Image(systemName: "envelope.badge.clock.fill")
                }
                .accessibilityLabel("Automatic email schedules")

                NavigationLink {
                    CalendarRemindersView()
                } label: {
                    Image(systemName: "calendar")
                }
                Button {
                    isShowingFilters = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Advanced filters")
                Menu {
                    Button {
                        isAddingReminder = true
                    } label: {
                        Label("New Reminder", systemImage: "bell.badge.fill")
                    }
                    Button {
                        isAddingScheduledEmail = true
                    } label: {
                        Label("New Scheduled Email", systemImage: "envelope.badge.clock.fill")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create")
            }'''
)
replace_once(
    root_view,
    '''        .sheet(isPresented: $isAddingReminder) {
            NavigationStack {
                ReminderEditorView(reminder: nil)
            }
            .environmentObject(store)
        }
''',
    '''        .sheet(isPresented: $isAddingReminder) {
            NavigationStack {
                ReminderEditorView(reminder: nil)
            }
            .environmentObject(store)
        }
        .sheet(isPresented: $isAddingScheduledEmail) {
            NavigationStack {
                EmailScheduleEditorView(item: nil)
            }
            .environmentObject(scheduledEmailStore)
        }
'''
)

# 2) The iOS 16.0 RootHide due live-card fallback writes Completed / Extend
# directly to NextReminderDatabase.json while the app is suspended. Reload those
# changes whenever the app becomes active. Only rebuild local notifications here;
# do NOT touch email automation, so opening the app can never cause email sending.
services = SOURCES / "Services.swift"
anchor = '''    var pendingReminders: [ReminderItem] {
'''
method = '''    func refreshFromDisk() {
        do {
            let database = try persistence.load()
            reminders = database.reminders
            categories = database.categories.isEmpty ? [.personal, .general] : database.categories
            let pending = pendingReminders
            let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
            Task {
                for reminder in pending {
                    await NotificationManager.shared.schedule(
                        reminder,
                        categoryName: categoryNames[reminder.categoryID] ?? ReminderCategory.general.name
                    )
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

# 3) Version 1.3.20 build 30.
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
