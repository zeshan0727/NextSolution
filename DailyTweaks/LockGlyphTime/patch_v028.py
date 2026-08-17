#!/usr/bin/env python3
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parent
runtime_path = ROOT / "RuntimeV023.xm"
prefs_path = ROOT / "prefs" / "LGTListControllerV023.m"
runtime = runtime_path.read_text()
prefs = prefs_path.read_text()

# ---------- Runtime license gate ----------
if '#import <CommonCrypto/CommonDigest.h>' not in runtime:
    runtime = runtime.replace('#import <Foundation/Foundation.h>\n', '#import <Foundation/Foundation.h>\n#import <CommonCrypto/CommonDigest.h>\n', 1)

runtime_globals_anchor = 'static BOOL gEnabled = YES;'
if runtime_globals_anchor not in runtime:
    raise SystemExit('runtime enabled anchor not found')
runtime = runtime.replace(runtime_globals_anchor, runtime_globals_anchor + '''
static BOOL gLicenseActive = NO;
static dispatch_source_t gLGTLicenseTimer = nil;
static NSString * const LGTLicenseRegistryURL = @"https://nextsolution.cc/licenses/nextlock.json";
static NSString * const LGTLicenseSalt = @"nextsolution-license-v1";
''', 1)

load_anchor = 'static void LGTLoadPrefs(void) {'
if load_anchor not in runtime:
    raise SystemExit('runtime load prefs anchor not found')
license_runtime = r'''
static NSString *LGTLicenseEnsureDeviceID(void) {
    NSUserDefaults *prefs=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain];
    NSString *existing=[[prefs stringForKey:@"licenseDeviceID"] uppercaseString];
    NSRegularExpression *rx=[NSRegularExpression regularExpressionWithPattern:@"^NS-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}$" options:0 error:nil];
    if(existing.length && [rx firstMatchInString:existing options:0 range:NSMakeRange(0,existing.length)]) return existing;
    NSString *raw=[[[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""] uppercaseString];
    if(raw.length<16) return @"NS-0000-0000-0000-0000";
    NSString *device=[NSString stringWithFormat:@"NS-%@-%@-%@-%@",[raw substringWithRange:NSMakeRange(0,4)],[raw substringWithRange:NSMakeRange(4,4)],[raw substringWithRange:NSMakeRange(8,4)],[raw substringWithRange:NSMakeRange(12,4)]];
    [prefs setObject:device forKey:@"licenseDeviceID"];
    if(![prefs stringForKey:@"licenseStatusDisplay"]) [prefs setObject:@"Unactivated" forKey:@"licenseStatusDisplay"];
    [prefs synchronize];
    return device;
}

static NSString *LGTLicenseTokenForDevice(NSString *device) {
    NSString *payload=[NSString stringWithFormat:@"%@|%@|%@",device?:@"",LGTPrefsDomain,LGTLicenseSalt];
    NSData *data=[payload dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *hex=[NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];
    for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [hex appendFormat:@"%02x",digest[i]];
    return hex;
}

static void LGTRefreshLicenseOnline(void) {
    NSString *device=LGTLicenseEnsureDeviceID();
    NSString *token=LGTLicenseTokenForDevice(device);
    NSString *urlString=[NSString stringWithFormat:@"%@?t=%.0f",LGTLicenseRegistryURL,[NSDate date].timeIntervalSince1970];
    NSURL *url=[NSURL URLWithString:urlString];
    if(!url) return;
    NSURLSessionDataTask *task=[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        if(error || !data.length) return;
        id obj=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if(![obj isKindOfClass:NSDictionary.class]) return;
        NSArray *active=[obj objectForKey:@"active"];
        if(![active isKindOfClass:NSArray.class]) return;
        BOOL found=NO;
        for(id value in active){ if([value isKindOfClass:NSString.class] && [[value lowercaseString] isEqualToString:token]) { found=YES; break; } }
        NSUserDefaults *prefs=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain];
        BOOL old=[prefs boolForKey:@"licenseActive"];
        [prefs setBool:found forKey:@"licenseActive"];
        [prefs setObject:(found?@"Activated":@"Unactivated") forKey:@"licenseStatusDisplay"];
        [prefs setDouble:[NSDate date].timeIntervalSince1970 forKey:@"licenseLastCheck"];
        [prefs synchronize];
        if(old!=found){
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),LGTReloadNotification,NULL,NULL,true);
        }
    }];
    [task resume];
}

static void LGTStartLicensePolling(void) {
    LGTLicenseEnsureDeviceID();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{ LGTRefreshLicenseOnline(); });
    if(gLGTLicenseTimer) return;
    gLGTLicenseTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(gLGTLicenseTimer,dispatch_time(DISPATCH_TIME_NOW,60*NSEC_PER_SEC),60*60*NSEC_PER_SEC,30*NSEC_PER_SEC);
    dispatch_source_set_event_handler(gLGTLicenseTimer,^{ LGTRefreshLicenseOnline(); });
    dispatch_resume(gLGTLicenseTimer);
}

'''
runtime = runtime.replace(load_anchor, license_runtime + load_anchor, 1)

old_enabled='    gEnabled=B(@"enabled",YES);'
new_enabled='    gLicenseActive=B(@"licenseActive",NO);\n    gEnabled=B(@"enabled",YES)&&gLicenseActive;'
if old_enabled not in runtime:
    raise SystemExit('runtime enabled load line not found')
runtime = runtime.replace(old_enabled,new_enabled,1)

ctor_anchor='''        MSHookMessageEx(UILabel.class,@selector(setAttributedText:),(IMP)LGTHookedUILabelSetAttributedText,(IMP *)&gOriginalUILabelSetAttributedText);'''
if ctor_anchor not in runtime:
    raise SystemExit('runtime ctor hook anchor not found')
runtime = runtime.replace(ctor_anchor,ctor_anchor+'\n        LGTStartLicensePolling();',1)
runtime_path.write_text(runtime)

# ---------- Preferences license UI ----------
if '#import <CommonCrypto/CommonDigest.h>' not in prefs:
    prefs = prefs.replace('#import <Preferences/PSListController.h>\n', '#import <Preferences/PSListController.h>\n#import <CommonCrypto/CommonDigest.h>\n', 1)

prefs_const_anchor='static CFStringRef const LGTReloadNotification = CFSTR("com.nextsolution.lockglyphtime/ReloadPrefs");'
if prefs_const_anchor not in prefs:
    raise SystemExit('prefs constants anchor not found')
prefs_helpers=r'''
static NSString * const LGTLicenseRegistryURL = @"https://nextsolution.cc/licenses/nextlock.json";
static NSString * const LGTLicenseSalt = @"nextsolution-license-v1";

static NSString *LGTPrefsLicenseDeviceID(void) {
    NSUserDefaults *p=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain];
    NSString *existing=[[p stringForKey:@"licenseDeviceID"] uppercaseString];
    NSRegularExpression *rx=[NSRegularExpression regularExpressionWithPattern:@"^NS-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}$" options:0 error:nil];
    if(existing.length && [rx firstMatchInString:existing options:0 range:NSMakeRange(0,existing.length)]) return existing;
    NSString *raw=[[[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""] uppercaseString];
    if(raw.length<16) return @"NS-0000-0000-0000-0000";
    NSString *device=[NSString stringWithFormat:@"NS-%@-%@-%@-%@",[raw substringWithRange:NSMakeRange(0,4)],[raw substringWithRange:NSMakeRange(4,4)],[raw substringWithRange:NSMakeRange(8,4)],[raw substringWithRange:NSMakeRange(12,4)]];
    [p setObject:device forKey:@"licenseDeviceID"];
    [p setObject:@"Unactivated" forKey:@"licenseStatusDisplay"];
    [p synchronize];
    return device;
}

static NSString *LGTPrefsLicenseToken(NSString *device) {
    NSString *payload=[NSString stringWithFormat:@"%@|%@|%@",device?:@"",LGTPrefsDomain,LGTLicenseSalt];
    NSData *data=[payload dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *hex=[NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];
    for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [hex appendFormat:@"%02x",digest[i]];
    return hex;
}
'''
prefs = prefs.replace(prefs_const_anchor,prefs_const_anchor+'\n'+prefs_helpers,1)

spec_old='- (NSArray *)specifiers { if(!_specifiers)_specifiers=[self loadSpecifiersFromPlistName:[self lgt_plistName] target:self]; return _specifiers; }'
spec_new='- (NSArray *)specifiers { if([[self lgt_plistName] isEqualToString:@"Root"]) LGTPrefsLicenseDeviceID(); if(!_specifiers)_specifiers=[self loadSpecifiersFromPlistName:[self lgt_plistName] target:self]; return _specifiers; }'
if spec_old not in prefs:
    raise SystemExit('prefs specifier method not found')
prefs = prefs.replace(spec_old,spec_new,1)

website_anchor='- (void)openWebsite { NSURL *u=[NSURL URLWithString:@"https://nextsolution.cc"]; if(u)[UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil]; }'
if website_anchor not in prefs:
    raise SystemExit('prefs website action anchor not found')
license_methods=r'''
- (void)lgtRefreshLicenseShowingResult:(BOOL)showResult {
    NSString *device=LGTPrefsLicenseDeviceID();
    NSString *token=LGTPrefsLicenseToken(device);
    NSString *urlString=[NSString stringWithFormat:@"%@?t=%.0f",LGTLicenseRegistryURL,[NSDate date].timeIntervalSince1970];
    NSURL *url=[NSURL URLWithString:urlString];
    if(!url)return;
    __weak typeof(self) weakSelf=self;
    NSURLSessionDataTask *task=[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            typeof(self) selfRef=weakSelf; if(!selfRef)return;
            if(error || !data.length){
                if(showResult){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"NextLock License" message:@"Could not reach the Next Solution license server. Your existing activation state was not changed." preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[selfRef presentViewController:a animated:YES completion:nil];}
                return;
            }
            id obj=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *active=[obj isKindOfClass:NSDictionary.class]?[(NSDictionary *)obj objectForKey:@"active"]:nil;
            if(![active isKindOfClass:NSArray.class])return;
            BOOL found=NO; for(id value in active){if([value isKindOfClass:NSString.class]&&[[value lowercaseString] isEqualToString:token]){found=YES;break;}}
            NSUserDefaults *p=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain];
            [p setBool:found forKey:@"licenseActive"];
            [p setObject:(found?@"Activated":@"Unactivated") forKey:@"licenseStatusDisplay"];
            [p setDouble:[NSDate date].timeIntervalSince1970 forKey:@"licenseLastCheck"];
            [p synchronize];
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),LGTReloadNotification,NULL,NULL,true);
            [selfRef reloadSpecifiers];
            if(showResult){NSString *message=found?@"NextLock is activated on this device.":@"This Device ID is not activated yet. If you already paid, confirm that this exact Device ID has been approved.";UIAlertController *a=[UIAlertController alertControllerWithTitle:(found?@"Activated":@"Unactivated") message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[selfRef presentViewController:a animated:YES completion:nil];}
        });
    }];
    [task resume];
}
- (void)checkActivation { [self lgtRefreshLicenseShowingResult:YES]; }
- (void)copyLicenseDeviceID { NSString *device=LGTPrefsLicenseDeviceID(); UIPasteboard.generalPasteboard.string=device; UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Device ID Copied" message:device preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil]; }
- (void)buyLicense { NSString *device=LGTPrefsLicenseDeviceID(); NSString *escaped=[device stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]; NSURL *u=[NSURL URLWithString:[NSString stringWithFormat:@"https://nextsolution.cc/license/nextlock/?device=%@",escaped?:@""]]; if(u)[UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; if([[self lgt_plistName] isEqualToString:@"Root"]){ LGTPrefsLicenseDeviceID(); [self lgtRefreshLicenseShowingResult:NO]; } }
'''
prefs = prefs.replace(website_anchor,license_methods+'\n'+website_anchor,1)

reset_old='''    NSUserDefaults *p=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain];
    [p removePersistentDomainForName:LGTPrefsDomain]; [p synchronize]; [self lgtNotify]; [self reloadSpecifiers];'''
reset_new='''    NSUserDefaults *p=[[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain];
    NSString *licenseDeviceID=[p stringForKey:@"licenseDeviceID"];
    NSNumber *licenseActive=[p objectForKey:@"licenseActive"];
    NSString *licenseStatus=[p stringForKey:@"licenseStatusDisplay"];
    NSNumber *licenseLastCheck=[p objectForKey:@"licenseLastCheck"];
    [p removePersistentDomainForName:LGTPrefsDomain];
    if(licenseDeviceID)[p setObject:licenseDeviceID forKey:@"licenseDeviceID"];
    if(licenseActive)[p setObject:licenseActive forKey:@"licenseActive"];
    if(licenseStatus)[p setObject:licenseStatus forKey:@"licenseStatusDisplay"];
    if(licenseLastCheck)[p setObject:licenseLastCheck forKey:@"licenseLastCheck"];
    [p synchronize]; [self lgtNotify]; [self reloadSpecifiers];'''
if reset_old not in prefs:
    raise SystemExit('prefs resetAll block not found')
prefs = prefs.replace(reset_old,reset_new,1)
prefs_path.write_text(prefs)

# ---------- Add activation section to Root.plist ----------
root_path = ROOT / 'prefs' / 'Resources' / 'Root.plist'
root = plistlib.loads(root_path.read_bytes())
items = root.get('items', [])
license_items = [
    {'cell':'PSGroupCell','label':'ACTIVATION','footerText':'NextLock requires a $1 USD lifetime license for this generated Next Solution Device ID. Activation is controlled by Next Solution and can be revoked by removing the Device ID from the license registry.'},
    {'cell':'PSTitleValueCell','label':'Status','defaults':'com.nextsolution.lockglyphtime','key':'licenseStatusDisplay','default':'Unactivated'},
    {'cell':'PSTitleValueCell','label':'Device ID','defaults':'com.nextsolution.lockglyphtime','key':'licenseDeviceID','default':'Generating…'},
    {'cell':'PSButtonCell','label':'Copy Device ID','action':'copyLicenseDeviceID'},
    {'cell':'PSButtonCell','label':'Buy / Activate — $1.00','action':'buyLicense'},
    {'cell':'PSButtonCell','label':'Check Activation','action':'checkActivation'},
]
# Prevent duplication during local iterative builds.
items = [x for x in items if not (x.get('cell')=='PSGroupCell' and x.get('label')=='ACTIVATION') and x.get('key') not in {'licenseStatusDisplay','licenseDeviceID'} and x.get('action') not in {'copyLicenseDeviceID','buyLicense','checkActivation'}]
root['items'] = license_items + items
root_path.write_bytes(plistlib.dumps(root,fmt=plistlib.FMT_XML,sort_keys=False))

# ---------- Version metadata ----------
control_path = ROOT / 'control'
control = control_path.read_text()
control = control.replace('Version: 1.0.5','Version: 1.1.0',1)
lines=control.splitlines()
for i,line in enumerate(lines):
    if line.startswith('Description:'):
        lines[i]='Description: Next Solution lock-screen customization suite for time, date, fonts, colors, positioning, shadows, SF Symbols and custom photos. Version 1.1.0 adds Next Solution paid activation with a privacy-safe Device ID and $1 lifetime NextLock license.'
        break
control_path.write_text('\n'.join(lines)+'\n')

resources=ROOT/'prefs'/'Resources'
info_path=resources/'Info.plist'
info=plistlib.loads(info_path.read_bytes())
info['CFBundleShortVersionString']='1.1.0'
info['CFBundleVersion']='110'
info_path.write_bytes(plistlib.dumps(info,fmt=plistlib.FMT_XML,sort_keys=False))

about_path=resources/'About.plist'
about=plistlib.loads(about_path.read_bytes())
for item in about.get('items',[]):
    footer=item.get('footerText')
    if isinstance(footer,str):
        for old in ('Version 1.0.1','Version 1.0.2','Version 1.0.3','Version 1.0.4','Version 1.0.5'):
            footer=footer.replace(old,'Version 1.1.0')
        item['footerText']=footer
about_path.write_bytes(plistlib.dumps(about,fmt=plistlib.FMT_XML,sort_keys=False))

print('Patched NextLock 1.1.0 with Next Solution paid Device ID licensing')
