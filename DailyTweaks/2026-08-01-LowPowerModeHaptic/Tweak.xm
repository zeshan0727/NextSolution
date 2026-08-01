#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "Decision.h"

static CFStringRef const LPMHPreferenceDomain = CFSTR("com.nextsolution.lowpowermodehaptic");
static CFStringRef const LPMHPreferencesChanged = CFSTR("com.nextsolution.lowpowermodehaptic.preferences.changed");

static BOOL LPMHEnabled = YES;
static BOOL LPMHHasPreviousState = NO;
static BOOL LPMHPreviousState = NO;

static BOOL LPMHIsSpringBoard(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] ||
           [NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"];
}

static void LPMHReloadPreferences(void) {
    CFPreferencesAppSynchronize(LPMHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), LPMHPreferenceDomain));
    LPMHEnabled = value ? [value boolValue] : YES;
}

static void LPMHPlayDecision(LPMHHapticDecision decision) {
    if (decision == LPMHHapticNone) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UINotificationFeedbackGenerator *generator = [UINotificationFeedbackGenerator new];
        [generator prepare];
        UINotificationFeedbackType type = decision == LPMHHapticEnabled
            ? UINotificationFeedbackTypeSuccess
            : UINotificationFeedbackTypeWarning;
        [generator notificationOccurred:type];
    });
}

static void LPMHHandlePowerStateChange(NSNotification *notification) {
    BOOL currentState = NSProcessInfo.processInfo.lowPowerModeEnabled;
    LPMHHapticDecision decision = LPMHDecisionForChange(LPMHEnabled,
                                                       LPMHHasPreviousState,
                                                       LPMHPreviousState,
                                                       currentState);
    LPMHPreviousState = currentState;
    LPMHHasPreviousState = YES;
    LPMHPlayDecision(decision);
}

static void LPMHPreferencesChangedCallback(CFNotificationCenterRef center,
                                           void *observer,
                                           CFStringRef name,
                                           const void *object,
                                           CFDictionaryRef userInfo) {
    LPMHReloadPreferences();
}

%ctor {
    @autoreleasepool {
        if (!LPMHIsSpringBoard()) return;

        LPMHReloadPreferences();
        LPMHPreviousState = NSProcessInfo.processInfo.lowPowerModeEnabled;
        LPMHHasPreviousState = YES;

        [NSNotificationCenter.defaultCenter addObserverForName:NSProcessInfoPowerStateDidChangeNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *notification) {
            LPMHHandlePowerStateChange(notification);
        }];

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        LPMHPreferencesChangedCallback,
                                        LPMHPreferencesChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
