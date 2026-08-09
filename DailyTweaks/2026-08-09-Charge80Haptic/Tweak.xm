#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <math.h>

static CFStringRef const C80PreferenceDomain = CFSTR("com.nextsolution.charge80haptic");
static CFStringRef const C80PreferencesChanged = CFSTR("com.nextsolution.charge80haptic.preferences.changed");
static NSString *const C80FeedbackValidationMarker = @"UINotificationFeedbackTypeSuccess";
static BOOL C80Enabled = YES;
static NSArray *C80Observers = nil;
static NSInteger C80LastPercent = -1;
static BOOL C80HasInitialState = NO;
static const NSInteger C80ThresholdPercent = 80;

static BOOL C80IsSpringBoard(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] ||
           [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"];
}

static void C80ReloadPreferences(void) {
    CFPreferencesAppSynchronize(C80PreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), C80PreferenceDomain));
    C80Enabled = value ? [value boolValue] : YES;
}

static BOOL C80IsPowered(UIDeviceBatteryState state) {
    return state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull;
}

static BOOL C80ShouldNotify(BOOL enabled,
                            BOOL hasPreviousState,
                            NSInteger previousPercent,
                            NSInteger currentPercent,
                            UIDeviceBatteryState currentState) {
    return enabled &&
           hasPreviousState &&
           C80IsPowered(currentState) &&
           previousPercent >= 0 &&
           previousPercent < C80ThresholdPercent &&
           currentPercent >= C80ThresholdPercent;
}

static NSInteger C80CurrentPercent(UIDevice *device) {
    float level = device.batteryLevel;
    if (level < 0.0f) return -1;
    NSInteger percent = (NSInteger)lroundf(level * 100.0f);
    return MAX(0, MIN(100, percent));
}

static void C80HandleBatteryChange(NSNotification *notification) {
    UIDevice *device = UIDevice.currentDevice;
    NSInteger currentPercent = C80CurrentPercent(device);
    UIDeviceBatteryState currentState = device.batteryState;
    BOOL shouldNotify = C80ShouldNotify(C80Enabled, C80HasInitialState, C80LastPercent, currentPercent, currentState);

    C80LastPercent = currentPercent;
    C80HasInitialState = currentPercent >= 0;

    if (!shouldNotify) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        (void)C80FeedbackValidationMarker;
        UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
        [feedback prepare];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
    });
}

static void C80PreferencesChangedCallback(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo) {
    C80ReloadPreferences();
}

%ctor {
    @autoreleasepool {
        if (!C80IsSpringBoard()) return;

        C80ReloadPreferences();

        UIDevice *device = UIDevice.currentDevice;
        device.batteryMonitoringEnabled = YES;
        C80LastPercent = C80CurrentPercent(device);
        C80HasInitialState = C80LastPercent >= 0;

        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        id levelObserver = [center addObserverForName:UIDeviceBatteryLevelDidChangeNotification
                                               object:device
                                                queue:nil
                                           usingBlock:^(NSNotification *note) {
            C80HandleBatteryChange(note);
        }];
        id stateObserver = [center addObserverForName:UIDeviceBatteryStateDidChangeNotification
                                               object:device
                                                queue:nil
                                           usingBlock:^(NSNotification *note) {
            C80HandleBatteryChange(note);
        }];
        C80Observers = @[levelObserver, stateObserver];

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        C80PreferencesChangedCallback, C80PreferencesChanged,
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
