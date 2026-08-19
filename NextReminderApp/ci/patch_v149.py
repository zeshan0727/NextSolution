#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:260]!r}")
    path.write_text(text.replace(old, new, 1))

# 1) App wiring: standalone email schedules + Live Activity URL actions/lifecycle.
app = SOURCES / "App.swift"
replace_once(
    app,
    '''    @StateObject private var emailAutomationStore = EmailAutomationStore()''',
    '''    @StateObject private var emailAutomationStore = EmailAutomationStore()
    @StateObject private var scheduledEmailStore = ScheduledEmailStore()'''
)
replace_once(
    app,
    '''                .environmentObject(emailAutomationStore)
                .preferredColorScheme(themeMode.colorScheme)''',
    '''                .environmentObject(emailAutomationStore)
                .environmentObject(scheduledEmailStore)
                .preferredColorScheme(themeMode.colorScheme)'''
)
replace_once(
    app,
    '''                .onOpenURL { url in
                    Task { await QuickReminderImporter.handle(url, store: store) }
                }''',
    '''                .onOpenURL { url in
                    Task {
                        if await ReminderLiveActionHandler.handle(url, store: store) { return }
                        await QuickReminderImporter.handle(url, store: store)
                    }
                }'''
)
# Other cumulative patches add work inside the scenePhase block, so extend the
# stable refresh call rather than replacing the whole block.
replace_once(
    app,
    '''                    automationStore.refreshDueStatuses()
''',
    '''                    automationStore.refreshDueStatuses()
                    scheduledEmailStore.refresh()
                    Task {
                        await ReminderLiveActivityManager.shared.syncDueActivities(
                            reminders: store.pendingReminders,
                            categoryName: { store.category(for: $0).name }
                        )
                    }
'''
)

# 2) Automations screen gets a dedicated Email Schedules window, separate from reminders.
automations = SOURCES / "AutomationsView.swift"
replace_once(
    automations,
    '''    @EnvironmentObject private var emailStore: EmailAutomationStore''',
    '''    @EnvironmentObject private var emailStore: EmailAutomationStore
    @EnvironmentObject private var scheduledEmailStore: ScheduledEmailStore'''
)
replace_once(
    automations,
    '''                emailAutomationCard
                listFilters''',
    '''                emailAutomationCard
                emailSchedulesCard
                listFilters'''
)
anchor = '''    private var emailAutomationSubtitle: String {
'''
if anchor not in automations.read_text():
    raise SystemExit("Could not find emailAutomationSubtitle anchor")
card = '''    private var emailSchedulesCard: some View {
        NavigationLink {
            EmailSchedulesView()
                .environmentObject(scheduledEmailStore)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.nextOrange.opacity(0.16))
                    Image(systemName: "envelope.badge.clock.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.nextOrange)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Email Schedules")
                        .font(.headline)
                    Text("\(scheduledEmailStore.items.filter { $0.isEnabled }.count) active • Daily, weekly or quarterly • Separate from reminders")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(15)
            .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(Color.nextOrange.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

'''
automations.write_text(automations.read_text().replace(anchor, card + anchor, 1))

# 3) Actionable lock-screen reminder fallback for iOS 16.0 and Live Activity lifecycle.
services = SOURCES / "Services.swift"
replace_once(
    services,
    '''        let complete = UNTextInputNotificationAction(
            identifier: Self.completeActionIdentifier,
            title: "Complete with Comment",
            options: [],
            textInputButtonTitle: "Complete",
            textInputPlaceholder: "Optional completion comment"
        )
        let snooze = UNNotificationAction(
            identifier: Self.snoozeActionIdentifier,
            title: "Snooze 10 Minutes",
            options: []
        )''',
    '''        let complete = UNNotificationAction(
            identifier: Self.completeActionIdentifier,
            title: "Completed",
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: Self.snoozeActionIdentifier,
            title: "Extend 10 Minutes",
            options: []
        )'''
)
replace_once(
    services,
    '''        case .snooze:
            Task { await NotificationManager.shared.scheduleSnooze(reminder: reminder) }''',
    '''        case .snooze:
            Task { await ReminderLiveActivityManager.shared.end(reminderID: reminder.id) }
            extend(
                reminder,
                to: Date().addingTimeInterval(10 * 60),
                comment: "Extended 10 minutes from Lock Screen"
            )'''
)
replace_once(
    services,
    '''            await NotificationManager.shared.schedule(
                reminder,
                categoryName: categoryName
            )
            await EmailAutomationManager.shared.sync(reminder)''',
    '''            await NotificationManager.shared.schedule(
                reminder,
                categoryName: categoryName
            )
            await ReminderLiveActivityManager.shared.sync(reminder, categoryName: categoryName)
            await EmailAutomationManager.shared.sync(reminder)'''
)

# Add Live Activity cancellation anywhere a reminder is permanently removed/completed.
services_text = services.read_text()
services_text = services_text.replace(
    '''            await NotificationManager.shared.cancel(reminderID: reminder.id)
            await EmailAutomationManager.shared.cancel(reminderID: reminder.id)''',
    '''            await NotificationManager.shared.cancel(reminderID: reminder.id)
            await EmailAutomationManager.shared.cancel(reminderID: reminder.id)
            await ReminderLiveActivityManager.shared.end(reminderID: reminder.id)'''
)
services.write_text(services_text)

# 4) Native Live Activity extension + version 1.3.19 build 29.
project = ROOT / "project.yml"
text = project.read_text()
text = text.replace('CFBundleShortVersionString: "1.3.18"', 'CFBundleShortVersionString: "1.3.19"')
text = text.replace('CFBundleVersion: "28"', 'CFBundleVersion: "29"')
text = text.replace('MARKETING_VERSION: "1.3.18"', 'MARKETING_VERSION: "1.3.19"')
text = text.replace('CURRENT_PROJECT_VERSION: "28"', 'CURRENT_PROJECT_VERSION: "29"')
if 'NSSupportsLiveActivities: true' not in text:
    info_anchor = '        CADisableMinimumFrameDurationOnPhone: true\n'
    if info_anchor in text:
        text = text.replace(info_anchor, info_anchor + '        NSSupportsLiveActivities: true\n', 1)
    else:
        text = text.replace('        UIRequiresFullScreen: true\n', '        UIRequiresFullScreen: true\n        NSSupportsLiveActivities: true\n', 1)

if 'NextReminderLiveActivity:' not in text:
    dependency_anchor = '''    scheme:
      testTargets: []
      gatherCoverageData: false
'''
    if dependency_anchor not in text:
        raise SystemExit('Could not find app scheme anchor for extension dependency')
    text = text.replace(
        dependency_anchor,
        '''    dependencies:
      - target: NextReminderLiveActivity
        embed: true
    scheme:
      testTargets: []
      gatherCoverageData: false

  NextReminderLiveActivity:
    type: app-extension
    platform: iOS
    deploymentTarget: "16.1"
    sources:
      - path: NextReminderLiveActivity
      - path: NextReminder/Sources/ReminderActivityAttributes.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.nextsolution.nextreminder.liveactivity
        PRODUCT_NAME: NextReminderLiveActivity
        MARKETING_VERSION: "1.3.19"
        CURRENT_PROJECT_VERSION: "29"
        INFOPLIST_FILE: NextReminderLiveActivity/Info.plist
        SKIP_INSTALL: YES
        APPLICATION_EXTENSION_API_ONLY: YES
        CODE_SIGN_STYLE: Automatic
        GENERATE_INFOPLIST_FILE: NO
''',
        1
    )
project.write_text(text)

settings = SOURCES / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.3.18 • iOS 16.0+", "Version 1.3.19 • iOS 16.0+"))
for swift in SOURCES.glob("*.swift"):
    swift.write_text(swift.read_text().replace("NextReminder-iOS/1.3.18", "NextReminder-iOS/1.3.19"))

print("Next Reminder v1.3.19 Live Activity and standalone email schedules patch applied successfully.")
