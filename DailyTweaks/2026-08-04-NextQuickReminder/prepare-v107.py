#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parent

for rel in ['control', 'ConsoleBridge.m', 'Preferences/Resources/Info.plist', 'Preferences/NQRDiagnosticsController.m', 'layout/DEBIAN/postinst']:
    path = root / rel
    text = path.read_text().replace('1.0.6', '1.0.7')
    if rel == 'control':
        lines = []
        for line in text.splitlines():
            if line.startswith('Description:'):
                line = 'Description: RootHide quick reminder with reliable multi-trigger access, keyboard input, background saving, and an iOS 16.0 Lock Screen due-reminder live-card fallback with Completed and Extend controls.'
            lines.append(line)
        text = '\n'.join(lines) + '\n'
    path.write_text(text)

makefile = root / 'Makefile'
text = makefile.read_text()
old = 'NextQuickReminder_FILES = Tweak.xm ConsoleBridge.m BackgroundLockscreen.xm MultiTriggersSettings.xm'
new = 'NextQuickReminder_FILES = Tweak.xm ConsoleBridge.m BackgroundLockscreen.xm MultiTriggersSettings.xm DueReminderLiveCard.xm'
if old not in text:
    raise SystemExit('Expected v1.0.6 Makefile source line not found')
makefile.write_text(text.replace(old, new, 1))

# Version string emitted by the v1.0.6 keyboard patch.
tweak = root / 'Tweak.xm'
tweak.write_text(tweak.read_text().replace(
    'Next Quick Reminder 1.0.6 loaded with multi-trigger keyboard fix',
    'Next Quick Reminder 1.0.7 loaded with keyboard + iOS16 due live-card fix'
))

print('Prepared Next Quick Reminder 1.0.7 iOS16 due live-card fallback.')
