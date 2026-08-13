#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:260]!r}")
    path.write_text(text.replace(old, new, 1))

# v1.3.20 already exposes Email Schedules with the envelope-clock toolbar icon
# and + -> New Scheduled Email. Add a large always-visible summary card to the
# main Reminders screen so saved email-only schedules are impossible to miss.
root = SOURCES / "RootReminders.swift"
replace_once(
    root,
    '''                header
                WorkweekPerformanceCard()
                quickFilters
''',
    '''                header
                emailSchedulesSummary
                WorkweekPerformanceCard()
                quickFilters
'''
)

anchor = '''    private var header: some View {
'''
summary_view = '''    private var emailSchedulesSummary: some View {
        NavigationLink {
            EmailSchedulesView()
                .environmentObject(scheduledEmailStore)
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.nextOrange.opacity(0.14))
                    Image(systemName: "envelope.badge.clock.fill")
                        .font(.title3.bold())
                        .foregroundStyle(.nextOrange)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Email Schedules")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if scheduledEmailStore.items.isEmpty {
                        Text("No email-only schedules yet • Tap to create or view")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\\(scheduledEmailStore.items.count) saved • \\(scheduledEmailStore.items.filter { $0.isEnabled }.count) active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let next = scheduledEmailStore.items.compactMap({ $0.nextOccurrence }).min() {
                            Text("Next email: \\(next.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.nextOrange.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

'''
if anchor not in root.read_text():
    raise SystemExit("Reminders header anchor not found")
root.write_text(root.read_text().replace(anchor, summary_view + anchor, 1))

# Every reminder database save notifies SpringBoard immediately. This lets the
# System Aperture tweak remove a due item as soon as the reminder is deleted,
# completed, or extended instead of showing stale data.
services = SOURCES / "Services.swift"
if 'import CoreFoundation\n' not in services.read_text():
    replace_once(services, 'import Combine\n', 'import Combine\nimport CoreFoundation\n')
replace_once(
    services,
    '''        let data = try encoder.encode(database)
        try data.write(to: fileURL, options: [.atomic])
''',
    '''        let data = try encoder.encode(database)
        try data.write(to: fileURL, options: [.atomic])
        let notificationName = "com.nextsolution.nextreminder.database.changed" as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
'''
)

# Version 1.3.21 build 31.
project = ROOT / "project.yml"
text = project.read_text()
text = text.replace('CFBundleShortVersionString: "1.3.20"', 'CFBundleShortVersionString: "1.3.21"')
text = text.replace('CFBundleVersion: "30"', 'CFBundleVersion: "31"')
text = text.replace('MARKETING_VERSION: "1.3.20"', 'MARKETING_VERSION: "1.3.21"')
text = text.replace('CURRENT_PROJECT_VERSION: "30"', 'CURRENT_PROJECT_VERSION: "31"')
project.write_text(text)

ext_plist = ROOT / "NextReminderLiveActivity" / "Info.plist"
plist_text = ext_plist.read_text().replace('<string>1.3.20</string>', '<string>1.3.21</string>').replace('<string>30</string>', '<string>31</string>')
ext_plist.write_text(plist_text)

settings = SOURCES / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.3.20 • iOS 16.0+", "Version 1.3.21 • iOS 16.0+"))
for swift in SOURCES.glob("*.swift"):
    swift.write_text(swift.read_text().replace("NextReminder-iOS/1.3.20", "NextReminder-iOS/1.3.21"))

print("Next Reminder v1.3.21 email schedule visibility and database-change sync patch applied successfully.")
