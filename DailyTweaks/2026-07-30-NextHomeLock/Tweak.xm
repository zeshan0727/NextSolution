#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static NSString *const NHLVersion = @"1.0.4";
static CFStringRef const NHLPreferenceDomain = CFSTR("com.nextsolution.nexthomelock");
static CFStringRef const NHLRuntimeDomain = CFSTR("com.nextsolution.nexthomelock.runtime");
static CFStringRef const NHLPreferencesChanged = CFSTR("com.nextsolution.nexthomelock.preferences.changed");
static CFStringRef const NHLTestLockNotification = CFSTR("com.nextsolution.nexthomelock.test-lock");

static dispatch_queue_t NHLStatusQueue;
static BOOL NHLEnabled = YES;

static BOOL NHLIsSpringBoardProcess(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] ||
           [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"];
}

static void NHLWriteStatus(NSDictionary<NSString *, id> *updates) {
    if (!updates.count || !NHLStatusQueue) return;

    dispatch_async(NHLStatusQueue, ^{
        [updates enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                     (__bridge CFPropertyListRef)value,
                                     NHLRuntimeDomain);
        }];
        CFPreferencesSetAppValue(CFSTR("updatedAt"),
                                 (__bridge CFNumberRef)@([NSDate date].timeIntervalSince1970),
                                 NHLRuntimeDomain);
        CFPreferencesAppSynchronize(NHLRuntimeDomain);
    });
}

static BOOL NHLReadEnabled(void) {
    CFPreferencesAppSynchronize(NHLPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), NHLPreferenceDomain));
    return value ? [value boolValue] : YES;
}

static void NHLReloadPreferences(void) {
    NHLEnabled = NHLReadEnabled();
    NHLWriteStatus(@{
        @"enabled": @(NHLEnabled),
        @"preferencesReloadedAt": @([NSDate date].timeIntervalSince1970)
    });
}

static NSString *NHLLockDevice(void) {
    Class springBoardClass = objc_getClass("SpringBoard");
    SEL sharedApplicationSelector = NSSelectorFromString(@"sharedApplication");
    id springBoard = nil;

    if (springBoardClass && [springBoardClass respondsToSelector:sharedApplicationSelector]) {
        springBoard = ((id (*)(id, SEL))objc_msgSend)(springBoardClass, sharedApplicationSelector);
    }

    // This is the same lock route used by the established open-source
    // Lock Screen Without Button tweak. It simulates Apple's lock-button action.
    SEL simulatedPressSelector = NSSelectorFromString(@"_simulateLockButtonPress");
    if (springBoard && [springBoard respondsToSelector:simulatedPressSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(springBoard, simulatedPressSelector);
        return @"SpringBoard _simulateLockButtonPress";
    }

    SEL pluginUserAgentSelector = NSSelectorFromString(@"pluginUserAgent");
    SEL lockAndDimSelector = NSSelectorFromString(@"lockAndDimDevice");
    if (springBoard && [springBoard respondsToSelector:pluginUserAgentSelector]) {
        id userAgent = ((id (*)(id, SEL))objc_msgSend)(springBoard, pluginUserAgentSelector);
        if (userAgent && [userAgent respondsToSelector:lockAndDimSelector]) {
            ((void (*)(id, SEL))objc_msgSend)(userAgent, lockAndDimSelector);
            return @"SpringBoard pluginUserAgent lockAndDimDevice";
        }
    }

    Class managerClass = objc_getClass("SBLockScreenManager");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    id manager = nil;
    if (managerClass && [managerClass respondsToSelector:sharedSelector]) {
        manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, sharedSelector);
    }

    SEL modernLockSelector = NSSelectorFromString(@"lockUIFromSource:withOptions:");
    if (manager && [manager respondsToSelector:modernLockSelector]) {
        ((void (*)(id, SEL, NSInteger, id))objc_msgSend)(manager, modernLockSelector, 1, nil);
        return @"SBLockScreenManager lockUIFromSource:withOptions:";
    }

    SEL legacyLockSelector = NSSelectorFromString(@"lockUIFromSource:");
    if (manager && [manager respondsToSelector:legacyLockSelector]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(manager, legacyLockSelector, 1);
        return @"SBLockScreenManager lockUIFromSource:";
    }

    typedef void (*SBSLockDeviceFunction)(void);
    SBSLockDeviceFunction lockFunction = (SBSLockDeviceFunction)dlsym(RTLD_DEFAULT, "SBSLockDevice");
    if (!lockFunction) {
        void *framework = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
        if (framework) lockFunction = (SBSLockDeviceFunction)dlsym(framework, "SBSLockDevice");
    }
    if (lockFunction) {
        lockFunction();
        return @"SBSLockDevice";
    }

    return @"No compatible lock route found";
}

static void NHLRequestLock(NSString *source) {
    NHLWriteStatus(@{
        @"lastLockSource": source ?: @"Unknown",
        @"lastLockRequestedAt": @([NSDate date].timeIntervalSince1970),
        @"lastLockRoute": @"Resolving"
    });

    NSString *route = NHLLockDevice();
    NHLWriteStatus(@{
        @"lastLockSource": source ?: @"Unknown",
        @"lastLockRoute": route ?: @"Unknown",
        @"lastLockCompletedAt": @([NSDate date].timeIntervalSince1970)
    });
}

static void NHLPreferencesChangedCallback(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo) {
    NHLReloadPreferences();
}

static void NHLTestLockCallback(CFNotificationCenterRef center,
                                void *observer,
                                CFStringRef name,
                                const void *object,
                                CFDictionaryRef userInfo) {
    NHLWriteStatus(@{
        @"testCommandReceived": @YES,
        @"testCommandReceivedAt": @([NSDate date].timeIntervalSince1970)
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        NHLRequestLock(@"Settings test command");
    });
}

// Proven Home Screen path: SBIconListView receives background touches directly.
// This intentionally replaces the unsuccessful SBRootFolderView recognizer approach.
%hook SBIconListView

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    NSUInteger tapCount = touch ? touch.tapCount : 0;
    NSString *touchClass = touch.view ? NSStringFromClass(touch.view.class) : @"(nil)";

    NHLWriteStatus(@{
        @"iconListHookSeen": @YES,
        @"iconListHookSeenAt": @([NSDate date].timeIntervalSince1970),
        @"lastTouchClass": touchClass,
        @"lastTapCount": @(tapCount),
        @"lastTapAt": @([NSDate date].timeIntervalSince1970),
        @"lastTouchAccepted": @(NHLEnabled && tapCount == 2)
    });

    if (NHLEnabled && tapCount == 2) {
        NHLRequestLock(@"SBIconListView double-tap");
        return;
    }

    %orig;
}

%end

%ctor {
    @autoreleasepool {
        if (!NHLIsSpringBoardProcess()) return;

        NHLStatusQueue = dispatch_queue_create("com.nextsolution.nexthomelock.runtime", DISPATCH_QUEUE_SERIAL);
        NHLReloadPreferences();

        Class iconListClass = objc_getClass("SBIconListView");
        Class springBoardClass = objc_getClass("SpringBoard");
        id springBoard = nil;
        if (springBoardClass && [springBoardClass respondsToSelector:@selector(sharedApplication)]) {
            springBoard = ((id (*)(id, SEL))objc_msgSend)(springBoardClass, @selector(sharedApplication));
        }

        NHLWriteStatus(@{
            @"tweakLoaded": @YES,
            @"loadedVersion": NHLVersion,
            @"loadedAt": @([NSDate date].timeIntervalSince1970),
            @"springBoardPID": @([NSProcessInfo processInfo].processIdentifier),
            @"processName": [NSProcessInfo processInfo].processName ?: @"Unknown",
            @"bundleIdentifier": NSBundle.mainBundle.bundleIdentifier ?: @"Unknown",
            @"iconListClassPresent": @(iconListClass != Nil),
            @"iconListHookSeen": @NO,
            @"simulateLockSelectorPresent": @(springBoard && [springBoard respondsToSelector:NSSelectorFromString(@"_simulateLockButtonPress")]),
            @"testCommandReceived": @NO,
            @"implementation": @"SBIconListView touchesEnded"
        });

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        NHLPreferencesChangedCallback,
                                        NHLPreferencesChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        NHLTestLockCallback,
                                        NHLTestLockNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
