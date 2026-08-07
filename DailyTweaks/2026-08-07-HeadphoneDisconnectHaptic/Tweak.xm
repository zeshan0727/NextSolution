#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

static CFStringRef const HDHPreferenceDomain = CFSTR("com.nextsolution.headphonedisconnecthaptic");
static CFStringRef const HDHPreferencesChanged = CFSTR("com.nextsolution.headphonedisconnecthaptic.preferences.changed");
static NSString *const HDHFeedbackValidationMarker = @"UINotificationFeedbackTypeWarning";
static BOOL HDHEnabled = YES;
static id HDHRouteObserver = nil;

static BOOL HDHIsSpringBoard(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] ||
           [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"];
}

static void HDHReloadPreferences(void) {
    CFPreferencesAppSynchronize(HDHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), HDHPreferenceDomain));
    HDHEnabled = value ? [value boolValue] : YES;
}

static BOOL HDHIsPersonalAudioPort(NSString *portType) {
    if (!portType.length) return NO;
    return [portType isEqualToString:AVAudioSessionPortHeadphones] ||
           [portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
           [portType isEqualToString:AVAudioSessionPortBluetoothHFP] ||
           [portType isEqualToString:AVAudioSessionPortBluetoothLE];
}

static BOOL HDHRouteHasPersonalAudio(AVAudioSessionRouteDescription *route) {
    for (AVAudioSessionPortDescription *output in route.outputs) {
        if (HDHIsPersonalAudioPort(output.portType)) return YES;
    }
    return NO;
}

static BOOL HDHShouldNotify(BOOL enabled,
                            AVAudioSessionRouteChangeReason reason,
                            BOOL previousHadPersonalAudio,
                            BOOL currentHasPersonalAudio) {
    return enabled &&
           reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable &&
           previousHadPersonalAudio &&
           !currentHasPersonalAudio;
}

static void HDHHandleRouteChange(NSNotification *notification) {
    NSNumber *reasonValue = notification.userInfo[AVAudioSessionRouteChangeReasonKey];
    AVAudioSessionRouteDescription *previousRoute = notification.userInfo[AVAudioSessionRouteChangePreviousRouteKey];
    if (![reasonValue isKindOfClass:NSNumber.class] || !previousRoute) return;

    AVAudioSessionRouteChangeReason reason = (AVAudioSessionRouteChangeReason)reasonValue.unsignedIntegerValue;
    BOOL previousHadPersonalAudio = HDHRouteHasPersonalAudio(previousRoute);
    BOOL currentHasPersonalAudio = HDHRouteHasPersonalAudio(AVAudioSession.sharedInstance.currentRoute);

    if (!HDHShouldNotify(HDHEnabled, reason, previousHadPersonalAudio, currentHasPersonalAudio)) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        (void)HDHFeedbackValidationMarker;
        UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
        [feedback prepare];
        [feedback notificationOccurred:UINotificationFeedbackTypeWarning];
    });
}

static void HDHPreferencesChangedCallback(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object,
                                          CFDictionaryRef userInfo) {
    HDHReloadPreferences();
}

%ctor {
    @autoreleasepool {
        if (!HDHIsSpringBoard()) return;

        HDHReloadPreferences();
        AVAudioSession *session = AVAudioSession.sharedInstance;
        (void)session.currentRoute;

        HDHRouteObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:AVAudioSessionRouteChangeNotification
                        object:session
                         queue:nil
                    usingBlock:^(NSNotification *note) {
            HDHHandleRouteChange(note);
        }];

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        HDHPreferencesChangedCallback, HDHPreferencesChanged,
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
