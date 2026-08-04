#!/usr/bin/env python3
from pathlib import Path
import base64
import gzip

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"
SWIFT_B64 = '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'
(SOURCES / "QuickTweakConsole.swift").write_bytes(gzip.decompress(base64.b64decode(SWIFT_B64)))

settings = SOURCES / "Settings.swift"
text = settings.read_text()
if "quickTweakSection" not in text:
    body_anchor = "                notificationSection\n"
    if body_anchor not in text:
        raise SystemExit("Settings body anchor not found")
    text = text.replace(body_anchor, body_anchor + "                quickTweakSection\n", 1)

    section_anchor = "    private var managementSection: some View {\n"
    if section_anchor not in text:
        raise SystemExit("Settings section anchor not found")
    section = '    private var quickTweakSection: some View {\n        VStack(alignment: .leading, spacing: 12) {\n            SectionHeader(title: "RootHide Quick Reminder")\n            NavigationLink {\n                QuickTweakConsoleView()\n            } label: {\n                settingsRow(\n                    icon: "terminal.fill",\n                    title: "Tweak Console",\n                    subtitle: "Heartbeat, gesture selection, Test Panel and live SpringBoard logs"\n                )\n            }\n            .buttonStyle(.plain)\n\n            Text("This in-app console works even when the separate PreferenceLoader page is missing from iOS Settings.")\n                .font(.caption)\n                .foregroundStyle(.secondary)\n        }\n    }\n\n'
    text = text.replace(section_anchor, section + section_anchor, 1)
settings.write_text(text)

project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.3.13"', 'CFBundleShortVersionString: "1.3.14"')
project_text = project_text.replace('CFBundleVersion: "23"', 'CFBundleVersion: "24"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.13"', 'MARKETING_VERSION: "1.3.14"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "23"', 'CURRENT_PROJECT_VERSION: "24"')
project.write_text(project_text)

settings.write_text(settings.read_text().replace("Version 1.3.13 • iOS 16.0+", "Version 1.3.14 • iOS 16.0+"))
for source in SOURCES.glob("*.swift"):
    source.write_text(source.read_text().replace("NextReminder-iOS/1.3.13", "NextReminder-iOS/1.3.14"))

print("Next Reminder v1.3.14 in-app RootHide tweak console applied successfully.")
