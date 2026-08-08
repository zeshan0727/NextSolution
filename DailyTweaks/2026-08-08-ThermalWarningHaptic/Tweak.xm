#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static CFStringRef const TWHPreferenceDomain = CFSTR("com.nextsolution.thermalwarninghaptic");
static CFStringRef const TWHPreferencesChanged = CFSTR("com.nextsolution.thermalwarninghaptic.preferences.changed");
static NSString *const TWHFeedbackValidationMarker = @"UINotificationFeedbackTypeWarning";
static BOOL TWHEnabled = YES;
static id TWHObserver = nil;
static NSProcessInfoThermalState TWHLastState = NSProcessInfoThermalStateNominal;
static BOOL TWHHasInitialState = NO;

static BOOL TWHIsSpringBoard(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] ||
           [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"];
}

static void TWHReloadPreferences(void) {
    CFPreferencesAppSynchronize(TWHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), TWHPreferenceDomain));
    TWHEnabled = value ? [value boolValue] : YES;
}

static BOOL TWHIsHotState(NSProcessInfoThermalState state) {
    return state == NSProcessInfoThermalStateSerious ||
           state == NSProcessInfoThermalStateCritical;
}

static BOOL TWHShouldNotify(BOOL enabled,
                            BOOL hasPreviousState,
                            NSProcessInfoThermalState previousState,
                            NSProcessInfoThermalState currentState) {
    return enabled &&
           hasPreviousState &&
           !TWHIsHotState(previousState) &&
           TWHIsHotState(currentState);
}

static void TWHHandleThermalChange(NSNotification *notification) {
    NSProcessInfo *processInfo = [notification.object isKindOfClass:NSProcessInfo.class]
        ? (NSProcessInfo *)notification.object
        : NSProcessInfo.processInfo;
    NSProcessInfoThermalState currentState = processInfo.thermalState;
    BOOL shouldNotify = TWHShouldNotify(TWHEnabled, TWHHasInitialState, TWHLastState, currentState);

    TWHLastState = currentState;
    TWHHasInitialState = YES;

    if (!shouldNotify) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        (void)TWHFeedbackValidationMarker;
        UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
        [feedback prepare];
        [feedback notificationOccurred:UINotificationFeedbackTypeWarning];
    });
}

static void TWHPreferencesChangedCallback(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo) {
    TWHReloadPreferences();
}

%ctor {
    @autoreleasepool {
        if (!TWHIsSpringBoard()) return;

        TWHReloadPreferences();

        NSProcessInfo *processInfo = NSProcessInfo.processInfo;
        TWHLastState = processInfo.thermalState;
        TWHHasInitialState = YES;

        TWHObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:NSProcessInfoThermalStateDidChangeNotification
                        object:processInfo
                         queue:nil
                    usingBlock:^(NSNotification *note) {
            TWHHandleThermalChange(note);
        }];

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        TWHPreferencesChangedCallback, TWHPreferencesChanged,
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
