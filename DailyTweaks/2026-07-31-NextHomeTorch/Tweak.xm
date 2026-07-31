#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static CFStringRef const NHTPreferenceDomain = CFSTR("com.nextsolution.nexthometorch");
static CFStringRef const NHTPreferencesChanged = CFSTR("com.nextsolution.nexthometorch.preferences.changed");
static BOOL NHTEnabled = YES;

static BOOL NHTIsSpringBoard(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] || [[[NSProcessInfo processInfo] processName] isEqualToString:@"SpringBoard"];
}

static void NHTReloadPreferences(void) {
    CFPreferencesAppSynchronize(NHTPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), NHTPreferenceDomain));
    NHTEnabled = value ? [value boolValue] : YES;
}

static id NHTSharedFlashlightController(void) {
    Class cls = objc_getClass("SBUIFlashlightController");
    if (!cls) return nil;
    for (NSString *name in @[@"sharedInstance", @"sharedController"]) {
        SEL sel = NSSelectorFromString(name);
        if ([cls respondsToSelector:sel]) return ((id (*)(id, SEL))objc_msgSend)(cls, sel);
    }
    return nil;
}

static BOOL NHTToggleFlashlight(void) {
    id controller = NHTSharedFlashlightController();
    if (!controller) return NO;
    SEL levelSel = NSSelectorFromString(@"level");
    SEL setLevelSel = NSSelectorFromString(@"setLevel:");
    if (![controller respondsToSelector:levelSel] || ![controller respondsToSelector:setLevelSel]) return NO;
    CGFloat level = ((CGFloat (*)(id, SEL))objc_msgSend)(controller, levelSel);
    ((void (*)(id, SEL, CGFloat))objc_msgSend)(controller, setLevelSel, level > 0.01 ? 0.0 : 1.0);
    return YES;
}

static BOOL NHTEventIsCompletedTwoFingerTap(UIEvent *event) {
    NSSet *allTouches = event.allTouches;
    if (allTouches.count != 2) return NO;
    for (UITouch *touch in allTouches) {
        if (touch.tapCount != 1) return NO;
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) return NO;
    }
    return YES;
}

static void NHTPreferencesChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NHTReloadPreferences();
}

%hook SBIconListView
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    BOOL shouldToggle = NHTEnabled && NHTEventIsCompletedTwoFingerTap(event);
    %orig;
    if (shouldToggle) NHTToggleFlashlight();
}
%end

%ctor {
    @autoreleasepool {
        if (!NHTIsSpringBoard()) return;
        NHTReloadPreferences();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NHTPreferencesChangedCallback, NHTPreferencesChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
