#!/usr/bin/env python3
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parent

for rel in ['control', 'ConsoleBridge.m', 'Preferences/Resources/Info.plist', 'Preferences/NQRDiagnosticsController.m', 'layout/DEBIAN/postinst']:
    path = root / rel
    text = path.read_text().replace('1.0.3', '1.0.4').replace('1.0.0', '1.0.4')
    if rel == 'control':
        lines = []
        for line in text.splitlines():
            if line.startswith('Description:'):
                line = 'Description: RootHide quick reminder panel with Lock Screen clock access and direct background scheduling without opening Next Reminder.'
            lines.append(line)
        text = '\n'.join(lines) + '\n'
    path.write_text(text)

plist_path = root / 'Preferences/Resources/Root.plist'
with plist_path.open('rb') as handle:
    plist = plistlib.load(handle)
items = plist['items']
if not any(item.get('key') == 'allowLockScreen' for item in items):
    gesture_index = next(i for i, item in enumerate(items) if item.get('key') == 'gesture')
    items.insert(gesture_index + 1, {
        'cell': 'PSSwitchCell',
        'default': False,
        'get': 'readPreferenceValue:',
        'key': 'allowLockScreen',
        'label': 'Allow on Lock Screen',
        'set': 'setPreferenceValue:specifier:',
    })
items[0]['footerText'] = 'Select one gesture. Enable Allow on Lock Screen to double-tap the Lock Screen clock. Schedule saves directly in the background without opening the app.'
with plist_path.open('wb') as handle:
    plistlib.dump(plist, handle, fmt=plistlib.FMT_XML, sort_keys=False)

print('Prepared Next Quick Reminder 1.0.4 background-save and Lock Screen package.')
