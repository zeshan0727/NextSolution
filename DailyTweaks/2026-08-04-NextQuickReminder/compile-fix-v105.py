#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parent

path = root / 'MultiTriggersSettings.xm'
text = path.read_text()
old = '''        UIWindowScene *scene = NQR105ActiveScene();
        if (!NQR105StatusWindow || (@available(iOS 13.0, *) && scene && NQR105StatusWindow.windowScene != scene)) {
            NQR105DestroyStatusWindow();
            if (@available(iOS 13.0, *)) {'''
new = '''        UIWindowScene *scene = NQR105ActiveScene();
        BOOL needsNewWindow = (NQR105StatusWindow == nil);
        if (@available(iOS 13.0, *)) {
            if (scene && NQR105StatusWindow && NQR105StatusWindow.windowScene != scene) {
                needsNewWindow = YES;
            }
        }
        if (needsNewWindow) {
            NQR105DestroyStatusWindow();
            if (@available(iOS 13.0, *)) {'''
if old in text:
    text = text.replace(old, new, 1)
elif 'BOOL needsNewWindow' not in text:
    raise SystemExit('v1.0.5 availability guard anchor not found')
path.write_text(text)

# The RootHide Theos SDK does not ship the Preferences private framework binary.
# Keep the proven PreferenceLoader dynamic-link method used by v1.0.4. The new
# in-panel Quick Access sheet is independent of PreferenceLoader and is the
# reliable configuration path on devices where the Settings bundle cannot load.
prefs = root / 'Preferences' / 'Makefile'
prefs_text = prefs.read_text()
prefs_text = prefs_text.replace('NextQuickReminderPreferences_PRIVATE_FRAMEWORKS = Preferences\n', '')
prefs_text = prefs_text.replace(
    'NextQuickReminderPreferences_LDFLAGS = -Wl,-segalign,4000',
    'NextQuickReminderPreferences_LDFLAGS = -Wl,-undefined,dynamic_lookup -Wl,-segalign,4000'
)
prefs.write_text(prefs_text)

print('Applied v1.0.5 compiler and RootHide preference-bundle compatibility fixes.')
