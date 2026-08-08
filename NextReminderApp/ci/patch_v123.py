#!/usr/bin/env python3
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:140]!r}")
    path.write_text(text.replace(old, new, 1))


def regex_once(path: Path, pattern: str, replacement: str) -> None:
    text = path.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"Expected one regex match in {path}, found {count}: {pattern}")
    path.write_text(updated)


# MARK: Replace center Add tab with a visible File Sharing tab.
root = SOURCES / "RootReminders.swift"
replace_once(root, "    case add", "    case files")
replace_once(
    root,
    '''    @State private var selectedTab: AppTab = .reminders
    @State private var lastRegularTab: AppTab = .reminders
    @State private var showAddMenu = false
    @State private var addFlow: AddFlow?
    @State private var openedAutomation: IdentifiedAutomationID?''',
    '''    @State private var selectedTab: AppTab = .reminders
    @State private var openedAutomation: IdentifiedAutomationID?'''
)
replace_once(
    root,
    '''            Color.clear
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(AppTab.add)''',
    '''            NavigationStack {
                FileSharingView()
            }
            .tabItem { Label("Files", systemImage: "paperclip.circle.fill") }
            .tag(AppTab.files)'''
)
regex_once(
    root,
    r'''        \.onChange\(of: selectedTab\) \{ newValue in.*?        \}
        \.onChange\(of: automationStore\.requestedAutomationID\)''',
    '''        .onChange(of: automationStore.requestedAutomationID)'''
)
regex_once(
    root,
    r'''        \.confirmationDialog\(.*?        \.sheet\(item: \$openedAutomation\)''',
    '''        .sheet(item: $openedAutomation)'''
)

# Add a prominent New Reminder button now that the center Add tab is used by Files.
replace_once(
    root,
    "    @State private var advancedCategoryIDs: Set<UUID> = []",
    "    @State private var advancedCategoryIDs: Set<UUID> = []\n    @State private var isAddingReminder = false"
)
replace_once(
    root,
    '''                Button {
                    isShowingFilters = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Advanced filters")''',
    '''                Button {
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
                .accessibilityLabel("New reminder")'''
)
replace_once(
    root,
    '''        .sheet(isPresented: $isShowingFilters) {
            FilterView(
                selectedPriorities: $selectedPriorities,
                selectedCategoryIDs: $advancedCategoryIDs
            )
            .environmentObject(store)
        }''',
    '''        .sheet(isPresented: $isShowingFilters) {
            FilterView(
                selectedPriorities: $selectedPriorities,
                selectedCategoryIDs: $advancedCategoryIDs
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $isAddingReminder) {
            NavigationStack {
                ReminderEditorView(reminder: nil)
            }
            .environmentObject(store)
        }'''
)

# MARK: Quick extend options from the current/original reminder time.
actions = SOURCES / "CompletedFilterActions.swift"
regex_once(
    actions,
    r'''struct ExtendReminderView: View \{.*?\n\}\s*\Z''',
    '''struct ExtendReminderView: View {
    @Environment(\\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReminderStore
    let reminder: ReminderItem

    @State private var newDate: Date
    @State private var comment = ""

    init(reminder: ReminderItem) {
        self.reminder = reminder
        let base = max(reminder.dueDate, Date())
        _newDate = State(initialValue: base.addingTimeInterval(3600))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Extend from the reminder time using a quick option or choose a custom date and time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Quick Extension")
                        HStack(spacing: 9) {
                            quickButton(title: "+1 Hour", seconds: 3_600)
                            quickButton(title: "+2 Hours", seconds: 7_200)
                            quickButton(title: "+1 Day", seconds: 86_400)
                        }
                        Text("Quick options are added to the existing reminder time. If the reminder is already overdue, they are added from the current time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Custom Date & Time")
                        DatePicker(
                            "New reminder time",
                            selection: $newDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .padding(14)
                        .nextCard()
                    }

                    TextEditor(text: $comment)
                        .frame(minHeight: 130)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .nextCard()
                        .overlay(alignment: .topLeading) {
                            if comment.isEmpty {
                                Text("Extension comment")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }

                    Button("Extend Reminder") {
                        store.extend(reminder, to: newDate, comment: comment)
                        dismiss()
                    }
                    .buttonStyle(OrangeActionButtonStyle())
                    .disabled(newDate <= Date())
                    .opacity(newDate > Date() ? 1 : 0.5)
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(Color.nextBackground.ignoresSafeArea())
            .navigationTitle("Extend Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func quickButton(title: String, seconds: TimeInterval) -> some View {
        Button {
            let base = max(reminder.dueDate, Date())
            newDate = base.addingTimeInterval(seconds)
        } label: {
            Text(title)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.nextOrange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
'''
)

# MARK: Version, camera permission, and network client metadata.
project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.2.2"', 'CFBundleShortVersionString: "1.2.3"')
project_text = project_text.replace('CFBundleVersion: "6"', 'CFBundleVersion: "7"')
project_text = project_text.replace('MARKETING_VERSION: "1.2.2"', 'MARKETING_VERSION: "1.2.3"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "6"', 'CURRENT_PROJECT_VERSION: "7"')
if "NSCameraUsageDescription:" not in project_text:
    project_text = project_text.replace(
        "        UIRequiresFullScreen: true\n",
        "        UIRequiresFullScreen: true\n        NSCameraUsageDescription: Capture and scan documents to attach to Gmail messages.\n"
    )
project.write_text(project_text)

settings = SOURCES / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.2.2 • iOS 16.0+", "Version 1.2.3 • iOS 16.0+"))

for name in ["EmailAutomationCore.swift", "GmailConnection.swift"]:
    path = SOURCES / name
    text = path.read_text().replace("NextReminder-iOS/1.2.2", "NextReminder-iOS/1.2.3")
    text = text.replace("NextReminder-iOS/1.2.1", "NextReminder-iOS/1.2.3")
    path.write_text(text)

info = ROOT / "NextReminder" / "Resources" / "Info.plist"
with info.open("rb") as handle:
    plist = plistlib.load(handle)
plist["NSCameraUsageDescription"] = "Capture and scan documents to attach to Gmail messages."
with info.open("wb") as handle:
    plistlib.dump(plist, handle, sort_keys=False)

print("Next Reminder v1.2.3 patches applied successfully.")
