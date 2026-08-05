#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static CFStringRef const FCHPreferenceDomain = CFSTR("com.nextsolution.fullchargehaptic");
static CFStringRef const FCHPreferencesChanged = CFSTR("com.nextsolution.fullchargehaptic.preferences.changed");
static BOOL FCHEnabled = YES;
static BOOL FCHInitialized = NO;
static BOOL FCHWasFull = NO;
static id FCHLevelObserver = nil;
static id FCHStateObserver = nil;

static BOOL FCHIsSpringBoard(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] ||
           [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"];
}

static void FCHReloadPreferences(void) {
    CFPreferencesAppSynchronize(FCHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), FCHPreferenceDomain));
    FCHEnabled = value ? [value boolValue] : YES;
}

static BOOL FCHIsChargingState(UIDeviceBatteryState state) {
    return state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull;
}

static BOOL FCHIsFull(float level, UIDeviceBatteryState state) {
    return level >= 0.995f && FCHIsChargingState(state);
}

static BOOL FCHShouldNotify(BOOL enabled, BOOL initialized, BOOL wasFull, BOOL isFull) {
    return enabled && initialized && !wasFull && isFull;
}

static void FCHHandleBatteryChange(void) {
    UIDevice *device = UIDevice.currentDevice;
    float level = device.batteryLevel;
    UIDeviceBatteryState state = device.batteryState;
    if (level < 0.0f || state == UIDeviceBatteryStateUnknown) return;

    BOOL isFull = FCHIsFull(level, state);
    BOOL shouldNotify = FCHShouldNotify(FCHEnabled, FCHInitialized, FCHWasFull, isFull);

    if (!FCHInitialized) {
        FCHInitialized = YES;
        FCHWasFull = isFull;
        return;
    }

    FCHWasFull = isFull;
    if (!shouldNotify) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
        [feedback prepare];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
    });
}

static void FCHPreferencesChangedCallback(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object,
                                          CFDictionaryRef userInfo) {
    FCHReloadPreferences();
}

%ctor {
    @autoreleasepool {
        if (!FCHIsSpringBoard()) return;

        FCHReloadPreferences();
        UIDevice.currentDevice.batteryMonitoringEnabled = YES;

        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        NSOperationQueue *queue = NSOperationQueue.mainQueue;
        FCHLevelObserver = [center addObserverForName:UIDeviceBatteryLevelDidChangeNotification
                                               object:nil queue:queue
                                           usingBlock:^(__unused NSNotification *note) {
            FCHHandleBatteryChange();
        }];
        FCHStateObserver = [center addObserverForName:UIDeviceBatteryStateDidChangeNotification
                                               object:nil queue:queue
                                           usingBlock:^(__unused NSNotification *note) {
            FCHHandleBatteryChange();
        }];

        FCHHandleBatteryChange();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        FCHPreferencesChangedCallback, FCHPreferencesChanged,
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
