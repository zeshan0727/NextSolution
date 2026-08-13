#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parent

# Version bump only; the Settings page itself is intentionally unchanged.
for rel in ['control', 'ConsoleBridge.m', 'Preferences/Resources/Info.plist', 'Preferences/NQRDiagnosticsController.m', 'layout/DEBIAN/postinst']:
    path = root / rel
    text = path.read_text().replace('1.0.10', '1.0.11')
    if rel == 'control':
        text = '\n'.join(
            'Description: RootHide quick reminder with multi-trigger access, background scheduling, live island layout controls and improved text-input focus.' if line.startswith('Description:') else line
            for line in text.splitlines()
        ) + '\n'
    path.write_text(text)

path = root / 'Tweak.xm'
text = path.read_text()

old_scene = '''static UIWindowScene *NQRActiveWindowScene(void) {\n    if (@available(iOS 13.0, *)) {\n        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {\n            if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState != UISceneActivationStateUnattached) {\n                return (UIWindowScene *)scene;\n            }\n        }\n        for (UIWindow *window in UIApplication.sharedApplication.windows) {\n            if (window.windowScene) return window.windowScene;\n        }\n    }\n    return nil;\n}\n'''
new_scene = '''static UIWindowScene *NQRActiveWindowScene(void) {\n    if (@available(iOS 13.0, *)) {\n        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {\n            if (![candidate isKindOfClass:UIWindowScene.class] || candidate.activationState != UISceneActivationStateForegroundActive) continue;\n            UIWindowScene *scene = (UIWindowScene *)candidate;\n            for (UIWindow *window in scene.windows) {\n                if (window.isKeyWindow && window != NQRStatusGestureWindow && window != NQRPanelWindow) return scene;\n            }\n        }\n        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {\n            if ([candidate isKindOfClass:UIWindowScene.class] && candidate.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)candidate;\n        }\n        for (UIWindow *window in UIApplication.sharedApplication.windows) {\n            if (window.windowScene) return window.windowScene;\n        }\n    }\n    return nil;\n}\n'''
if old_scene not in text:
    raise SystemExit('Scene selection anchor not found')
text = text.replace(old_scene, new_scene, 1)

old_focus = '''    BOOL accepted = [responder becomeFirstResponder];\n    NQRLog(@"Keyboard focus request source=%@ keyWindow=%@ accepted=%@ firstResponder=%@", source ?: @"unknown", NQRPanelWindow.isKeyWindow ? @"YES" : @"NO", accepted ? @"YES" : @"NO", responder.isFirstResponder ? @"YES" : @"NO");\n    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{\n        if (NQRPanelWindow && !NQRPanelWindow.isKeyWindow) [NQRPanelWindow makeKeyWindow];\n        if (!responder.isFirstResponder) [responder becomeFirstResponder];\n        [responder reloadInputViews];\n    });\n'''
new_focus = '''    NQRPanelWindow.windowLevel = UIWindowLevelAlert + 1.0;\n    BOOL accepted = [responder becomeFirstResponder];\n    NQRLog(@"Keyboard focus request source=%@ keyWindow=%@ accepted=%@ firstResponder=%@", source ?: @"unknown", NQRPanelWindow.isKeyWindow ? @"YES" : @"NO", accepted ? @"YES" : @"NO", responder.isFirstResponder ? @"YES" : @"NO");\n    for (NSNumber *delay in @[@0.04, @0.12, @0.28]) {\n        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{\n            if (!NQRPanelWindow) return;\n            [NQRPanelWindow makeKeyAndVisible];\n            if (!responder.isFirstResponder) [responder becomeFirstResponder];\n            if (responder.isFirstResponder) [responder reloadInputViews];\n        });\n    }\n'''
if old_focus not in text:
    raise SystemExit('Keyboard focus anchor not found')
text = text.replace(old_focus, new_focus, 1)

text = text.replace('NQRPanelWindow.windowLevel = UIWindowLevelAlert + 40.0;', 'NQRPanelWindow.windowLevel = UIWindowLevelAlert + 1.0;', 1)
text = text.replace('Next Quick Reminder 1.0.10 loaded with live island layout preferences', 'Next Quick Reminder 1.0.11 loaded with keyboard focus reliability update')
path.write_text(text)

background = root / 'BackgroundLockscreen.xm'
background.write_text(background.read_text().replace('UIWindowLevelAlert + 40.0', 'UIWindowLevelAlert + 1.0'))

print('Prepared Next Quick Reminder 1.0.11 keyboard focus update without changing Settings controls.')
