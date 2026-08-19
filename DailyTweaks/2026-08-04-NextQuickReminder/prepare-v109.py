#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parent

for rel in ['control', 'ConsoleBridge.m', 'Preferences/Resources/Info.plist', 'Preferences/NQRDiagnosticsController.m', 'layout/DEBIAN/postinst']:
    path = root / rel
    text = path.read_text().replace('1.0.8', '1.0.9')
    if rel == 'control':
        lines = []
        for line in text.splitlines():
            if line.startswith('Description:'):
                line = 'Description: RootHide quick reminder with multi-trigger access, reliable keyboard input, background saving, and iOS 16 Dynamic Island presentation attached to SpringBoard System Aperture. Version 1.0.9 adds persistent Dismiss so the same reminder occurrence does not return after lock/unlock.'
            lines.append(line)
        text = '\n'.join(lines) + '\n'
    path.write_text(text)

makefile = root / 'Makefile'
text = makefile.read_text()
old = 'NextQuickReminder_FILES = Tweak.xm ConsoleBridge.m BackgroundLockscreen.xm MultiTriggersSettings.xm SystemApertureReminder.xm'
new = 'NextQuickReminder_FILES = Tweak.xm ConsoleBridge.m BackgroundLockscreen.xm MultiTriggersSettings.xm SystemApertureReminderV109.xm'
if old not in text:
    if new not in text:
        raise SystemExit('Expected v1.0.8 Makefile source line not found')
else:
    text = text.replace(old, new, 1)
makefile.write_text(text)

tweak = root / 'Tweak.xm'
text = tweak.read_text()
text = text.replace(
    'Next Quick Reminder 1.0.8 loaded with keyboard + Apple System Aperture reminder integration',
    'Next Quick Reminder 1.0.9 loaded with island-only System Aperture + persistent dismiss'
)
tweak.write_text(text)

print('Prepared Next Quick Reminder 1.0.9 island-only presentation and persistent dismiss.')
