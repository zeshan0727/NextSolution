#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "Decision.h"

static CFStringRef const LBHAPreferenceDomain = CFSTR("com.nextsolution.lowbatteryhapticalert");
static CFStringRef const LBHAPreferencesChanged = CFSTR("com.nextsolution.lowbatteryhapticalert.preferences.changed");

static BOOL LBHAEnabled = YES;
static NSInteger LBHAThreshold = 15;
static BOOL LBHAHasPreviousLevel = NO;
static NSInteger LBHAPreviousPercent = -1;

static BOOL LBHAIsSpringBoard(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] ||
           [NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"];
}

static NSInteger LBHACurrentPercent(void) {
    float level = UIDevice.currentDevice.batteryLevel;
    if (level < 0.0f) return -1;
    return (NSInteger)(level * 100.0f + 0.5f);
}

static void LBHAReloadPreferences(void) {
    CFPreferencesAppSynchronize(LBHAPreferenceDomain);

    id enabledValue = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), LBHAPreferenceDomain));
    id thresholdValue = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("threshold"), LBHAPreferenceDomain));

    LBHAEnabled = enabledValue ? [enabledValue boolValue] : YES;
    LBHAThreshold = LBHAClampThreshold(thresholdValue ? [thresholdValue intValue] : 15);
}

static void LBHAPlayWarningHaptic(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UINotificationFeedbackGenerator *generator = [UINotificationFeedbackGenerator new];
        [generator prepare];
        [generator notificationOccurred:UINotificationFeedbackTypeWarning];
    });
}

static void LBHAEvaluateBatteryChange(void) {
    NSInteger currentPercent = LBHACurrentPercent();
    UIDeviceBatteryState deviceState = UIDevice.currentDevice.batteryState;

    LBHAAlertDecision decision = LBHADecisionForChange(LBHAEnabled,
                                                       LBHAHasPreviousLevel,
                                                       (int)LBHAPreviousPercent,
                                                       (int)currentPercent,
                                                       (LBHABatteryState)deviceState,
                                                       (int)LBHAThreshold);

    if (currentPercent >= 0) {
        LBHAPreviousPercent = currentPercent;
        LBHAHasPreviousLevel = YES;
    }

    if (decision == LBHAAlertThresholdCrossed) {
        LBHAPlayWarningHaptic();
    }
}

static void LBHAPreferencesChangedCallback(CFNotificationCenterRef center,
                                           void *observer,
                                           CFStringRef name,
                                           const void *object,
                                           CFDictionaryRef userInfo) {
    LBHAReloadPreferences();
}

%ctor {
    @autoreleasepool {
        if (!LBHAIsSpringBoard()) return;

        LBHAReloadPreferences();
        UIDevice.currentDevice.batteryMonitoringEnabled = YES;
        LBHAPreviousPercent = LBHACurrentPercent();
        LBHAHasPreviousLevel = LBHAPreviousPercent >= 0;

        [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceBatteryLevelDidChangeNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *notification) {
            LBHAEvaluateBatteryChange();
        }];

        [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceBatteryStateDidChangeNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *notification) {
            NSInteger currentPercent = LBHACurrentPercent();
            if (currentPercent >= 0) {
                LBHAPreviousPercent = currentPercent;
                LBHAHasPreviousLevel = YES;
            }
        }];

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        LBHAPreferencesChangedCallback,
                                        LBHAPreferencesChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
