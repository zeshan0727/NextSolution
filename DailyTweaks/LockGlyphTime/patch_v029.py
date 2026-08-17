#!/usr/bin/env python3
from pathlib import Path
import plistlib

ROOT=Path(__file__).resolve().parent
runtime_path=ROOT/'RuntimeV023.xm'
prefs_path=ROOT/'prefs'/'LGTListControllerV023.m'
runtime=runtime_path.read_text()
prefs=prefs_path.read_text()

# Read the registry directly from the main branch instead of waiting for GitHub
# Pages deployment. A cache-busting timestamp is already appended by 1.1.0.
old_url='https://nextsolution.cc/licenses/nextlock.json'
new_url='https://raw.githubusercontent.com/zeshan0727/NextSolution/main/licenses/nextlock.json'
if old_url not in runtime or old_url not in prefs:
    raise SystemExit('license registry URL anchor not found')
runtime=runtime.replace(old_url,new_url)
prefs=prefs.replace(old_url,new_url)

# Runtime auto-refresh: every 10 seconds rather than the previous hourly cycle.
old_timer='dispatch_source_set_timer(gLGTLicenseTimer,dispatch_time(DISPATCH_TIME_NOW,60*NSEC_PER_SEC),60*60*NSEC_PER_SEC,30*NSEC_PER_SEC);'
new_timer='dispatch_source_set_timer(gLGTLicenseTimer,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),10*NSEC_PER_SEC,1*NSEC_PER_SEC);'
if old_timer not in runtime:
    raise SystemExit('license timer anchor not found')
runtime=runtime.replace(old_timer,new_timer,1)
runtime_path.write_text(runtime)

# Include hardware model + iOS version in checkout/request handoff so NS Admin
# can display useful device details for activated licenses.
if '#import <sys/utsname.h>' not in prefs:
    prefs=prefs.replace('#import <CommonCrypto/CommonDigest.h>\n','#import <CommonCrypto/CommonDigest.h>\n#import <sys/utsname.h>\n',1)

helper_anchor='static NSString * const LGTLicenseSalt = @"nextsolution-license-v1";'
helper='''

static NSString *LGTPrefsHardwareModel(void) {
    struct utsname info;
    if(uname(&info)!=0) return @"Unknown iPhone";
    NSString *model=[NSString stringWithCString:info.machine encoding:NSUTF8StringEncoding];
    return model.length?model:@"Unknown iPhone";
}
'''
if helper_anchor not in prefs:
    raise SystemExit('license helper anchor not found')
prefs=prefs.replace(helper_anchor,helper_anchor+helper,1)

old_buy='- (void)buyLicense { NSString *device=LGTPrefsLicenseDeviceID(); NSString *escaped=[device stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]; NSURL *u=[NSURL URLWithString:[NSString stringWithFormat:@"https://nextsolution.cc/license/nextlock/?device=%@",escaped?:@""]]; if(u)[UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil]; }'
new_buy='''- (void)buyLicense {
    NSString *device=LGTPrefsLicenseDeviceID();
    NSString *model=LGTPrefsHardwareModel();
    NSString *ios=UIDevice.currentDevice.systemVersion?:@"";
    NSCharacterSet *allowed=NSCharacterSet.URLQueryAllowedCharacterSet;
    NSString *d=[device stringByAddingPercentEncodingWithAllowedCharacters:allowed]?:@"";
    NSString *m=[model stringByAddingPercentEncodingWithAllowedCharacters:allowed]?:@"";
    NSString *v=[ios stringByAddingPercentEncodingWithAllowedCharacters:allowed]?:@"";
    NSURL *u=[NSURL URLWithString:[NSString stringWithFormat:@"https://nextsolution.cc/license/nextlock/?device=%@&model=%@&ios=%@",d,m,v]];
    if(u)[UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
}'''
if old_buy not in prefs:
    raise SystemExit('buyLicense anchor not found')
prefs=prefs.replace(old_buy,new_buy,1)
prefs_path.write_text(prefs)

# Update activation footer to reflect fast refresh behavior.
root_path=ROOT/'prefs'/'Resources'/'Root.plist'
root=plistlib.loads(root_path.read_bytes())
for item in root.get('items',[]):
    if item.get('cell')=='PSGroupCell' and item.get('label')=='ACTIVATION':
        item['footerText']='NextLock requires a $1 USD lifetime license for this generated Next Solution Device ID. Activation and revocation are checked directly against the live registry and normally apply within about 10 seconds while the device is online.'
root_path.write_bytes(plistlib.dumps(root,fmt=plistlib.FMT_XML,sort_keys=False))

# Version metadata.
control_path=ROOT/'control'
control=control_path.read_text().replace('Version: 1.1.0','Version: 1.1.1',1)
lines=control.splitlines()
for i,line in enumerate(lines):
    if line.startswith('Description:'):
        lines[i]='Description: Next Solution lock-screen customization suite. Version 1.1.1 adds near-instant activation/revocation checks, device model + iOS activation metadata, and a polished native-style NextLock preference icon.'
        break
control_path.write_text('\n'.join(lines)+'\n')

info_path=ROOT/'prefs'/'Resources'/'Info.plist'
info=plistlib.loads(info_path.read_bytes())
info['CFBundleShortVersionString']='1.1.1'
info['CFBundleVersion']='111'
info_path.write_bytes(plistlib.dumps(info,fmt=plistlib.FMT_XML,sort_keys=False))

about_path=ROOT/'prefs'/'Resources'/'About.plist'
about=plistlib.loads(about_path.read_bytes())
for item in about.get('items',[]):
    if isinstance(item.get('footerText'),str):
        item['footerText']=item['footerText'].replace('Version 1.1.0','Version 1.1.1')
about_path.write_bytes(plistlib.dumps(about,fmt=plistlib.FMT_XML,sort_keys=False))

print('Patched NextLock 1.1.1 instant licensing + device metadata')
