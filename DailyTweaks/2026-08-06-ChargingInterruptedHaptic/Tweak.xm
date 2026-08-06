#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static CFStringRef const CIHPreferenceDomain = CFSTR("com.nextsolution.charginginterruptedhaptic");
static CFStringRef const CIHPreferencesChanged = CFSTR("com.nextsolution.charginginterruptedhaptic.preferences.changed");
static NSString *const CIHFeedbackValidationMarker = @"UINotificationFeedbackTypeWarning";
static BOOL CIHEnabled = YES;
static BOOL CIHInitialized = NO;
static UIDeviceBatteryState CIHPreviousState = UIDeviceBatteryStateUnknown;
static id CIHStateObserver = nil;

static BOOL CIHIsSpringBoard(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] ||
           [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"];
}

static void CIHReloadPreferences(void) {
    CFPreferencesAppSynchronize(CIHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), CIHPreferenceDomain));
    CIHEnabled = value ? [value boolValue] : YES;
}

static BOOL CIHIsPoweredState(UIDeviceBatteryState state) {
    return state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull;
}

static BOOL CIHShouldNotify(BOOL enabled, BOOL initialized,
                            UIDeviceBatteryState previousState,
                            UIDeviceBatteryState currentState) {
    return enabled && initialized && CIHIsPoweredState(previousState) &&
           currentState == UIDeviceBatteryStateUnplugged;
}

static void CIHHandleBatteryStateChange(void) {
    UIDeviceBatteryState currentState = UIDevice.currentDevice.batteryState;
    if (currentState == UIDeviceBatteryStateUnknown) return;

    BOOL shouldNotify = CIHShouldNotify(CIHEnabled, CIHInitialized,
                                       CIHPreviousState, currentState);

    if (!CIHInitialized) {
        CIHInitialized = YES;
        CIHPreviousState = currentState;
        return;
    }

    CIHPreviousState = currentState;
    if (!shouldNotify) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        (void)CIHFeedbackValidationMarker;
        UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
        [feedback prepare];
        [feedback notificationOccurred:UINotificationFeedbackTypeWarning];
    });
}

static void CIHPreferencesChangedCallback(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object,
                                          CFDictionaryRef userInfo) {
    CIHReloadPreferences();
}

%ctor {
    @autoreleasepool {
        if (!CIHIsSpringBoard()) return;

        CIHReloadPreferences();
        UIDevice.currentDevice.batteryMonitoringEnabled = YES;

        CIHStateObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:UIDeviceBatteryStateDidChangeNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *note) {
            CIHHandleBatteryStateChange();
        }];

        CIHHandleBatteryStateChange();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        CIHPreferencesChangedCallback, CIHPreferencesChanged,
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
