#!/usr/bin/env python3
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parent
root_path = ROOT / 'prefs' / 'Resources' / 'Root.plist'
root = plistlib.loads(root_path.read_bytes())
items = root.get('items', [])

# Remove the activation block from wherever an earlier patch placed it.
activation_keys = {'licenseStatusDisplay', 'licenseDeviceID'}
activation_actions = {'copyLicenseDeviceID', 'buyLicense', 'checkActivation', 'shareDeviceDetails'}
filtered = []
for item in items:
    if item.get('cell') == 'PSGroupCell' and item.get('label') == 'ACTIVATION':
        continue
    if item.get('key') in activation_keys:
        continue
    if item.get('action') in activation_actions:
        continue
    filtered.append(item)

# Public 1.1.3 layout: keep all normal tweak controls first and activation last.
activation = [
    {
        'cell': 'PSGroupCell',
        'label': 'ACTIVATION',
        'footerText': 'NextLock requires a $1 USD lifetime license for this generated Next Solution Device ID. Activation and revocation use the live Next Solution license registry.'
    },
    {
        'cell': 'PSTitleValueCell',
        'label': 'Status',
        'defaults': 'com.nextsolution.lockglyphtime',
        'key': 'licenseStatusDisplay',
        'default': 'Unactivated'
    },
    {
        'cell': 'PSTitleValueCell',
        'label': 'Device ID',
        'defaults': 'com.nextsolution.lockglyphtime',
        'key': 'licenseDeviceID',
        'default': 'Generating…'
    },
    {'cell': 'PSButtonCell', 'label': 'Copy Device ID', 'action': 'copyLicenseDeviceID'},
    {'cell': 'PSButtonCell', 'label': 'Buy / Activate — $1.00', 'action': 'buyLicense'},
    {'cell': 'PSButtonCell', 'label': 'Check Activation', 'action': 'checkActivation'},
]
root['items'] = filtered + activation
root_path.write_bytes(plistlib.dumps(root, fmt=plistlib.FMT_XML, sort_keys=False))

# Version metadata.
control_path = ROOT / 'control'
control = control_path.read_text().replace('Version: 1.1.2', 'Version: 1.1.3', 1)
lines = control.splitlines()
for i, line in enumerate(lines):
    if line.startswith('Description:'):
        lines[i] = 'Description: Next Solution lock-screen customization suite. Version 1.1.3 moves the paid Activation section to the bottom of Settings while keeping fast live license checks, polished preference icon, and device model/iOS metadata in activation requests.'
        break
control_path.write_text('\n'.join(lines) + '\n')

info_path = ROOT / 'prefs' / 'Resources' / 'Info.plist'
info = plistlib.loads(info_path.read_bytes())
info['CFBundleShortVersionString'] = '1.1.3'
info['CFBundleVersion'] = '113'
info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=False))

about_path = ROOT / 'prefs' / 'Resources' / 'About.plist'
about = plistlib.loads(about_path.read_bytes())
for item in about.get('items', []):
    footer = item.get('footerText')
    if isinstance(footer, str):
        item['footerText'] = footer.replace('Version 1.1.2', 'Version 1.1.3')
about_path.write_bytes(plistlib.dumps(about, fmt=plistlib.FMT_XML, sort_keys=False))

print('Patched NextLock 1.1.3: activation section moved to bottom')
