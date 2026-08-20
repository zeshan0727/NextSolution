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

static NSString *NLLower(NSString *s) {
    return [s isKindOfClass:[NSString class]] ? s.lowercaseString : @""];
}

static BOOL NLStringHasAny(NSString *s, NSArray<NSString *> *tokens) {
    NSString *lower = NLLower(s);
    for (NSString *token in tokens) {
        if ([lower containsString:token]) return YES;
    }
    return NO;
}

static BOOL NLViewHasToken(UIView *view, NSArray<NSString *> *tokens) {
    if (!view) return NO;
    NSString *className = NSStringFromClass(view.class);
    NSString *identifier = view.accessibilityIdentifier;
    NSString *label = view.accessibilityLabel;
    return NLStringHasAny(className, tokens) || NLStringHasAny(identifier, tokens) || NLStringHasAny(label, tokens);
}

static NSArray<UIView *> *NLDescendants(UIView *root, NSUInteger limit) {
    if (!root) return @[];
    NSMutableArray<UIView *> *result = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    NSUInteger index = 0;
    while (index < queue.count && result.count < limit) {
        UIView *view = queue[index++];
        [result addObject:view];
        for (UIView *child in view.subviews) {
            if (result.count + queue.count >= limit * 2) break;
            [queue addObject:child];
        }
    }
    return result;
}

static UIView *NLTopLockRootFromDateView(UIView *dateView) {
    if (!dateView.window) return nil;
    UIView *current = dateView;
    UIView *best = dateView;
    for (NSInteger i = 0; i < 14 && current.superview && current.superview != dateView.window; i++) {
        current = current.superview;
        best = current;
        NSString *name = NLLower(NSStringFromClass(current.class));
        if ([name containsString:@"coversheet"] || [name containsString:@"lockscreen"]) {
            best = current;
        }
    }
    return best;
}

static void NLApplyCustomClockVisibility(UIView *root) {
    if (!root || (!NLHideTime && !NLHideDate)) {
        // Still restore any previously suppressed NextLock labels if switches were turned off.
    }

    UIView *overlay = nil;
    NSArray<UIView *> *all = NLDescendants(root, 700);
    for (UIView *view in all) {
        if (fabs(view.layer.zPosition - 900.0) < 0.75 && !view.userInteractionEnabled) {
            NSUInteger labels = 0;
            for (UIView *child in view.subviews) if ([child isKindOfClass:[UILabel class]]) labels++;
            if (labels >= 2) { overlay = view; break; }
        }
    }
    if (!overlay) return;

    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    for (UIView *view in NLDescendants(overlay, 40)) {
        if ([view isKindOfClass:[UILabel class]]) [labels addObject:(UILabel *)view];
    }
    if (labels.count < 2) return;

    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGFloat pa = a.font.pointSize, pb = b.font.pointSize;
        if (pa > pb) return NSOrderedAscending;
        if (pa < pb) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    UILabel *timeLabel = labels.firstObject;
    UILabel *dateLabel = labels.count > 1 ? labels[1] : nil;
    NLSetSuppressed(timeLabel, NLHideTime, NO);
    NLSetSuppressed(dateLabel, NLHideDate, NO);
}

static NSArray<UIControl *> *NLQuickActionControls(UIView *quickView) {
    NSMutableArray<UIControl *> *controls = [NSMutableArray array];
    for (UIView *view in NLDescendants(quickView, 100)) {
        if (![view isKindOfClass:[UIControl class]]) continue;
        CGRect b = view.bounds;
        if (b.size.width < 24 || b.size.height < 24) continue;
        [controls addObject:(UIControl *)view];
    }
    return controls;
}

static void NLApplyQuickActions(UIView *quickView) {
    if (!quickView) return;
    NSArray<NSString *> *cameraTokens = @[@"camera"];
    NSArray<NSString *> *flashTokens = @[@"flashlight", @"torch", @"flash"];
    NSArray<UIControl *> *controls = NLQuickActionControls(quickView);
    UIControl *camera = nil;
    UIControl *flash = nil;

    for (UIControl *control in controls) {
        if (!camera && NLViewHasToken(control, cameraTokens)) camera = control;
        if (!flash && NLViewHasToken(control, flashTokens)) flash = control;
    }

    if ((!camera || !flash) && controls.count >= 2) {
        NSArray<UIControl *> *sorted = [controls sortedArrayUsingComparator:^NSComparisonResult(UIControl *a, UIControl *b) {
            CGPoint ca = [a.superview convertPoint:a.center toView:quickView];
            CGPoint cb = [b.superview convertPoint:b.center toView:quickView];
            if (ca.x < cb.x) return NSOrderedAscending;
            if (ca.x > cb.x) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        if (!flash) flash = sorted.firstObject;
        if (!camera) camera = sorted.lastObject;
    }

    NLSetSuppressed(flash, NLHideFlashlight, YES);
    NLSetSuppressed(camera, NLHideCamera, YES);
}

static void NLApplyElementVisibility(void) {
    UIView *root = NLLockRoot;
    if (!root || !root.window) return;

    NLApplyCustomClockVisibility(root);

    NSArray<NSString *> *otherTextTokens = @[
        @"calltoaction", @"teachable", @"instruction", @"hintlabel",
        @"unlocklabel", @"charginglabel", @"chargingtext"
    ];
    NSArray<NSString *> *barTokens = @[
        @"homeaffordance", @"controlcentergrabber", @"controlcenterindicator", @"grabber"
    ];

    for (UIView *view in NLDescendants(root, 900)) {
        NSString *name = NLLower(NSStringFromClass(view.class));

        if ([name containsString:@"quickactionsview"]) {
            NLApplyQuickActions(view);
        }

        BOOL isLockStatusBar = [name containsString:@"statusbar"] &&
            ([name hasPrefix:@"cs"] || [name containsString:@"lockscreen"] || [name containsString:@"coversheet"]);
        if (isLockStatusBar) NLSetSuppressed(view, NLHideStatusBar, NO);

        if (NLStringHasAny(name, otherTextTokens)) {
            // Do not touch the native date container/subtitle here; Test 12 manages those separately.
            if (![name containsString:@"date"] && ![name containsString:@"time"]) {
                NLSetSuppressed(view, NLHideOtherText, NO);
            }
        }

        BOOL barMatch = NLStringHasAny(name, barTokens);
        if (!barMatch && [name containsString:@"lumadodgepill"]) {
            CGRect b = view.bounds;
            barMatch = b.size.width > 70 && b.size.width > b.size.height * 2.5;
        }
        if (barMatch) NLSetSuppressed(view, NLHideBars, NO);
    }
}

static void NLDateDidMove(UIView *self, SEL _cmd) {
    if (NLOrigDateDidMove) NLOrigDateDidMove(self, _cmd);
    NLDateView = self;
    if (self.window) {
        NLLockRoot = NLTopLockRootFromDateView(self);
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
        if (NLDateView.window) NLLockRoot = NLTopLockRootFromDateView(NLDateView);
        NLApplyElementVisibility();
    });
}

static void NLStartHideTimer(void) {
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
            NLStartHideTimer();
            NSLog(@"[NextLockHideElements] Test13 loaded: independent hide controls ready");
        });
    }
}
