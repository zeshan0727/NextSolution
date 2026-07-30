#import <UIKit/UIKit.h>

static BOOL NCPHasInitialState = NO;
static BOOL NCPLastPowerConnected = NO;

static BOOL NCPIsPowerConnected(UIDeviceBatteryState state) {
    return state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull;
}

static void NCPHandleBatteryStateChange(NSNotification *notification) {
    UIDeviceBatteryState state = UIDevice.currentDevice.batteryState;
    if (state == UIDeviceBatteryStateUnknown) {
        return;
    }

    BOOL powerConnected = NCPIsPowerConnected(state);

    if (!NCPHasInitialState) {
        NCPLastPowerConnected = powerConnected;
        NCPHasInitialState = YES;
        return;
    }

    if (powerConnected == NCPLastPowerConnected) {
        return;
    }

    NCPLastPowerConnected = powerConnected;

    // The tweak intentionally responds only to a real transition into a
    // charging/full state. Disconnecting power produces no extra feedback.
    if (!powerConnected) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
        [generator prepare];
        [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
    });
}

%ctor {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIDevice *device = UIDevice.currentDevice;
            device.batteryMonitoringEnabled = YES;

            [[NSNotificationCenter defaultCenter]
                addObserverForName:UIDeviceBatteryStateDidChangeNotification
                object:device
                queue:[NSOperationQueue mainQueue]
                usingBlock:NCPHandleBatteryStateChange];

            // Establish the baseline after battery monitoring has had time to
            // populate. This prevents a false haptic immediately after respring.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                NCPHandleBatteryStateChange(nil);
            });
        });
    }
}
