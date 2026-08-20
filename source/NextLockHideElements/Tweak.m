#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

extern void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result);

static NSString * const NLPrefsDomain = @"com.nextsolution.lockglyphtime";
static const CFStringRef NLPrefsChangedName = CFSTR("com.nextsolution.lockglyphtime/ReloadPrefs");

__attribute__((used)) static const char *NLHideMarker =
    "NextLockHideElements 1.1.5-test13 independent-lockscreen-hide-controls";

static BOOL NLHideTime = NO;
static BOOL NLHideDate = NO;
static BOOL NLHideCamera = NO;
static BOOL NLHideFlashlight = NO;
static BOOL NLHideStatusBar = NO;
static BOOL NLHideOtherText = NO;
static BOOL NLHideBars = NO;

static __weak UIView *NLLockRoot = nil;
static __weak UIView *NLDateView = nil;
static dispatch_source_t NLHideTimer = nil;
static void (*NLOrigDateDidMove)(UIView *, SEL) = NULL;

static char NLOriginalAlphaKey;
static char NLOriginalInteractionKey;

static CFTypeRef NLCopyPref(CFStringRef key) {
    return CFPreferencesCopyAppValue(key, (__bridge CFStringRef)NLPrefsDomain);
}

static BOOL NLCopyBool(CFStringRef key, BOOL fallback) {
    CFTypeRef value = NLCopyPref(key);
    if (!value) return fallback;
    BOOL result = fallback;
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
        result = CFBooleanGetValue((CFBooleanRef)value);
    } else if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        int n = 0;
        CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &n);
        result = n != 0;
    }
    CFRelease(value);
    return result;
}

static void NLReloadPrefs(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NLPrefsDomain);
    NLHideTime = NLCopyBool(CFSTR("hideLockScreenTime"), NO);
    NLHideDate = NLCopyBool(CFSTR("hideLockScreenDate"), NO);
    NLHideCamera = NLCopyBool(CFSTR("hideLockScreenCamera"), NO);
    NLHideFlashlight = NLCopyBool(CFSTR("hideLockScreenFlashlight"), NO);
    NLHideStatusBar = NLCopyBool(CFSTR("hideLockScreenStatusBar"), NO);
    NLHideOtherText = NLCopyBool(CFSTR("hideLockScreenOtherText"), NO);
    NLHideBars = NLCopyBool(CFSTR("hideLockScreenBars"), NO);
}

static BOOL NLAnyHideEnabled(void) {
    return NLHideTime || NLHideDate || NLHideCamera || NLHideFlashlight ||
           NLHideStatusBar || NLHideOtherText || NLHideBars;
}

static void NLSetSuppressed(UIView *view, BOOL suppress, BOOL disableInteraction) {
    if (!view) return;
    NSNumber *storedAlpha = objc_getAssociatedObject(view, &NLOriginalAlphaKey);
    NSNumber *storedInteraction = objc_getAssociatedObject(view, &NLOriginalInteractionKey);

    if (suppress) {
        if (!storedAlpha) {
            objc_setAssociatedObject(view, &NLOriginalAlphaKey, @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (disableInteraction && !storedInteraction) {
            objc_setAssociatedObject(view, &NLOriginalInteractionKey, @(view.userInteractionEnabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        view.alpha = 0.0;
        if (disableInteraction) view.userInteractionEnabled = NO;
    } else {
        if (storedAlpha) {
            view.alpha = storedAlpha.doubleValue;
            objc_setAssociatedObject(view, &NLOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (storedInteraction) {
            view.userInteractionEnabled = storedInteraction.boolValue;
            objc_setAssociatedObject(view, &NLOriginalInteractionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static NSString *NLLower(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return value.lowercaseString;
}

static BOOL NLContainsAny(NSString *value, NSArray *tokens) {
    NSString *lower = NLLower(value);
    for (NSString *token in tokens) {
        if ([lower containsString:token]) return YES;
    }
    return NO;
}

static BOOL NLViewMatches(UIView *view, NSArray *tokens) {
    if (!view) return NO;
    if (NLContainsAny(NSStringFromClass(view.class), tokens)) return YES;
    if (NLContainsAny(view.accessibilityIdentifier, tokens)) return YES;
    if (NLContainsAny(view.accessibilityLabel, tokens)) return YES;
    return NO;
}

static NSArray *NLDescendants(UIView *root, NSUInteger maxCount) {
    if (!root) return @[];
    NSMutableArray *result = [NSMutableArray array];
    NSMutableArray *queue = [NSMutableArray arrayWithObject:root];
    NSUInteger cursor = 0;
    while (cursor < queue.count && result.count < maxCount) {
        UIView *view = queue[cursor++];
        [result addObject:view];
        for (UIView *child in view.subviews) {
            if (queue.count >= maxCount) break;
            [queue addObject:child];
        }
    }
    return result;
}

static UIView *NLFindLockRoot(UIView *dateView) {
    if (!dateView || !dateView.window) return nil;
    UIView *current = dateView;
    UIView *best = dateView;
    for (NSInteger i = 0; i < 16 && current.superview && current.superview != dateView.window; i++) {
        current = current.superview;
        best = current;
        NSString *name = NLLower(NSStringFromClass(current.class));
        if ([name containsString:@"coversheet"] || [name containsString:@"lockscreen"]) best = current;
    }
    return best;
}

static void NLApplyCustomClockVisibility(UIView *root) {
    UIView *overlay = nil;
    for (UIView *view in NLDescendants(root, 700)) {
        CGFloat z = view.layer.zPosition;
        if (z >= 899.0 && z <= 901.0 && !view.userInteractionEnabled) {
            NSUInteger labelCount = 0;
            for (UIView *child in view.subviews) {
                if ([child isKindOfClass:[UILabel class]]) labelCount++;
            }
            if (labelCount >= 2) {
                overlay = view;
                break;
            }
        }
    }
    if (!overlay) return;

    NSMutableArray *labels = [NSMutableArray array];
    for (UIView *view in NLDescendants(overlay, 40)) {
        if ([view isKindOfClass:[UILabel class]]) [labels addObject:view];
    }
    if (labels.count < 2) return;

    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        if (a.font.pointSize > b.font.pointSize) return NSOrderedAscending;
        if (a.font.pointSize < b.font.pointSize) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    UILabel *timeLabel = labels[0];
    UILabel *dateLabel = labels[1];
    NLSetSuppressed(timeLabel, NLHideTime, NO);
    NLSetSuppressed(dateLabel, NLHideDate, NO);
}

static NSArray *NLQuickControls(UIView *quickView) {
    NSMutableArray *controls = [NSMutableArray array];
    for (UIView *view in NLDescendants(quickView, 120)) {
        if (![view isKindOfClass:[UIControl class]]) continue;
        if (view.bounds.size.width < 24.0 || view.bounds.size.height < 24.0) continue;
        [controls addObject:view];
    }
    return controls;
}

static void NLApplyQuickActions(UIView *quickView) {
    NSArray *controls = NLQuickControls(quickView);
    if (controls.count == 0) return;

    UIControl *camera = nil;
    UIControl *flashlight = nil;
    NSArray *cameraTokens = @[@"camera"];
    NSArray *flashTokens = @[@"flashlight", @"torch", @"flash"];

    for (UIControl *control in controls) {
        if (!camera && NLViewMatches(control, cameraTokens)) camera = control;
        if (!flashlight && NLViewMatches(control, flashTokens)) flashlight = control;
    }

    if ((!camera || !flashlight) && controls.count >= 2) {
        NSArray *sorted = [controls sortedArrayUsingComparator:^NSComparisonResult(UIControl *a, UIControl *b) {
            CGPoint ap = [a.superview convertPoint:a.center toView:quickView];
            CGPoint bp = [b.superview convertPoint:b.center toView:quickView];
            if (ap.x < bp.x) return NSOrderedAscending;
            if (ap.x > bp.x) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        if (!flashlight) flashlight = sorted.firstObject;
        if (!camera) camera = sorted.lastObject;
    }

    NLSetSuppressed(flashlight, NLHideFlashlight, YES);
    NLSetSuppressed(camera, NLHideCamera, YES);
}

static void NLApplyElementVisibility(void) {
    UIView *root = NLLockRoot;
    if (!root || !root.window) return;

    NLApplyCustomClockVisibility(root);

    NSArray *otherTextTokens = @[@"calltoaction", @"teachable", @"instruction", @"hintlabel", @"unlocklabel", @"charginglabel", @"chargingtext"];
    NSArray *barTokens = @[@"homeaffordance", @"controlcentergrabber", @"controlcenterindicator", @"grabber"];

    for (UIView *view in NLDescendants(root, 900)) {
        NSString *name = NLLower(NSStringFromClass(view.class));

        if ([name containsString:@"quickactionsview"]) {
            NLApplyQuickActions(view);
        }

        BOOL lockStatusBar = [name containsString:@"statusbar"] &&
            ([name hasPrefix:@"cs"] || [name containsString:@"lockscreen"] || [name containsString:@"coversheet"]);
        if (lockStatusBar) NLSetSuppressed(view, NLHideStatusBar, NO);

        if (NLContainsAny(name, otherTextTokens) && ![name containsString:@"date"] && ![name containsString:@"time"]) {
            NLSetSuppressed(view, NLHideOtherText, NO);
        }

        BOOL barMatch = NLContainsAny(name, barTokens);
        if (!barMatch && [name containsString:@"lumadodgepill"]) {
            CGRect b = view.bounds;
            barMatch = b.size.width > 70.0 && b.size.width > b.size.height * 2.5;
        }
        if (barMatch) NLSetSuppressed(view, NLHideBars, NO);
    }
}

static void NLDateDidMove(UIView *self, SEL _cmd) {
    if (NLOrigDateDidMove) NLOrigDateDidMove(self, _cmd);
    NLDateView = self;
    if (self.window) {
        NLLockRoot = NLFindLockRoot(self);
        dispatch_async(dispatch_get_main_queue(), ^{ NLApplyElementVisibility(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            NLApplyElementVisibility();
        });
    } else {
        NLLockRoot = nil;
    }
}

static void NLPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                           const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    NLReloadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (NLDateView.window) NLLockRoot = NLFindLockRoot(NLDateView);
        NLApplyElementVisibility();
    });
}

static void NLStartTimer(void) {
    if (NLHideTimer) return;
    NLHideTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(NLHideTimer,
                              dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                              2 * NSEC_PER_SEC,
                              500 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(NLHideTimer, ^{
        if (NLAnyHideEnabled()) NLApplyElementVisibility();
    });
    dispatch_resume(NLHideTimer);
}

__attribute__((constructor)) static void NLHideInit(void) {
    @autoreleasepool {
        NLReloadPrefs();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        NLPrefsChanged, NLPrefsChangedName, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        dispatch_async(dispatch_get_main_queue(), ^{
            Class dateView = NSClassFromString(@"SBFLockScreenDateView");
            if (dateView) {
                MSHookMessageEx(dateView, @selector(didMoveToWindow), (IMP)NLDateDidMove,
                                (IMP *)&NLOrigDateDidMove);
            }
            NLStartTimer();
            NSLog(@"[NextLockHideElements] Test13 loaded: independent hide controls ready");
        });
    }
}
