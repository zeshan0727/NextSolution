#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Network/Network.h>

static CFStringRef const WDHPreferenceDomain = CFSTR("com.nextsolution.wifidrophaptic");
static CFStringRef const WDHPreferencesChanged = CFSTR("com.nextsolution.wifidrophaptic.preferences.changed");
static BOOL WDHEnabled = YES;
static BOOL WDHHasPreviousState = NO;
static BOOL WDHPreviousWiFi = NO;
static nw_path_monitor_t WDHMonitor = nil;
static dispatch_queue_t WDHMonitorQueue = nil;

static BOOL WDHIsSpringBoard(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] ||
           [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"];
}

static void WDHReloadPreferences(void) {
    CFPreferencesAppSynchronize(WDHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), WDHPreferenceDomain));
    WDHEnabled = value ? [value boolValue] : YES;
}

static BOOL WDHShouldNotify(BOOL enabled, BOOL hasPreviousState, BOOL previousWiFi, BOOL currentWiFi) {
    return enabled && hasPreviousState && previousWiFi && !currentWiFi;
}

static BOOL WDHPathUsesWiFi(nw_path_t path) {
    if (!path) return NO;
    return nw_path_get_status(path) == nw_path_status_satisfied &&
           nw_path_uses_interface_type(path, nw_interface_type_wifi);
}

static void WDHHandlePath(nw_path_t path) {
    BOOL currentWiFi = WDHPathUsesWiFi(path);
    BOOL shouldNotify = WDHShouldNotify(WDHEnabled, WDHHasPreviousState, WDHPreviousWiFi, currentWiFi);

    WDHPreviousWiFi = currentWiFi;
    WDHHasPreviousState = YES;

    if (!shouldNotify) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
        [feedback prepare];
        [feedback notificationOccurred:UINotificationFeedbackTypeWarning];
    });
}

static void WDHPreferencesChangedCallback(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo) {
    WDHReloadPreferences();
}

%ctor {
    @autoreleasepool {
        if (!WDHIsSpringBoard()) return;

        WDHReloadPreferences();

        WDHMonitorQueue = dispatch_queue_create("com.nextsolution.wifidrophaptic.monitor", DISPATCH_QUEUE_SERIAL);
        WDHMonitor = nw_path_monitor_create();
        if (WDHMonitor) {
            nw_path_monitor_set_update_handler(WDHMonitor, ^(nw_path_t path) {
                WDHHandlePath(path);
            });
            nw_path_monitor_set_queue(WDHMonitor, WDHMonitorQueue);
            nw_path_monitor_start(WDHMonitor);
        }

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        WDHPreferencesChangedCallback, WDHPreferencesChanged,
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
