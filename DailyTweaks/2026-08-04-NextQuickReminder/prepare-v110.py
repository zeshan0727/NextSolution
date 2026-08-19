#!/usr/bin/env python3
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parent

# Version/package metadata.
for rel in ['control', 'ConsoleBridge.m', 'Preferences/Resources/Info.plist', 'Preferences/NQRDiagnosticsController.m', 'layout/DEBIAN/postinst']:
    path = root / rel
    text = path.read_text().replace('1.0.9', '1.0.10')
    if rel == 'control':
        lines = []
        for line in text.splitlines():
            if line.startswith('Description:'):
                line = 'Description: RootHide quick reminder with multi-trigger access, keyboard input, background saving, Dynamic Island/System Aperture due reminders, persistent dismiss, and live size/position controls with a test preview in Settings.'
            lines.append(line)
        text = '\n'.join(lines) + '\n'
    path.write_text(text)

# Add standard PreferenceLoader controls. They use the existing RootHide-safe
# custom getter/setter and Darwin preferences.changed notification, so changing
# any slider updates the currently visible island immediately without respring.
plist_path = root / 'Preferences' / 'Resources' / 'Root.plist'
with plist_path.open('rb') as handle:
    plist = plistlib.load(handle)
items = plist['items']

layout_items = [
    {
        'cell': 'PSGroupCell',
        'label': 'Dynamic Island Layout',
        'footerText': 'Size and position changes apply live. Tap Test Dynamic Island first, then move the sliders and watch the preview update immediately. No respring is required.'
    },
    {'cell':'PSSliderCell','label':'Compact Width','key':'islandCompactWidth','default':250.0,'min':170.0,'max':390.0,'showValue':True,'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'},
    {'cell':'PSSliderCell','label':'Compact Height','key':'islandCompactHeight','default':54.0,'min':44.0,'max':90.0,'showValue':True,'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'},
    {'cell':'PSSliderCell','label':'Compact Vertical Position','key':'islandCompactY','default':4.0,'min':-8.0,'max':90.0,'showValue':True,'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'},
    {'cell':'PSSliderCell','label':'Expanded Width','key':'islandExpandedWidth','default':412.0,'min':280.0,'max':430.0,'showValue':True,'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'},
    {'cell':'PSSliderCell','label':'Expanded Height','key':'islandExpandedHeight','default':108.0,'min':90.0,'max':220.0,'showValue':True,'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'},
    {'cell':'PSSliderCell','label':'Expanded Vertical Position','key':'islandExpandedY','default':4.0,'min':-8.0,'max':180.0,'showValue':True,'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'},
    {'cell':'PSSliderCell','label':'Horizontal Offset','key':'islandHorizontalOffset','default':0.0,'min':-100.0,'max':100.0,'showValue':True,'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'},
    {'cell':'PSButtonCell','label':'Test Dynamic Island','action':'testDynamicIsland'},
    {'cell':'PSButtonCell','label':'Reset Island Layout','action':'resetIslandLayout'},
]

# Insert before the Test & Diagnostics section so layout controls are easy to find.
insert_at = len(items)
for i, item in enumerate(items):
    if item.get('cell') == 'PSGroupCell' and item.get('label') == 'Test & Diagnostics':
        insert_at = i
        break
items[insert_at:insert_at] = layout_items

with plist_path.open('wb') as handle:
    plistlib.dump(plist, handle, fmt=plistlib.FMT_XML, sort_keys=False)

# Add Settings actions for one test preview and reset.
prefs = root / 'Preferences' / 'NQRRootListController.m'
text = prefs.read_text()
anchor = '''- (void)clearSavedDraft {\n'''
if anchor not in text:
    raise SystemExit('Could not find NQRRootListController insertion anchor')
methods = '''- (void)testDynamicIsland {\n    CFNotificationCenterPostNotification(\n        CFNotificationCenterGetDarwinNotifyCenter(),\n        CFSTR("com.nextsolution.nextquickreminder.testisland"),\n        NULL,\n        NULL,\n        true\n    );\n}\n\n- (void)resetIslandLayout {\n    NSDictionary *defaults = @{\n        @"islandCompactWidth": @250.0,\n        @"islandCompactHeight": @54.0,\n        @"islandCompactY": @4.0,\n        @"islandExpandedWidth": @412.0,\n        @"islandExpandedHeight": @108.0,\n        @"islandExpandedY": @4.0,\n        @"islandHorizontalOffset": @0.0\n    };\n    [defaults enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *value, BOOL *stop) {\n        CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, NQRDomain);\n    }];\n    CFPreferencesAppSynchronize(NQRDomain);\n    CFNotificationCenterPostNotification(\n        CFNotificationCenterGetDarwinNotifyCenter(),\n        NQRChanged,\n        NULL,\n        NULL,\n        true\n    );\n    [self reloadSpecifiers];\n}\n\n'''
text = text.replace(anchor, methods + anchor, 1)
prefs.write_text(text)

# Patch System Aperture geometry to use live preferences and add a test preview.
aperture = root / 'SystemApertureReminderV109.xm'
text = aperture.read_text()

# Test-mode flag.
text = text.replace('static BOOL NQR109Expanded = NO;\n', 'static BOOL NQR109Expanded = NO;\nstatic BOOL NQR110TestMode = NO;\n', 1)

# Helpers inserted before date parser.
helper_anchor = 'static NSDate *NQR109DateFromJSON(id value) {\n'
helpers = '''static CGFloat NQR110PreferenceFloat(NSString *key, CGFloat fallback, CGFloat minimum, CGFloat maximum) {\n    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)NQR109PrefsDomain);\n    CGFloat result = fallback;\n    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {\n        NSNumber *number = (__bridge NSNumber *)value;\n        result = number.doubleValue;\n    }\n    if (value) CFRelease(value);\n    return MIN(MAX(result, minimum), maximum);\n}\n\nstatic CGRect NQR110FrameForState(BOOL expanded) {\n    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;\n    CGFloat defaultExpandedWidth = MIN(screenWidth - 18.0, 412.0);\n    CGFloat width = expanded\n        ? NQR110PreferenceFloat(@"islandExpandedWidth", defaultExpandedWidth, 260.0, MAX(260.0, screenWidth - 8.0))\n        : NQR110PreferenceFloat(@"islandCompactWidth", 250.0, 150.0, MAX(150.0, screenWidth - 8.0));\n    CGFloat height = expanded\n        ? NQR110PreferenceFloat(@"islandExpandedHeight", 108.0, 82.0, 240.0)\n        : NQR110PreferenceFloat(@"islandCompactHeight", 54.0, 40.0, 100.0);\n    CGFloat y = expanded\n        ? NQR110PreferenceFloat(@"islandExpandedY", 4.0, -20.0, 220.0)\n        : NQR110PreferenceFloat(@"islandCompactY", 4.0, -20.0, 120.0);\n    CGFloat xOffset = NQR110PreferenceFloat(@"islandHorizontalOffset", 0.0, -140.0, 140.0);\n    CGFloat x = ((screenWidth - width) / 2.0) + xOffset;\n    x = MIN(MAX(x, 4.0), MAX(4.0, screenWidth - width - 4.0));\n    return CGRectMake(x, y, width, height);\n}\n\n'''
if helper_anchor not in text:
    raise SystemExit('Could not find aperture helper insertion anchor')
text = text.replace(helper_anchor, helpers + helper_anchor, 1)

old_geometry = '''    // Both states stay attached to the top System Aperture region. 1.0.8 used\n    // y=84 for its expanded state, which looked like a separate Lock Screen card.\n    CGFloat width = expanded ? MIN(UIScreen.mainScreen.bounds.size.width - 18.0, 412.0) : 250.0;\n    CGFloat height = expanded ? 108.0 : 54.0;\n    CGFloat y = 4.0;\n    CGFloat x = (UIScreen.mainScreen.bounds.size.width - width) / 2.0;\n    void (^changes)(void) = ^{\n        self.frame = CGRectMake(x, y, width, height);\n        self.layer.cornerRadius = expanded ? 29.0 : 27.0;\n        [self layoutIfNeeded];\n    };\n'''
new_geometry = '''    // Geometry is PreferenceLoader-controlled in 1.0.10 and updates live.\n    CGRect targetFrame = NQR110FrameForState(expanded);\n    void (^changes)(void) = ^{\n        self.frame = targetFrame;\n        CGFloat adaptiveRadius = MIN(targetFrame.size.height / 2.0, expanded ? 31.0 : 29.0);\n        self.layer.cornerRadius = MAX(16.0, adaptiveRadius);\n        [self layoutIfNeeded];\n    };\n'''
if old_geometry not in text:
    raise SystemExit('Could not find hard-coded aperture geometry')
text = text.replace(old_geometry, new_geometry, 1)

# Test mode ends when any test action is tapped.
text = text.replace('''- (void)completeTapped {\n    if (self.reminderID.length) NQR109ApplyAction(self.reminderID, YES, 0);''', '''- (void)completeTapped {\n    if (NQR110TestMode) { NQR110TestMode = NO; NQR109RemoveIsland(); return; }\n    if (self.reminderID.length) NQR109ApplyAction(self.reminderID, YES, 0);''', 1)
text = text.replace('''- (void)extendTapped {\n    if (self.reminderID.length) NQR109ApplyAction(self.reminderID, NO, 10 * 60);''', '''- (void)extendTapped {\n    if (NQR110TestMode) { NQR110TestMode = NO; NQR109RemoveIsland(); return; }\n    if (self.reminderID.length) NQR109ApplyAction(self.reminderID, NO, 10 * 60);''', 1)
text = text.replace('''- (void)dismissTapped {\n    NSDictionary *current = NQR109CurrentReminder;''', '''- (void)dismissTapped {\n    if (NQR110TestMode) { NQR110TestMode = NO; NQR109RemoveIsland(); return; }\n    NSDictionary *current = NQR109CurrentReminder;''', 1)

# While the Settings test preview is active, the regular due-reminder timer must
# not immediately remove it because no actual reminder is due.
text = text.replace('''static void NQR109Evaluate(void) {\n    NQR109ReloadDatabase(NO);''', '''static void NQR109Evaluate(void) {\n    if (NQR110TestMode && NQR109IslandView) return;\n    NQR109ReloadDatabase(NO);''', 1)

# Live preference callback + test callback, inserted before database changed callback.
callback_anchor = 'static void NQR109DatabaseChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {\n'
callbacks = '''static void NQR110PreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {\n    dispatch_async(dispatch_get_main_queue(), ^{\n        if ([NQR109IslandView isKindOfClass:NQR109ApertureCard.class]) {\n            [(NQR109ApertureCard *)NQR109IslandView setExpanded:NQR109Expanded animated:NO];\n        }\n    });\n}\n\nstatic void NQR110TestIsland(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {\n    dispatch_async(dispatch_get_main_queue(), ^{\n        NQR110TestMode = YES;\n        NSDictionary *sample = @{\n            @"id": @"00000000-0000-0000-0000-000000001010",\n            @"title": @"Test Reminder — Live Layout",\n            @"dueDate": NQR109JSONStringFromDate([NSDate date]),\n            @"priority": @"medium",\n            @"categoryID": @"A1000000-0000-0000-0000-000000000002",\n            @"notificationsEnabled": @YES,\n            @"completedAt": NSNull.null\n        };\n        NQR109PresentReminder(sample);\n        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{\n            if ([NQR109IslandView isKindOfClass:NQR109ApertureCard.class]) {\n                [(NQR109ApertureCard *)NQR109IslandView setExpanded:YES animated:YES];\n            }\n        });\n    });\n}\n\n'''
if callback_anchor not in text:
    raise SystemExit('Could not find aperture callback insertion anchor')
text = text.replace(callback_anchor, callbacks + callback_anchor, 1)

# Register both Darwin notifications.
constructor_anchor = '''        CFNotificationCenterAddObserver(\n            CFNotificationCenterGetDarwinNotifyCenter(),\n            NULL,\n            NQR109DatabaseChanged,\n            CFSTR("com.nextsolution.nextreminder.database.changed"),\n            NULL,\n            CFNotificationSuspensionBehaviorDeliverImmediately\n        );\n'''
constructor_extra = constructor_anchor + '''        CFNotificationCenterAddObserver(\n            CFNotificationCenterGetDarwinNotifyCenter(),\n            NULL,\n            NQR110PreferencesChanged,\n            CFSTR("com.nextsolution.nextquickreminder.preferences.changed"),\n            NULL,\n            CFNotificationSuspensionBehaviorDeliverImmediately\n        );\n        CFNotificationCenterAddObserver(\n            CFNotificationCenterGetDarwinNotifyCenter(),\n            NULL,\n            NQR110TestIsland,\n            CFSTR("com.nextsolution.nextquickreminder.testisland"),\n            NULL,\n            CFNotificationSuspensionBehaviorDeliverImmediately\n        );\n'''
if constructor_anchor not in text:
    raise SystemExit('Could not find aperture constructor observer anchor')
text = text.replace(constructor_anchor, constructor_extra, 1)
text = text.replace('1.0.9 island-only System Aperture reminder loaded with persistent dismiss state', '1.0.10 System Aperture reminder loaded with live layout preferences + test preview')
aperture.write_text(text)

# Version string from the main tweak.
tweak = root / 'Tweak.xm'
tweak.write_text(tweak.read_text().replace(
    'Next Quick Reminder 1.0.9 loaded with island-only System Aperture + persistent dismiss',
    'Next Quick Reminder 1.0.10 loaded with live island layout preferences'
))

print('Prepared Next Quick Reminder 1.0.10 live Dynamic Island layout controls and test preview.')
