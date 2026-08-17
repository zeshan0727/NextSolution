#!/usr/bin/env python3
from pathlib import Path
import plistlib

ROOT=Path(__file__).resolve().parent
prefs_path=ROOT/'prefs'/'LGTListControllerV023.m'
prefs=prefs_path.read_text()

anchor='''- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; if([[self lgt_plistName] isEqualToString:@"Root"]){ LGTPrefsLicenseDeviceID(); [self lgtRefreshLicenseShowingResult:NO]; } }
'''
method='''- (void)shareDeviceDetails {
    NSString *device=LGTPrefsLicenseDeviceID();
    NSString *model=LGTPrefsHardwareModel();
    NSString *ios=UIDevice.currentDevice.systemVersion?:@"";
    NSCharacterSet *allowed=NSCharacterSet.URLQueryAllowedCharacterSet;
    NSString *d=[device stringByAddingPercentEncodingWithAllowedCharacters:allowed]?:@"";
    NSString *m=[model stringByAddingPercentEncodingWithAllowedCharacters:allowed]?:@"";
    NSString *v=[ios stringByAddingPercentEncodingWithAllowedCharacters:allowed]?:@"";
    NSString *url=[NSString stringWithFormat:@"https://nextsolution.cc/license/request/?product=NextLock&device=%@&package=com.nextsolution.lockglyphtime&model=%@&ios=%@",d,m,v];
    NSURL *u=[NSURL URLWithString:url];
    if(u)[UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; if([[self lgt_plistName] isEqualToString:@"Root"]){ LGTPrefsLicenseDeviceID(); [self lgtRefreshLicenseShowingResult:NO]; } }
'''
if anchor not in prefs:
    raise SystemExit('viewWillAppear anchor not found')
prefs=prefs.replace(anchor,method,1)
prefs_path.write_text(prefs)

root_path=ROOT/'prefs'/'Resources'/'Root.plist'
root=plistlib.loads(root_path.read_bytes())
items=root.get('items',[])
items=[x for x in items if x.get('action')!='shareDeviceDetails']
insert_at=0
for i,item in enumerate(items):
    if item.get('action')=='checkActivation':
        insert_at=i+1
        break
items.insert(insert_at,{'cell':'PSButtonCell','label':'Send Device Details to NS Admin','action':'shareDeviceDetails'})
for item in items:
    if item.get('cell')=='PSGroupCell' and item.get('label')=='ACTIVATION':
        item['footerText']='NextLock requires a $1 USD lifetime license. Activation/revocation checks the live registry about every 10 seconds. Already-paid devices can use Send Device Details to NS Admin to sync hardware model and iOS information without paying again.'
root['items']=items
root_path.write_bytes(plistlib.dumps(root,fmt=plistlib.FMT_XML,sort_keys=False))

control_path=ROOT/'control'
control=control_path.read_text().replace('Version: 1.1.1','Version: 1.1.2',1)
lines=control.splitlines()
for i,line in enumerate(lines):
    if line.startswith('Description:'):
        lines[i]='Description: Next Solution lock-screen customization suite. Version 1.1.2 adds fast license refresh, polished preference icon, device model/iOS metadata and a no-payment device-detail sync for existing licenses.'
        break
control_path.write_text('\n'.join(lines)+'\n')

info_path=ROOT/'prefs'/'Resources'/'Info.plist'
info=plistlib.loads(info_path.read_bytes())
info['CFBundleShortVersionString']='1.1.2'; info['CFBundleVersion']='112'
info_path.write_bytes(plistlib.dumps(info,fmt=plistlib.FMT_XML,sort_keys=False))

about_path=ROOT/'prefs'/'Resources'/'About.plist'
about=plistlib.loads(about_path.read_bytes())
for item in about.get('items',[]):
    if isinstance(item.get('footerText'),str): item['footerText']=item['footerText'].replace('Version 1.1.1','Version 1.1.2')
about_path.write_bytes(plistlib.dumps(about,fmt=plistlib.FMT_XML,sort_keys=False))
print('Patched NextLock 1.1.2 existing-device detail sync')
