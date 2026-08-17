#!/usr/bin/env python3
from pathlib import Path
import plistlib

ROOT=Path(__file__).resolve().parent

# Public 1.1.2 keeps automatic model/iOS metadata in normal activation requests,
# but removes the temporary manual "Send Device Details to NS Admin" row.
root_path=ROOT/'prefs'/'Resources'/'Root.plist'
root=plistlib.loads(root_path.read_bytes())
items=root.get('items',[])
items=[x for x in items if x.get('action')!='shareDeviceDetails' and x.get('label')!='Send Device Details to NS Admin']
for item in items:
    if item.get('cell')=='PSGroupCell' and item.get('label')=='ACTIVATION':
        item['footerText']='NextLock requires a $1 USD lifetime license. Activation and revocation use the live Next Solution registry and refresh automatically about every 10 seconds while the device is online.'
root['items']=items
root_path.write_bytes(plistlib.dumps(root,fmt=plistlib.FMT_XML,sort_keys=False))

control_path=ROOT/'control'
control=control_path.read_text().replace('Version: 1.1.1','Version: 1.1.2',1)
lines=control.splitlines()
for i,line in enumerate(lines):
    if line.startswith('Description:'):
        lines[i]='Description: Next Solution lock-screen customization suite. Version 1.1.2 adds fast live license refresh, a polished preference icon, and device model/iOS metadata in activation requests.'
        break
control_path.write_text('\n'.join(lines)+'\n')

info_path=ROOT/'prefs'/'Resources'/'Info.plist'
info=plistlib.loads(info_path.read_bytes())
info['CFBundleShortVersionString']='1.1.2'
info['CFBundleVersion']='112'
info_path.write_bytes(plistlib.dumps(info,fmt=plistlib.FMT_XML,sort_keys=False))

about_path=ROOT/'prefs'/'Resources'/'About.plist'
about=plistlib.loads(about_path.read_bytes())
for item in about.get('items',[]):
    if isinstance(item.get('footerText'),str):
        item['footerText']=item['footerText'].replace('Version 1.1.1','Version 1.1.2')
about_path.write_bytes(plistlib.dumps(about,fmt=plistlib.FMT_XML,sort_keys=False))

print('Patched NextLock 1.1.2 public release without the NS Admin device-details row')
