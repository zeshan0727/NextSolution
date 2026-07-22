#!/usr/bin/env python3
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:200]!r}")
    path.write_text(text.replace(old, new, 1))


# Use an AI hub so DeepSeek reminder assistance and the OpenAI X generator coexist.
root = SOURCES / "RootReminders.swift"
replace_once(
    root,
    '''            NavigationStack {
                DeepSeekAIView()
            }
            .tabItem { Label("AI", systemImage: "sparkles") }
            .tag(AppTab.ai)''',
    '''            NavigationStack {
                AIHubView()
            }
            .tabItem { Label("AI", systemImage: "sparkles") }
            .tag(AppTab.ai)'''
)


# Add OpenAI X generator settings beside the existing DeepSeek settings.
settings = SOURCES / "Settings.swift"
replace_once(
    settings,
    '''            .buttonStyle(.plain)

            Text("The AI tab can analyze active reminders only when reminder context is enabled. It never completes or changes reminders automatically.")''',
    '''            .buttonStyle(.plain)

            NavigationLink {
                OpenAIXGeneratorSettingsView()
            } label: {
                settingsRow(
                    icon: "bolt.horizontal.circle.fill",
                    title: "X Post Generator Settings",
                    subtitle: "OpenAI API key, latest-news writing model, and image quality"
                )
            }
            .buttonStyle(.plain)

            Text("DeepSeek can analyze active reminders when context is enabled. The X generator uses OpenAI web search and image generation, but never posts automatically.")'''
)


# Backup security wording includes the OpenAI key, which remains in Keychain.
backup = SOURCES / "BackupRestore.swift"
backup_text = backup.read_text()
backup_text = backup_text.replace(
    "Gmail, scheduler, and DeepSeek credentials are never included; reconnect them after restoring on another device",
    "Gmail, scheduler, DeepSeek, and OpenAI credentials are never included; reconnect them after restoring on another device"
)
backup_text = backup_text.replace(
    "Backup restored successfully. Reconnect Gmail and DeepSeek if needed.",
    "Backup restored successfully. Reconnect Gmail, DeepSeek, and OpenAI if needed."
)
backup.write_text(backup_text)


# Version metadata and Photos add-only permission.
project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.3.0"', 'CFBundleShortVersionString: "1.3.1"')
project_text = project_text.replace('CFBundleVersion: "10"', 'CFBundleVersion: "11"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.0"', 'MARKETING_VERSION: "1.3.1"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "10"', 'CURRENT_PROJECT_VERSION: "11"')
if "NSPhotoLibraryAddUsageDescription:" not in project_text:
    marker = "        NSCameraUsageDescription: Capture and scan documents to attach to Gmail messages.\n"
    addition = marker + "        NSPhotoLibraryAddUsageDescription: Save generated X post visuals to your Photos library.\n"
    if marker in project_text:
        project_text = project_text.replace(marker, addition, 1)
    else:
        project_text = project_text.replace(
            "        UIRequiresFullScreen: true\n",
            "        UIRequiresFullScreen: true\n        NSPhotoLibraryAddUsageDescription: Save generated X post visuals to your Photos library.\n",
            1
        )
project.write_text(project_text)

info = ROOT / "NextReminder" / "Resources" / "Info.plist"
with info.open("rb") as handle:
    plist = plistlib.load(handle)
plist["NSPhotoLibraryAddUsageDescription"] = "Save generated X post visuals to your Photos library."
with info.open("wb") as handle:
    plistlib.dump(plist, handle, sort_keys=False)

settings.write_text(settings.read_text().replace("Version 1.3.0 • iOS 16.0+", "Version 1.3.1 • iOS 16.0+"))

for path in SOURCES.glob("*.swift"):
    path.write_text(path.read_text().replace("NextReminder-iOS/1.3.0", "NextReminder-iOS/1.3.1"))

print("Next Reminder v1.3.1 patches applied successfully.")
