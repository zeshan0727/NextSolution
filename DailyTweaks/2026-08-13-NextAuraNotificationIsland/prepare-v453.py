#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parent
path = root / 'NotificationIsland.xm'
s = path.read_text()

# Restore any stock notification view that the Island temporarily suppressed.
# This prevents blank/ghost rows in Lock Screen and Notification Center history.
anchor = 'static void NANRemoveIsland(void);\nstatic void NANPresentModel(NSDictionary *model, UIViewController *shortLook);\n'
helper = r'''static void NANRestoreShortLook(UIViewController *shortLook) {
    if (!shortLook || !shortLook.view) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        shortLook.view.hidden = NO;
        shortLook.view.alpha = 1.0;
        shortLook.view.userInteractionEnabled = YES;
    });
}

'''
if 'static void NANRestoreShortLook' not in s:
    if anchor not in s:
        raise SystemExit('Short-look helper anchor missing')
    s = s.replace(anchor, helper + anchor, 1)

# Restore the currently suppressed stock card before forgetting its controller.
old_remove = '''static void NANRemoveIslandOnMain(void) {
    [NANHideTimer invalidate]; NANHideTimer = nil;
    [NANPrivacyTimer invalidate]; NANPrivacyTimer = nil;
    [NANIslandView removeFromSuperview];
    NANIslandView = nil;
    NANCurrentModel = nil;
    NANCurrentShortLook = nil;
    NANExpanded = NO;
}
'''
new_remove = '''static void NANRemoveIslandOnMain(void) {
    [NANHideTimer invalidate]; NANHideTimer = nil;
    [NANPrivacyTimer invalidate]; NANPrivacyTimer = nil;
    NANRestoreShortLook(NANCurrentShortLook);
    [NANIslandView removeFromSuperview];
    NANIslandView = nil;
    NANCurrentModel = nil;
    NANCurrentShortLook = nil;
    NANExpanded = NO;
}
'''
if old_remove not in s:
    raise SystemExit('NANRemoveIslandOnMain anchor missing')
s = s.replace(old_remove, new_remove, 1)

# Dismiss the Island immediately, but never make the real notification cell
# transparent. The stock notification stays available in Notification Center.
old_dismiss = '''- (void)dismissTapped {
    if (NANTestMode) { NANTestMode = NO; NANRemoveIsland(); return; }
    if (self.fingerprint.length) NANMarkDismissed(self.fingerprint);
    UIViewController *shortLook = NANCurrentShortLook;
    if (shortLook) {
        dispatch_async(dispatch_get_main_queue(), ^{
            shortLook.view.hidden = YES;
            shortLook.view.alpha = 0.0;
        });
    }
    NANRemoveIsland();
}
'''
new_dismiss = '''- (void)dismissTapped {
    if (NANTestMode) { NANTestMode = NO; NANRemoveIsland(); return; }
    if (self.fingerprint.length) NANMarkDismissed(self.fingerprint);
    NANRestoreShortLook(NANCurrentShortLook);
    NANRemoveIsland();
}
'''
if old_dismiss not in s:
    raise SystemExit('dismissTapped anchor missing')
s = s.replace(old_dismiss, new_dismiss, 1)

# Every time a stock notification view comes back on screen, reset visibility
# first. This repairs rows that were left transparent by an older NextAura build.
old_hook = '''%hook NCNotificationShortLookViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    id request = NANSafeValue(self, @"notificationRequest");
'''
new_hook = '''%hook NCNotificationShortLookViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    self.view.hidden = NO;
    self.view.alpha = 1.0;
    self.view.userInteractionEnabled = YES;
    id request = NANSafeValue(self, @"notificationRequest");
'''
if old_hook not in s:
    raise SystemExit('viewWillAppear hook anchor missing')
s = s.replace(old_hook, new_hook, 1)

# Only suppress the currently represented stock banner while its Island is
# actually visible. Historical cells and previous notifications remain visible.
old_didappear = '''- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (NANBool(@"NotificationIslandReplaceStockBanner", YES) && NANCurrentShortLook == self) {
        self.view.alpha = 0.0;
        self.view.userInteractionEnabled = NO;
    }
}
'''
new_didappear = '''- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (NANBool(@"NotificationIslandReplaceStockBanner", YES) && NANCurrentShortLook == self && NANIslandView != nil) {
        self.view.hidden = NO;
        self.view.alpha = 0.0;
        self.view.userInteractionEnabled = NO;
    } else {
        self.view.hidden = NO;
        self.view.alpha = 1.0;
        self.view.userInteractionEnabled = YES;
    }
}
'''
if old_didappear not in s:
    raise SystemExit('viewDidAppear hook anchor missing')
s = s.replace(old_didappear, new_didappear, 1)

# Identify this maintenance revision in logs while retaining the historical CI marker.
s = s.replace(
    'Notification Island 4.5.0 loaded; maintenance 4.5.2 exact-app Open + persistent Test preview',
    'Notification Island 4.5.0 loaded; maintenance 4.5.3 ghost-row restore + exact-app Open + persistent Test preview',
    1
)

path.write_text(s)
print('Prepared NextAura Notification Island 4.5.3 ghost-notification visibility fix.')
