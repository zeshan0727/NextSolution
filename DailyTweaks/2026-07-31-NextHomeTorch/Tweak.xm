#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static NSString *const HSFVersion = @"1.0.4";
static CFStringRef const HSFPreferenceDomain = CFSTR("com.nextsolution.nexthometorch");
static CFStringRef const HSFRuntimeDomain = CFSTR("com.nextsolution.nexthometorch.runtime");
static CFStringRef const HSFPreferencesChanged = CFSTR("com.nextsolution.nexthometorch.preferences.changed");
static CFStringRef const HSFTestNotification = CFSTR("com.nextsolution.nexthometorch.test-flashlight");
static BOOL HSFEnabled = YES;
static dispatch_queue_t HSFStatusQueue;

static BOOL HSFIsSpringBoard(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] ||
           [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"];
}

static void HSFWriteStatus(NSDictionary<NSString *, id> *updates) {
    if (!updates.count || !HSFStatusQueue) return;
    dispatch_async(HSFStatusQueue, ^{
        [updates enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                     (__bridge CFPropertyListRef)value,
                                     HSFRuntimeDomain);
        }];
        CFPreferencesSetAppValue(CFSTR("updatedAt"),
                                 (__bridge CFNumberRef)@([NSDate date].timeIntervalSince1970),
                                 HSFRuntimeDomain);
        CFPreferencesAppSynchronize(HSFRuntimeDomain);
    });
}

static void HSFReloadPreferences(void) {
    CFPreferencesAppSynchronize(HSFPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), HSFPreferenceDomain));
    HSFEnabled = value ? [value boolValue] : YES;
    HSFWriteStatus(@{@"enabled": @(HSFEnabled)});
}

static void HSFLoadFlashlightFrameworks(void) {
    const char *paths[] = {
        "/System/Library/PrivateFrameworks/SpringBoardUIServices.framework/SpringBoardUIServices",
        "/System/Library/PrivateFrameworks/SpringBoardUI.framework/SpringBoardUI",
        "/System/Library/PrivateFrameworks/ControlCenterUIKit.framework/ControlCenterUIKit"
    };
    for (NSUInteger index = 0; index < sizeof(paths) / sizeof(paths[0]); index++) {
        dlopen(paths[index], RTLD_LAZY | RTLD_GLOBAL);
    }
}

static id HSFSharedFlashlightController(void) {
    HSFLoadFlashlightFrameworks();
    Class controllerClass = objc_getClass("SBUIFlashlightController");
    if (!controllerClass) return nil;

    for (NSString *selectorName in @[@"sharedInstance", @"sharedController", @"sharedFlashlightController"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([controllerClass respondsToSelector:selector]) {
            id controller = ((id (*)(id, SEL))objc_msgSend)(controllerClass, selector);
            if (controller) return controller;
        }
    }

    if ([controllerClass instancesRespondToSelector:@selector(init)]) {
        return [[controllerClass alloc] init];
    }
    return nil;
}

static NSString *HSFToggleUsingSpringBoardController(void) {
    id controller = HSFSharedFlashlightController();
    if (!controller) return nil;

    for (NSString *toggleName in @[@"toggleFlashlight", @"toggle", @"toggleState"]) {
        SEL selector = NSSelectorFromString(toggleName);
        if ([controller respondsToSelector:selector]) {
            ((void (*)(id, SEL))objc_msgSend)(controller, selector);
            return [NSString stringWithFormat:@"SBUIFlashlightController %@", toggleName];
        }
    }

    for (NSArray<NSString *> *pair in @[
        @[@"level", @"setLevel:"],
        @[@"flashlightLevel", @"setFlashlightLevel:"]
    ]) {
        SEL getter = NSSelectorFromString(pair[0]);
        SEL setter = NSSelectorFromString(pair[1]);
        if ([controller respondsToSelector:getter] && [controller respondsToSelector:setter]) {
            CGFloat current = ((CGFloat (*)(id, SEL))objc_msgSend)(controller, getter);
            ((void (*)(id, SEL, CGFloat))objc_msgSend)(controller, setter, current > 0.01 ? 0.0 : 1.0);
            return [NSString stringWithFormat:@"SBUIFlashlightController %@", pair[1]];
        }
    }
    return nil;
}

static NSString *HSFToggleUsingAVFoundation(void) {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!device || !device.hasTorch || !device.isTorchAvailable) return nil;

    NSError *error = nil;
    if (![device lockForConfiguration:&error]) return nil;

    BOOL success = NO;
    if (device.isTorchActive) {
        device.torchMode = AVCaptureTorchModeOff;
        success = YES;
    } else {
        success = [device setTorchModeOnWithLevel:1.0 error:&error];
    }
    [device unlockForConfiguration];
    return success ? @"AVCaptureDevice torch" : nil;
}

static void HSFToggleFlashlight(NSString *source) {
    NSString *route = HSFToggleUsingSpringBoardController();
    if (!route) route = HSFToggleUsingAVFoundation();

    HSFWriteStatus(@{
        @"lastSource": source ?: @"Unknown",
        @"lastRoute": route ?: @"No compatible flashlight route",
        @"lastAttemptAt": @([NSDate date].timeIntervalSince1970),
        @"lastAttemptSucceeded": @(route != nil)
    });
}

static void HSFPreferencesChangedCallback(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object,
                                          CFDictionaryRef userInfo) {
    HSFReloadPreferences();
}

static void HSFTestCallback(CFNotificationCenterRef center, void *observer,
                            CFStringRef name, const void *object,
                            CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        HSFToggleFlashlight(@"Settings test button");
    });
}

%hook SBIconListView

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    NSUInteger tapCount = touch ? touch.tapCount : 0;

    HSFWriteStatus(@{
        @"iconListHookSeen": @YES,
        @"lastTapCount": @(tapCount),
        @"lastTapAt": @([NSDate date].timeIntervalSince1970)
    });

    if (HSFEnabled && tapCount == 2) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback prepare];
        [feedback impactOccurred];
        HSFToggleFlashlight(@"SBIconListView double-tap");
        return;
    }

    %orig;
}

%end

%ctor {
    @autoreleasepool {
        if (!HSFIsSpringBoard()) return;

        HSFStatusQueue = dispatch_queue_create("com.nextsolution.nexthometorch.runtime", DISPATCH_QUEUE_SERIAL);
        HSFLoadFlashlightFrameworks();
        HSFReloadPreferences();

        HSFWriteStatus(@{
            @"tweakLoaded": @YES,
            @"loadedVersion": HSFVersion,
            @"loadedAt": @([NSDate date].timeIntervalSince1970),
            @"processName": [NSProcessInfo processInfo].processName ?: @"Unknown",
            @"iconListClassPresent": @(objc_getClass("SBIconListView") != Nil),
            @"flashlightClassPresent": @(objc_getClass("SBUIFlashlightController") != Nil),
            @"iconListHookSeen": @NO
        });

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        HSFPreferencesChangedCallback, HSFPreferencesChanged,
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        HSFTestCallback, HSFTestNotification,
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
