#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "Tests/BrightnessDecision.h"

static CFStringRef const BEHDomain = CFSTR("com.nextsolution.brightnessedgehaptic");
static CFStringRef const BEHChanged = CFSTR("com.nextsolution.brightnessedgehaptic.preferences.changed");
static BOOL BEHEnabled = YES;
static BEHEdgeState BEHLastState = BEHEdgeStateUnknown;
static id BEHObserver = nil;

static BOOL BEHIsSpringBoard(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] || [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"];
}

static void BEHReload(void) {
    CFPreferencesAppSynchronize(BEHDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), BEHDomain));
    BEHEnabled = value ? [value boolValue] : YES;
}

static void BEHPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    BEHReload();
}

static void BEHHandleBrightness(CGFloat brightness) {
    BEHEdgeState next = BEHClassifyBrightness(brightness);
    BEHHapticDecision decision = BEHDecision(BEHEnabled, BEHLastState, next);
    BEHLastState = next;
    if (decision == BEHHapticDecisionNone) return;

    UINotificationFeedbackGenerator *generator = [UINotificationFeedbackGenerator new];
    [generator prepare];
    [generator notificationOccurred:(decision == BEHHapticDecisionMaximum) ? UINotificationFeedbackTypeSuccess : UINotificationFeedbackTypeWarning];
}

%ctor {
    @autoreleasepool {
        if (!BEHIsSpringBoard()) return;
        BEHReload();
        BEHLastState = BEHClassifyBrightness(UIScreen.mainScreen.brightness);
        BEHObserver = [NSNotificationCenter.defaultCenter addObserverForName:UIScreenBrightnessDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            UIScreen *screen = [note.object isKindOfClass:UIScreen.class] ? note.object : UIScreen.mainScreen;
            BEHHandleBrightness(screen.brightness);
        }];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, BEHPreferencesChanged, BEHChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
