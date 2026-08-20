#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

extern void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result);

static NSString * const NLPrefsDomain = @"com.nextsolution.lockglyphtime";
static const CFStringRef NLPrefsChangedName = CFSTR("com.nextsolution.lockglyphtime/ReloadPrefs");

__attribute__((used)) static const char *NLHideMarker =
    "NextLockHideElements 1.1.5-test14 direct-functional-hide-items";

static BOOL NLHideTime = NO;
static BOOL NLHideDate = NO;
static BOOL NLHideCamera = NO;
static BOOL NLHideFlashlight = NO;
static BOOL NLHideStatusBar = NO;
static BOOL NLHideOtherText = NO;
static BOOL NLHideBars = NO;

static __weak UIView *NLDateView = nil;
static __weak UIWindow *NLLockWindow = nil;
static BOOL NLLockScreenActive = NO;
static dispatch_source_t NLHideTimer = nil;
static CFTimeInterval NLLastFullApply = 0;

static void (*NLOrigDateDidMove)(UIView *, SEL) = NULL;
static void (*NLOrigDateLayout)(UIView *, SEL) = NULL;
static void (*NLOrigQuickDidMove)(UIView *, SEL) = NULL;
static void (*NLOrigQuickLayout)(UIView *, SEL) = NULL;

static char NLOriginalAlphaKey;
static char NLOriginalHiddenKey;
static char NLOriginalInteractionKey;

#pragma mark - Preferences

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

#pragma mark - View helpers

static void NLSetSuppressed(UIView *view, BOOL suppress, BOOL disableInteraction) {
    if (!view) return;

    NSNumber *storedAlpha = objc_getAssociatedObject(view, &NLOriginalAlphaKey);
    NSNumber *storedHidden = objc_getAssociatedObject(view, &NLOriginalHiddenKey);
    NSNumber *storedInteraction = objc_getAssociatedObject(view, &NLOriginalInteractionKey);

    if (suppress) {
        if (!storedAlpha) {
            objc_setAssociatedObject(view, &NLOriginalAlphaKey, @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!storedHidden) {
            objc_setAssociatedObject(view, &NLOriginalHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (disableInteraction && !storedInteraction) {
            objc_setAssociatedObject(view, &NLOriginalInteractionKey, @(view.userInteractionEnabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        view.alpha = 0.0;
        view.hidden = YES;
        if (disableInteraction) view.userInteractionEnabled = NO;
    } else {
        if (storedAlpha) {
            view.alpha = storedAlpha.doubleValue;
            objc_setAssociatedObject(view, &NLOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (storedHidden) {
            view.hidden = storedHidden.boolValue;
            objc_setAssociatedObject(view, &NLOriginalHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

static BOOL NLContainsAny(NSString *value, NSArray<NSString *> *tokens) {
    NSString *lower = NLLower(value);
    for (NSString *token in tokens) {
        if ([lower containsString:token]) return YES;
    }
    return NO;
}

static BOOL NLViewMatches(UIView *view, NSArray<NSString *> *tokens) {
    if (!view) return NO;
    if (NLContainsAny(NSStringFromClass(view.class), tokens)) return YES;
    if (NLContainsAny(view.accessibilityIdentifier, tokens)) return YES;
    if (NLContainsAny(view.accessibilityLabel, tokens)) return YES;
    return NO;
}

static NSArray<UIView *> *NLDescendants(UIView *root, NSUInteger maxCount) {
    if (!root) return @[];
    NSMutableArray<UIView *> *result = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
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

static NSArray<UIWindow *> *NLAllWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if ([window isKindOfClass:[UIWindow class]]) [windows addObject:window];
    }
    return windows;
}

static void NLRestoreSuppressedViews(void) {
    for (UIWindow *window in NLAllWindows()) {
        for (UIView *view in NLDescendants(window, 2600)) {
            if (objc_getAssociatedObject(view, &NLOriginalAlphaKey) ||
                objc_getAssociatedObject(view, &NLOriginalHiddenKey) ||
                objc_getAssociatedObject(view, &NLOriginalInteractionKey)) {
                NLSetSuppressed(view, NO, NO);
            }
        }
    }
}

#pragma mark - Time / Date

static UIView *NLFindCustomClockOverlay(UIWindow *window) {
    if (!window) return nil;
    for (UIView *view in NLDescendants(window, 2200)) {
        CGFloat z = view.layer.zPosition;
        if (z < 899.0 || z > 901.0 || view.userInteractionEnabled) continue;
        NSUInteger labelCount = 0;
        for (UIView *child in view.subviews) {
            if ([child isKindOfClass:[UILabel class]]) labelCount++;
        }
        if (labelCount >= 2) return view;
    }
    return nil;
}

static void NLApplyTimeDate(void) {
    UIWindow *window = NLLockWindow;
    if (!window) return;
    UIView *overlay = NLFindCustomClockOverlay(window);
    if (!overlay) return;

    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    for (UIView *view in NLDescendants(overlay, 50)) {
        if ([view isKindOfClass:[UILabel class]]) [labels addObject:(UILabel *)view];
    }
    if (labels.count < 2) return;

    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        if (a.font.pointSize > b.font.pointSize) return NSOrderedAscending;
        if (a.font.pointSize < b.font.pointSize) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    NLSetSuppressed(labels[0], NLHideTime, NO);
    NLSetSuppressed(labels[1], NLHideDate, NO);
}

#pragma mark - Camera / Flashlight

static UIView *NLValueView(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        @try {
            id value = [object valueForKey:key];
            if ([value isKindOfClass:[UIView class]]) return value;
        } @catch (__unused NSException *exception) {}
    }
    return nil;
}

static NSArray<UIControl *> *NLQuickControls(UIView *quickView) {
    NSMutableArray<UIControl *> *controls = [NSMutableArray array];
    for (UIView *view in NLDescendants(quickView, 180)) {
        if (![view isKindOfClass:[UIControl class]]) continue;
        if (view.bounds.size.width < 24.0 || view.bounds.size.height < 24.0) continue;
        [controls addObject:(UIControl *)view];
    }
    return controls;
}

static void NLApplyQuickActions(UIView *quickView) {
    if (!quickView) return;

    UIView *camera = NLValueView(quickView, @[@"_cameraButton", @"cameraButton", @"_cameraQuickActionButton", @"cameraQuickActionButton"]);
    UIView *flashlight = NLValueView(quickView, @[@"_flashlightButton", @"flashlightButton", @"_torchButton", @"torchButton", @"_flashlightQuickActionButton", @"flashlightQuickActionButton"]);

    NSArray<UIControl *> *controls = NLQuickControls(quickView);
    NSArray *cameraTokens = @[@"camera"];
    NSArray *flashTokens = @[@"flashlight", @"torch", @"flash"];

    for (UIControl *control in controls) {
        if (!camera && NLViewMatches(control, cameraTokens)) camera = control;
        if (!flashlight && NLViewMatches(control, flashTokens)) flashlight = control;
    }

    if ((!camera || !flashlight) && controls.count >= 2) {
        NSArray<UIControl *> *sorted = [controls sortedArrayUsingComparator:^NSComparisonResult(UIControl *a, UIControl *b) {
            CGPoint ap = [a.superview convertPoint:a.center toView:quickView];
            CGPoint bp = [b.superview convertPoint:b.center toView:quickView];
            if (ap.x < bp.x) return NSOrderedAscending;
            if (ap.x > bp.x) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        if (!flashlight) flashlight = sorted.firstObject;
        if (!camera) camera = sorted.lastObject;
    }

    NLSetSuppressed(flashlight, NLLockScreenActive && NLHideFlashlight, YES);
    NLSetSuppressed(camera, NLLockScreenActive && NLHideCamera, YES);
}

#pragma mark - Status bar / text / bars

static BOOL NLIsStatusBarView(UIView *view) {
    NSString *name = NLLower(NSStringFromClass(view.class));
    NSString *identifier = NLLower(view.accessibilityIdentifier);
    if ([name containsString:@"statusbar"] || [identifier containsString:@"statusbar"]) return YES;
    return NO;
}

static BOOL NLIsOtherLockText(UIView *view) {
    if (![view isKindOfClass:[UILabel class]] && ![NLLower(NSStringFromClass(view.class)) containsString:@"label"]) return NO;
    NSArray *tokens = @[@"calltoaction", @"teachable", @"instruction", @"hint", @"unlock", @"swipe", @"charging", @"face id", @"faceid"];
    return NLViewMatches(view, tokens);
}

static BOOL NLIsBarView(UIView *view, UIWindow *window) {
    NSArray *tokens = @[@"homeaffordance", @"homeindicator", @"controlcentergrabber", @"controlcenterindicator", @"grabber", @"lumadodgepill"];
    if (NLViewMatches(view, tokens)) return YES;

    CGRect rect = [view convertRect:view.bounds toView:window];
    CGFloat width = CGRectGetWidth(rect);
    CGFloat height = CGRectGetHeight(rect);
    CGFloat maxY = CGRectGetMaxY(window.bounds);
    BOOL pillShape = width >= 70.0 && height > 0.5 && height <= 12.0 && width >= height * 6.0;
    BOOL edgePosition = CGRectGetMinY(rect) <= 55.0 || CGRectGetMaxY(rect) >= maxY - 40.0;
    return pillShape && edgePosition;
}

static void NLApplyWindowElements(void) {
    if (!NLLockScreenActive) return;
    UIWindow *lockWindow = NLLockWindow;
    if (!lockWindow) return;

    for (UIWindow *window in NLAllWindows()) {
        for (UIView *view in NLDescendants(window, 2600)) {
            if (NLIsStatusBarView(view)) {
                NLSetSuppressed(view, NLHideStatusBar, NO);
            }
        }
    }

    for (UIView *view in NLDescendants(lockWindow, 2600)) {
        NSString *name = NLLower(NSStringFromClass(view.class));
        if ([name containsString:@"quickactionsview"]) NLApplyQuickActions(view);
        if (NLIsOtherLockText(view)) NLSetSuppressed(view, NLHideOtherText, NO);
        if (NLIsBarView(view, lockWindow)) NLSetSuppressed(view, NLHideBars, NO);
    }
}

static void NLApplyAll(void) {
    if (!NLLockScreenActive || !NLLockWindow) {
        NLRestoreSuppressedViews();
        return;
    }
    NLApplyTimeDate();
    NLApplyWindowElements();
}

#pragma mark - Hooks

static void NLDateDidMove(UIView *self, SEL _cmd) {
    if (NLOrigDateDidMove) NLOrigDateDidMove(self, _cmd);
    NLDateView = self;
    NLLockScreenActive = self.window != nil;
    NLLockWindow = self.window;

    if (NLLockScreenActive) {
        dispatch_async(dispatch_get_main_queue(), ^{ NLApplyAll(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ NLApplyAll(); });
    } else {
        NLRestoreSuppressedViews();
        NLLockWindow = nil;
    }
}

static void NLDateLayout(UIView *self, SEL _cmd) {
    if (NLOrigDateLayout) NLOrigDateLayout(self, _cmd);
    if (!self.window) return;
    NLDateView = self;
    NLLockScreenActive = YES;
    NLLockWindow = self.window;

    NLApplyTimeDate();
    CFTimeInterval now = CACurrentMediaTime();
    if (now - NLLastFullApply >= 0.5) {
        NLLastFullApply = now;
        NLApplyWindowElements();
    }
}

static void NLQuickDidMove(UIView *self, SEL _cmd) {
    if (NLOrigQuickDidMove) NLOrigQuickDidMove(self, _cmd);
    if (self.window && NLLockScreenActive) NLApplyQuickActions(self);
    else {
        for (UIControl *control in NLQuickControls(self)) NLSetSuppressed(control, NO, NO);
    }
}

static void NLQuickLayout(UIView *self, SEL _cmd) {
    if (NLOrigQuickLayout) NLOrigQuickLayout(self, _cmd);
    if (self.window && NLLockScreenActive) NLApplyQuickActions(self);
}

static void NLPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                           const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    NLReloadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{
        NLApplyAll();
    });
}

static void NLStartTimer(void) {
    if (NLHideTimer) return;
    NLHideTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(NLHideTimer,
                              dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                              NSEC_PER_SEC,
                              250 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(NLHideTimer, ^{
        if (NLLockScreenActive && NLAnyHideEnabled()) NLApplyAll();
    });
    dispatch_resume(NLHideTimer);
}

static void NLHookClassIfAvailable(NSString *className, SEL selector, IMP replacement, IMP *original) {
    Class cls = NSClassFromString(className);
    if (cls && class_getInstanceMethod(cls, selector)) {
        MSHookMessageEx(cls, selector, replacement, original);
    }
}

__attribute__((constructor)) static void NLHideInit(void) {
    @autoreleasepool {
        NLReloadPrefs();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        NLPrefsChanged, NLPrefsChangedName, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        dispatch_async(dispatch_get_main_queue(), ^{
            NLHookClassIfAvailable(@"SBFLockScreenDateView", @selector(didMoveToWindow),
                                   (IMP)NLDateDidMove, (IMP *)&NLOrigDateDidMove);
            NLHookClassIfAvailable(@"SBFLockScreenDateView", @selector(layoutSubviews),
                                   (IMP)NLDateLayout, (IMP *)&NLOrigDateLayout);
            NLHookClassIfAvailable(@"CSQuickActionsView", @selector(didMoveToWindow),
                                   (IMP)NLQuickDidMove, (IMP *)&NLOrigQuickDidMove);
            NLHookClassIfAvailable(@"CSQuickActionsView", @selector(layoutSubviews),
                                   (IMP)NLQuickLayout, (IMP *)&NLOrigQuickLayout);
            NLStartTimer();
            NSLog(@"[NextLockHideElements] Test14 loaded: Hide Items direct controls active");
        });
    }
}
