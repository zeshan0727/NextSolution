#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
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
            id controller = ((id (*)(id, SEL))objc_msgSend)(controllerClass, selector);
            if (controller) return controller;
        }
    }
    return nil;
}

static BOOL HSFToggleUsingSpringBoardController(void) {
    id controller = HSFSharedFlashlightController();
    if (!controller) return NO;

    SEL toggleSelector = NSSelectorFromString(@"toggleFlashlight");
    if ([controller respondsToSelector:toggleSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(controller, toggleSelector);
        return YES;
    }

    for (NSArray<NSString *> *pair in @[
        @[@"level", @"setLevel:"],
        @[@"flashlightLevel", @"setFlashlightLevel:"]
    ]) {
        SEL getSelector = NSSelectorFromString(pair[0]);
        SEL setSelector = NSSelectorFromString(pair[1]);
        if ([controller respondsToSelector:getSelector] && [controller respondsToSelector:setSelector]) {
            CGFloat currentLevel = ((CGFloat (*)(id, SEL))objc_msgSend)(controller, getSelector);
            ((void (*)(id, SEL, CGFloat))objc_msgSend)(controller, setSelector, currentLevel > 0.01 ? 0.0 : 1.0);
            return YES;
        }
    }

    return NO;
}

static BOOL HSFToggleUsingAVFoundation(void) {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!device || !device.hasTorch || !device.isTorchAvailable) return NO;

    NSError *error = nil;
    if (![device lockForConfiguration:&error]) return NO;

    BOOL success = NO;
    if (device.isTorchActive) {
        device.torchMode = AVCaptureTorchModeOff;
        success = YES;
    } else {
        success = [device setTorchModeOnWithLevel:1.0 error:&error];
    }

    [device unlockForConfiguration];
    return success;
}

static BOOL HSFToggleFlashlight(void) {
    if (HSFToggleUsingSpringBoardController()) return YES;
    return HSFToggleUsingAVFoundation();
}

static void HSFPreferencesChangedCallback(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo) {
    HSFReloadPreferences();
}

// Uses the same verified Home Screen hook and double-tap detection as Home Lock.
%hook SBIconListView

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    NSUInteger tapCount = touch ? touch.tapCount : 0;

    if (HSFEnabled && tapCount == 2) {
        dispatch_async(dispatch_get_main_queue(), ^{
            HSFToggleFlashlight();
        });
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
