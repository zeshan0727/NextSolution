#!/usr/bin/env python3
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parent

# Version and package metadata.
for rel in ['control', 'ConsoleBridge.m', 'Preferences/Resources/Info.plist', 'Preferences/NQRDiagnosticsController.m', 'layout/DEBIAN/postinst']:
    path = root / rel
    text = path.read_text().replace('1.0.4', '1.0.5').replace('1.0.3', '1.0.5').replace('1.0.0', '1.0.5')
    if rel == 'control':
        lines = []
        for line in text.splitlines():
            if line.startswith('Description:'):
                line = 'Description: RootHide quick reminder card with reliable multi-trigger access, Lock Screen support, background saving, and in-panel Quick Access settings.'
            lines.append(line)
        text = '\n'.join(lines) + '\n'
    path.write_text(text)

# Compile the new multi-trigger engine.
makefile = root / 'Makefile'
text = makefile.read_text()
text = text.replace(
    'NextQuickReminder_FILES = Tweak.xm ConsoleBridge.m BackgroundLockscreen.xm',
    'NextQuickReminder_FILES = Tweak.xm ConsoleBridge.m BackgroundLockscreen.xm MultiTriggersSettings.xm'
)
makefile.write_text(text)

# Link Preference bundle against Apple's Preferences framework instead of depending on unresolved dynamic symbols.
prefs_makefile = root / 'Preferences' / 'Makefile'
text = prefs_makefile.read_text()
if 'NextQuickReminderPreferences_PRIVATE_FRAMEWORKS = Preferences' not in text:
    text = text.replace(
        'NextQuickReminderPreferences_FRAMEWORKS = UIKit Foundation\n',
        'NextQuickReminderPreferences_FRAMEWORKS = UIKit Foundation\nNextQuickReminderPreferences_PRIVATE_FRAMEWORKS = Preferences\n'
    )
text = text.replace('NextQuickReminderPreferences_LDFLAGS = -Wl,-undefined,dynamic_lookup -Wl,-segalign,4000', 'NextQuickReminderPreferences_LDFLAGS = -Wl,-segalign,4000')
prefs_makefile.write_text(text)

# New independent trigger switches in Settings. The panel has the same controls as a RootHide-safe fallback.
plist_path = root / 'Preferences' / 'Resources' / 'Root.plist'
with plist_path.open('rb') as handle:
    plist = plistlib.load(handle)

items = plist['items']
items[:] = [
    {
        'cell': 'PSGroupCell',
        'label': 'Next Quick Reminder',
        'footerText': 'Enable any combination of quick-access triggers. The same options are available from the gear button inside the Quick Reminder card, so the tweak remains configurable even if PreferenceLoader is unavailable.'
    },
    {'cell':'PSSwitchCell','label':'Double-tap Status-Bar Time','key':'triggerStatusBar','default':True,'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'},
    {'cell':'PSSwitchCell','label':'Hold Volume Up','key':'triggerVolumeUp','default':True,'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'},
    {'cell':'PSSwitchCell','label':'Hold Volume Down','key':'triggerVolumeDown','default':False,'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'},
    {'cell':'PSSwitchCell','label':'Shake Device','key':'triggerShake','default':False,'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'},
    {'cell':'PSSwitchCell','label':'Lock Screen Clock Double-Tap','key':'triggerLockScreen','default':True,'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'},
    {'cell':'PSSwitchCell','label':'Trigger Haptic','key':'triggerHaptic','default':True,'get':'readPreferenceValue:','set':'setPreferenceValue:specifier:'},
    {
        'cell': 'PSGroupCell',
        'label': 'Test & Diagnostics',
        'footerText': 'Status-Bar access refreshes automatically after SpringBoard UI changes. Volume buttons keep their normal volume behavior.'
    },
    {'cell':'PSButtonCell','label':'Test Quick Panel','action':'testQuickPanel'},
    {'cell':'PSLinkCell','label':'Diagnostics & Console','detail':'NQRDiagnosticsController'},
    {'cell':'PSButtonCell','label':'Clear Saved Draft','action':'clearSavedDraft'},
]
with plist_path.open('wb') as handle:
    plistlib.dump(plist, handle, fmt=plistlib.FMT_XML, sort_keys=False)

# 1.0.4 lock-screen hook should follow the independent lock-screen toggle, not the old exclusive gesture preference.
background = root / 'BackgroundLockscreen.xm'
text = background.read_text()
old = '''static BOOL NQR104StatusGestureSelected(void) {
    id value = NQR104Preference(@"gesture");
    return [value isKindOfClass:NSString.class] && [value isEqualToString:@"statusbar"];
}'''
new = '''static BOOL NQR104StatusGestureSelected(void) {
    id value = NQR104Preference(@"triggerLockScreen");
    return ![value isKindOfClass:NSNumber.class] || [value boolValue];
}'''
if old not in text:
    raise SystemExit('Could not find 1.0.4 lock-screen preference helper')
text = text.replace(old, new, 1)
background.write_text(text)

print('Prepared Next Quick Reminder 1.0.5 multi-trigger RootHide package.')
