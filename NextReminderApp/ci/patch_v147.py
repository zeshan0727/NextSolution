#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
project = ROOT / "project.yml"
components = ROOT / "NextReminder" / "Sources" / "Components.swift"
settings = ROOT / "NextReminder" / "Sources" / "Settings.swift"

project_text = project.read_text()
if "CADisableMinimumFrameDurationOnPhone: true" not in project_text:
    anchor = "        UIRequiresFullScreen: true\n"
    if anchor not in project_text:
        raise SystemExit("project.yml anchor not found")
    project_text = project_text.replace(anchor, anchor + "        CADisableMinimumFrameDurationOnPhone: true\n", 1)

project_text = project_text.replace('CFBundleShortVersionString: "1.3.16"', 'CFBundleShortVersionString: "1.3.17"')
project_text = project_text.replace('CFBundleVersion: "26"', 'CFBundleVersion: "27"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.16"', 'MARKETING_VERSION: "1.3.17"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "26"', 'CURRENT_PROJECT_VERSION: "27"')
project.write_text(project_text)

components_text = components.read_text()
old_shadow = '        .shadow(color: accentColor.opacity(0.08), radius: 8, y: 3)'
new_shadow = '        .shadow(color: Color.black.opacity(0.035), radius: 3, x: 0, y: 1)'
if old_shadow not in components_text:
    raise SystemExit("shadow anchor not found")
components_text = components_text.replace(old_shadow, new_shadow, 1)

old_press = '''            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)'''
new_press = '''            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.86), value: configuration.isPressed)'''
if old_press not in components_text:
    raise SystemExit("button anchor not found")
components_text = components_text.replace(old_press, new_press, 1)
components.write_text(components_text)

settings.write_text(settings.read_text().replace("Version 1.3.16 • iOS 16.0+", "Version 1.3.17 • iOS 16.0+"))
for swift in (ROOT / "NextReminder" / "Sources").glob("*.swift"):
    swift.write_text(swift.read_text().replace("NextReminder-iOS/1.3.16", "NextReminder-iOS/1.3.17"))

print("Next Reminder v1.3.17 performance patch applied successfully.")
