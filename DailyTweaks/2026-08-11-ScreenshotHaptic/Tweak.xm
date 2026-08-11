#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static CFStringRef const SSHPreferenceDomain = CFSTR("com.nextsolution.screenshothaptic");
static CFStringRef const SSHPreferencesChanged = CFSTR("com.nextsolution.screenshothaptic.preferences.changed");
static BOOL SSHEnabled = YES;
static id SSHScreenshotObserver = nil;

static BOOL SSHIsSpringBoard(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] ||
           [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"];
}

static void SSHReloadPreferences(void) {
    CFPreferencesAppSynchronize(SSHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), SSHPreferenceDomain));
    SSHEnabled = value ? [value boolValue] : YES;
}

static BOOL SSHShouldNotify(BOOL enabled, BOOL receivedScreenshotEvent) {
    return enabled && receivedScreenshotEvent;
}

static void SSHHandleScreenshot(void) {
    if (!SSHShouldNotify(SSHEnabled, YES)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
        [feedback prepare];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
    });
}

static void SSHPreferencesChangedCallback(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo) {
    SSHReloadPreferences();
}

%ctor {
    @autoreleasepool {
        if (!SSHIsSpringBoard()) return;
        SSHReloadPreferences();
        SSHScreenshotObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationUserDidTakeScreenshotNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *note) {
                SSHHandleScreenshot();
            }];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        SSHPreferencesChangedCallback, SSHPreferencesChanged,
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
