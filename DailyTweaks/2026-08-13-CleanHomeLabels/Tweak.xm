#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static CFStringRef const CHLPreferenceDomain = CFSTR("com.nextsolution.cleanhomelabels");
static CFStringRef const CHLPreferencesChanged = CFSTR("com.nextsolution.cleanhomelabels.preferences.changed");
static BOOL CHLEnabled = YES;

static BOOL CHLIsSpringBoardProcess(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] || [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"];
}

static BOOL CHLReadEnabled(void) {
    CFPreferencesAppSynchronize(CHLPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), CHLPreferenceDomain));
    return value ? [value boolValue] : YES;
}

static void CHLReloadPreferences(void) {
    CHLEnabled = CHLReadEnabled();
}

static BOOL CHLResolvedHidden(BOOL enabled, BOOL requestedHidden) {
    return enabled ? YES : requestedHidden;
}

static void CHLPreferencesChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    CHLReloadPreferences();
}

%hook SBIconView
- (void)setLabelHidden:(BOOL)hidden {
    %orig(CHLResolvedHidden(CHLEnabled, hidden));
}
%end

%ctor {
    @autoreleasepool {
        if (!CHLIsSpringBoardProcess()) return;
        CHLReloadPreferences();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CHLPreferencesChangedCallback, CHLPreferencesChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
