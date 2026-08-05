#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
project = ROOT / "project.yml"
plist = ROOT / "NextReminder" / "Resources" / "Info.plist"
components = ROOT / "NextReminder" / "Sources" / "Components.swift"
settings = ROOT / "NextReminder" / "Sources" / "Settings.swift"

project_text = project.read_text()
if "CADisableMinimumFrameDurationOnPhone: true" not in project_text:
    anchor = "        UIRequiresFullScreen: true\n"
    if anchor not in project_text:
        raise SystemExit("project.yml Info.plist properties anchor not found")
    project_text = project_text.replace(
        anchor,
        anchor + "        CADisableMinimumFrameDurationOnPhone: true\n",
        1,
    )

project_text = project_text.replace('CFBundleShortVersionString: "1.3.16"', 'CFBundleShortVersionString: "1.3.17"')
project_text = project_text.replace('CFBundleVersion: "26"', 'CFBundleVersion: "27"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.16"', 'MARKETING_VERSION: "1.3.17"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "26"', 'CURRENT_PROJECT_VERSION: "27"')
project.write_text(project_text)

plist_text = plist.read_text()
if "<key>CADisableMinimumFrameDurationOnPhone</key>" not in plist_text:
    anchor = "    <key>CFBundleDevelopmentRegion</key>\n"
    if anchor not in plist_text:
        raise SystemExit("Info.plist dictionary anchor not found")
    plist_text = plist_text.replace(
        anchor,
        "    <key>CADisableMinimumFrameDurationOnPhone</key>\n"
        "    <true/>\n" + anchor,
        1,
    )
plist.write_text(plist_text)

components_text = components.read_text()
components_text = components_text.replace(
    '''        .shadow(color: accentColor.opacity(0.08), radius: 8, y: 3)''',
    '''        // Keep the same lifted-card appearance with substantially less GPU overdraw while scrolling.
        .shadow(color: Color.black.opacity(0.035), radius: 3, x: 0, y: 1)''',
    1,
)
components_text = components_text.replace(
    '''            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)''',
    '''            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.86), value: configuration.isPressed)''',
    1,
)
components.write_text(components_text)

settings_text = settings.read_text().replace("Version 1.3.16 • iOS 16.0+", "Version 1.3.17 • iOS 16.0+")
settings.write_text(settings_text)
for swift in (ROOT / "NextReminder" / "Sources").glob("*.swift"):
    swift.write_text(swift.read_text().replace("NextReminder-iOS/1.3.16", "NextReminder-iOS/1.3.17"))

print("Next Reminder v1.3.17 ProMotion and animation performance patch applied successfully.")
