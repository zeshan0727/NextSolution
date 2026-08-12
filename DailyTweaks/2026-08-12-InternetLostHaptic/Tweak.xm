#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Network/Network.h>

static CFStringRef const ILHPreferenceDomain = CFSTR("com.nextsolution.internetlosthaptic");
static CFStringRef const ILHPreferencesChanged = CFSTR("com.nextsolution.internetlosthaptic.preferences.changed");
static BOOL ILHEnabled = YES;
static BOOL ILHHasPreviousState = NO;
static nw_path_status_t ILHPreviousStatus = nw_path_status_invalid;
static nw_path_monitor_t ILHMonitor = nil;
static dispatch_queue_t ILHMonitorQueue = nil;

static BOOL ILHIsSpringBoard(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] ||
           [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"];
}

static void ILHReloadPreferences(void) {
    CFPreferencesAppSynchronize(ILHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), ILHPreferenceDomain));
    ILHEnabled = value ? [value boolValue] : YES;
}

static BOOL ILHShouldNotify(BOOL enabled, BOOL hasPreviousState,
                            nw_path_status_t previousStatus,
                            nw_path_status_t currentStatus) {
    return enabled && hasPreviousState &&
           previousStatus == nw_path_status_satisfied &&
           currentStatus == nw_path_status_unsatisfied;
}

static void ILHHandlePath(nw_path_t path) {
    if (!path) return;
    nw_path_status_t currentStatus = nw_path_get_status(path);
    BOOL shouldNotify = ILHShouldNotify(ILHEnabled, ILHHasPreviousState,
                                       ILHPreviousStatus, currentStatus);

    ILHPreviousStatus = currentStatus;
    ILHHasPreviousState = YES;

    if (!shouldNotify) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
        [feedback prepare];
        [feedback notificationOccurred:UINotificationFeedbackTypeWarning];
    });
}

static void ILHPreferencesChangedCallback(CFNotificationCenterRef center,
                                           void *observer,
                                           CFStringRef name,
                                           const void *object,
                                           CFDictionaryRef userInfo) {
    ILHReloadPreferences();
}

%ctor {
    @autoreleasepool {
        if (!ILHIsSpringBoard()) return;
        ILHReloadPreferences();
        ILHMonitorQueue = dispatch_queue_create("com.nextsolution.internetlosthaptic.monitor", DISPATCH_QUEUE_SERIAL);
        ILHMonitor = nw_path_monitor_create();
        if (ILHMonitor) {
            nw_path_monitor_set_update_handler(ILHMonitor, ^(nw_path_t path) {
                ILHHandlePath(path);
            });
            nw_path_monitor_set_queue(ILHMonitor, ILHMonitorQueue);
            nw_path_monitor_start(ILHMonitor);
        }
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        ILHPreferencesChangedCallback, ILHPreferencesChanged,
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
