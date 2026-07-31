#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static CFStringRef const HSFPreferenceDomain = CFSTR("com.nextsolution.nexthometorch");
static CFStringRef const HSFPreferencesChanged = CFSTR("com.nextsolution.nexthometorch.preferences.changed");
static BOOL HSFEnabled = YES;

static BOOL HSFIsSpringBoard(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] ||
           [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"];
}

static void HSFReloadPreferences(void) {
    CFPreferencesAppSynchronize(HSFPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), HSFPreferenceDomain));
    HSFEnabled = value ? [value boolValue] : YES;
}

static id HSFSharedFlashlightController(void) {
    Class controllerClass = objc_getClass("SBUIFlashlightController");
    if (!controllerClass) return nil;

    for (NSString *selectorName in @[@"sharedInstance", @"sharedController"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([controllerClass respondsToSelector:selector]) {
            return ((id (*)(id, SEL))objc_msgSend)(controllerClass, selector);
        }
    }
    return nil;
}

static BOOL HSFToggleFlashlight(void) {
    id controller = HSFSharedFlashlightController();
    if (!controller) return NO;

    SEL toggleSelector = NSSelectorFromString(@"toggleFlashlight");
    if ([controller respondsToSelector:toggleSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(controller, toggleSelector);
        return YES;
    }

    SEL levelSelector = NSSelectorFromString(@"level");
    SEL setLevelSelector = NSSelectorFromString(@"setLevel:");
    if ([controller respondsToSelector:levelSelector] &&
        [controller respondsToSelector:setLevelSelector]) {
        CGFloat currentLevel = ((CGFloat (*)(id, SEL))objc_msgSend)(controller, levelSelector);
        CGFloat targetLevel = currentLevel > 0.01 ? 0.0 : 1.0;
        ((void (*)(id, SEL, CGFloat))objc_msgSend)(controller, setLevelSelector, targetLevel);
        return YES;
    }

    SEL flashlightLevelSelector = NSSelectorFromString(@"flashlightLevel");
    SEL setFlashlightLevelSelector = NSSelectorFromString(@"setFlashlightLevel:");
    if ([controller respondsToSelector:flashlightLevelSelector] &&
        [controller respondsToSelector:setFlashlightLevelSelector]) {
        CGFloat currentLevel = ((CGFloat (*)(id, SEL))objc_msgSend)(controller, flashlightLevelSelector);
        CGFloat targetLevel = currentLevel > 0.01 ? 0.0 : 1.0;
        ((void (*)(id, SEL, CGFloat))objc_msgSend)(controller, setFlashlightLevelSelector, targetLevel);
        return YES;
    }

    return NO;
}

static void HSFPreferencesChangedCallback(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo) {
    HSFReloadPreferences();
}

// Same proven gesture path used by Home Lock: SBIconListView receives
// empty Home Screen background touches and reports tapCount == 2.
%hook SBIconListView

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    NSUInteger tapCount = touch ? touch.tapCount : 0;

    if (HSFEnabled && tapCount == 2 && HSFToggleFlashlight()) {
        return;
    }

    %orig;
}

%end

%ctor {
    @autoreleasepool {
        if (!HSFIsSpringBoard()) return;
        HSFReloadPreferences();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        HSFPreferencesChangedCallback,
                                        HSFPreferencesChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
