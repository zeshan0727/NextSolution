#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

static CFStringRef const SRHPreferenceDomain = CFSTR("com.nextsolution.screenrecordinghapticalert");
static CFStringRef const SRHPreferencesChanged = CFSTR("com.nextsolution.screenrecordinghapticalert.preferences.changed");
static BOOL SRHEnabled = YES;
static BOOL SRHHasInitialState = NO;
static BOOL SRHLastCaptured = NO;

static BOOL SRHIsSpringBoard(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] ||
           [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"];
}

static BOOL SRHShouldPlay(BOOL enabled, BOOL hasInitialState, BOOL previous, BOOL current) {
    return enabled && hasInitialState && previous != current;
}

static void SRHReloadPreferences(void) {
    CFPreferencesAppSynchronize(SRHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), SRHPreferenceDomain));
    SRHEnabled = value ? [value boolValue] : YES;
}

static void SRHHandleCaptureState(UIScreen *screen) {
    if (!screen) screen = UIScreen.mainScreen;
    BOOL captured = screen.isCaptured;
    BOOL shouldPlay = SRHShouldPlay(SRHEnabled, SRHHasInitialState, SRHLastCaptured, captured);
    SRHLastCaptured = captured;
    SRHHasInitialState = YES;
    if (!shouldPlay) return;

    // Distinct system haptics: success-like on start, warning-like on stop.
    AudioServicesPlaySystemSound(captured ? 1520 : 1521);
}

static void SRHCaptureChanged(NSNotification *notification) {
    UIScreen *screen = [notification.object isKindOfClass:UIScreen.class] ? notification.object : UIScreen.mainScreen;
    dispatch_async(dispatch_get_main_queue(), ^{
        SRHHandleCaptureState(screen);
    });
}

static void SRHPreferencesChangedCallback(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo) {
    SRHReloadPreferences();
}

%ctor {
    @autoreleasepool {
        if (!SRHIsSpringBoard()) return;
        SRHReloadPreferences();
        SRHHandleCaptureState(UIScreen.mainScreen); // Baseline only; never haptics at load.
        [NSNotificationCenter.defaultCenter addObserverForName:UIScreenCapturedDidChangeNotification
                                                       object:nil
                                                        queue:NSOperationQueue.mainQueue
                                                   usingBlock:SRHCaptureChanged];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        SRHPreferencesChangedCallback,
                                        SRHPreferencesChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
