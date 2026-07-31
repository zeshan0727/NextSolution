#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static CFStringRef const NHTPreferenceDomain = CFSTR("com.nextsolution.nexthometorch");
static CFStringRef const NHTPreferencesChanged = CFSTR("com.nextsolution.nexthometorch.preferences.changed");
static BOOL NHTEnabled = YES;

static BOOL NHTIsSpringBoard(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] ||
           [[[NSProcessInfo processInfo] processName] isEqualToString:@"SpringBoard"];
}

static BOOL NHTReadEnabled(void) {
    CFPreferencesAppSynchronize(NHTPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), NHTPreferenceDomain));
    return value ? [value boolValue] : YES;
}

static void NHTReloadPreferences(void) {
    NHTEnabled = NHTReadEnabled();
}

static id NHTSharedFlashlightController(void) {
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

static BOOL NHTToggleFlashlight(void) {
    id controller = NHTSharedFlashlightController();
    if (!controller) return NO;

    SEL levelSelector = NSSelectorFromString(@"level");
    SEL setLevelSelector = NSSelectorFromString(@"setLevel:");
    if (![controller respondsToSelector:levelSelector] ||
        ![controller respondsToSelector:setLevelSelector]) return NO;

    CGFloat currentLevel = ((CGFloat (*)(id, SEL))objc_msgSend)(controller, levelSelector);
    CGFloat targetLevel = currentLevel > 0.01 ? 0.0 : 1.0;
    ((void (*)(id, SEL, CGFloat))objc_msgSend)(controller, setLevelSelector, targetLevel);
    return YES;
}

static void NHTPreferencesChangedCallback(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo) {
    NHTReloadPreferences();
}

%hook SBIconListView

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    NSUInteger touchCount = touches.count;
    BOOL allTouchesEnded = touchCount == 2;

    for (UITouch *touch in touches) {
        if (touch.phase != UITouchPhaseEnded || touch.tapCount != 1) {
            allTouchesEnded = NO;
            break;
        }
    }

    if (NHTEnabled && allTouchesEnded && NHTToggleFlashlight()) {
        return;
    }

    %orig;
}

%end

%ctor {
    @autoreleasepool {
        if (!NHTIsSpringBoard()) return;
        NHTReloadPreferences();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        NHTPreferencesChangedCallback,
                                        NHTPreferencesChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
