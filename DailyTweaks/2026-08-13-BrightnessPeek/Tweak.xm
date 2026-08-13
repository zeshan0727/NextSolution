#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static CFStringRef const BPPreferenceDomain = CFSTR("com.nextsolution.brightnesspeek");
static CFStringRef const BPPreferencesChanged = CFSTR("com.nextsolution.brightnesspeek.preferences.changed");
static BOOL BPEnabled = YES;
static UIWindow *BPWindow;
static UILabel *BPLabel;
static NSUInteger BPHideGeneration = 0;

@interface BPPassthroughWindow : UIWindow
@end
@implementation BPPassthroughWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return NO; }
@end

static BOOL BPIsSpringBoardProcess(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    return [bundleID isEqualToString:@"com.apple.springboard"] || [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"];
}

static BOOL BPReadEnabled(void) {
    CFPreferencesAppSynchronize(BPPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), BPPreferenceDomain));
    return value ? [value boolValue] : YES;
}

static NSInteger BPPercentForBrightness(CGFloat brightness) {
    CGFloat clamped = MIN(1.0, MAX(0.0, brightness));
    return (NSInteger)lround(clamped * 100.0);
}

static void BPEnsureOverlay(void) {
    if (BPWindow) return;
    CGRect screenBounds = UIScreen.mainScreen.bounds;
    BPWindow = [[BPPassthroughWindow alloc] initWithFrame:screenBounds];
    BPWindow.windowLevel = UIWindowLevelStatusBar + 2.0;
    BPWindow.backgroundColor = UIColor.clearColor;
    BPWindow.userInteractionEnabled = NO;
    BPWindow.hidden = YES;

    CGFloat width = 92.0, height = 38.0;
    BPLabel = [[UILabel alloc] initWithFrame:CGRectMake((CGRectGetWidth(screenBounds)-width)/2.0, 54.0, width, height)];
    BPLabel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.86];
    BPLabel.textColor = UIColor.whiteColor;
    BPLabel.textAlignment = NSTextAlignmentCenter;
    BPLabel.font = [UIFont monospacedDigitSystemFontOfSize:17.0 weight:UIFontWeightSemibold];
    BPLabel.layer.cornerRadius = 19.0;
    BPLabel.layer.masksToBounds = YES;
    BPLabel.accessibilityLabel = @"Screen brightness";
    [BPWindow addSubview:BPLabel];
}

static void BPShowCurrentBrightness(void) {
    if (!BPEnabled) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        BPEnsureOverlay();
        NSInteger percent = BPPercentForBrightness(UIScreen.mainScreen.brightness);
        BPLabel.text = [NSString stringWithFormat:@"☀︎ %ld%%", (long)percent];
        BPWindow.hidden = NO;
        BPWindow.alpha = 1.0;
        NSUInteger generation = ++BPHideGeneration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.85 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation != BPHideGeneration) return;
            [UIView animateWithDuration:0.18 animations:^{ BPWindow.alpha = 0.0; } completion:^(BOOL finished) {
                if (generation == BPHideGeneration) BPWindow.hidden = YES;
            }];
        });
    });
}

static void BPReloadPreferences(void) { BPEnabled = BPReadEnabled(); }
static void BPPreferencesChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) { BPReloadPreferences(); }
static void BPBrightnessChanged(NSNotification *note) { BPShowCurrentBrightness(); }

%ctor {
    @autoreleasepool {
        if (!BPIsSpringBoardProcess()) return;
        BPReloadPreferences();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, BPPreferencesChangedCallback, BPPreferencesChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        [[NSNotificationCenter defaultCenter] addObserverForName:UIScreenBrightnessDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { BPBrightnessChanged(note); }];
    }
}
