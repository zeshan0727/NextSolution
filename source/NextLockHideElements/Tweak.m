#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

extern void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result);

static NSString * const NLPrefsDomain = @"com.nextsolution.lockglyphtime";
static const CFStringRef NLPrefsChangedName = CFSTR("com.nextsolution.lockglyphtime/ReloadPrefs");

__attribute__((used)) static const char *NLHideMarker =
    "NextLockHideElements 1.1.5-test15 designer-direct-safe-hooks";

static BOOL NLHideTime = NO;
static BOOL NLHideDate = NO;
static BOOL NLHideCamera = NO;
static BOOL NLHideFlashlight = NO;
static BOOL NLHideStatusBar = NO;
static BOOL NLHideOtherText = NO;
static BOOL NLHideBars = NO;
static BOOL NLLastKnownLocked = NO;

static __weak UIView *NLCustomTimeLabel = nil;
static __weak UIView *NLCustomDateLabel = nil;
static __weak UIView *NLCCGrabberView = nil;
static __weak UIView *NLHomeAffordanceView = nil;
static __weak UIView *NLHomeAffordanceContainerView = nil;
static __weak UIView *NLStatusBarView = nil;
static __weak UIView *NLStatusLegibilityView = nil;
static __weak UIView *NLCallToActionView = nil;
static __weak UIView *NLFocusActivityView = nil;
static __weak UIView *NLFixedFooterView = nil;

static char NLOriginalHiddenKey;
static char NLOriginalAlphaKey;

static BOOL (*NLOrigHasCamera)(id, SEL) = NULL;
static BOOL (*NLOrigHasFlashlight)(id, SEL) = NULL;
static UIView *(*NLOrigControlCenterGrabberView)(id, SEL) = NULL;
static UIView *(*NLOrigHomeAffordanceView)(id, SEL) = NULL;
static UIView *(*NLOrigHomeAffordanceContainerView)(id, SEL) = NULL;
static BOOL (*NLOrigIsUILocked)(id, SEL) = NULL;

static void (*NLOrigDateLayout)(UIView *, SEL) = NULL;
static void (*NLOrigDateDidMove)(UIView *, SEL) = NULL;
static void (*NLOrigStatusLayout)(UIView *, SEL) = NULL;
static void (*NLOrigStatusDidMove)(UIView *, SEL) = NULL;
static void (*NLOrigLegibilityLayout)(UIView *, SEL) = NULL;
static void (*NLOrigLegibilityDidMove)(UIView *, SEL) = NULL;
static void (*NLOrigCallLayout)(UIView *, SEL) = NULL;
static void (*NLOrigCallDidMove)(UIView *, SEL) = NULL;
static void (*NLOrigFocusLayout)(UIView *, SEL) = NULL;
static void (*NLOrigFocusDidMove)(UIView *, SEL) = NULL;
static void (*NLOrigFooterLayout)(UIView *, SEL) = NULL;
static void (*NLOrigFooterDidMove)(UIView *, SEL) = NULL;

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

#pragma mark - Safe state helpers

static void NLSetSuppressed(UIView *view, BOOL suppress) {
    if (!view) return;

    NSNumber *oldHidden = objc_getAssociatedObject(view, &NLOriginalHiddenKey);
    NSNumber *oldAlpha = objc_getAssociatedObject(view, &NLOriginalAlphaKey);

    if (suppress) {
        if (!oldHidden) {
            objc_setAssociatedObject(view, &NLOriginalHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!oldAlpha) {
            objc_setAssociatedObject(view, &NLOriginalAlphaKey, @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!view.hidden) view.hidden = YES;
        if (view.alpha != 0.0) view.alpha = 0.0;
    } else {
        if (oldHidden) {
            BOOL value = oldHidden.boolValue;
            objc_setAssociatedObject(view, &NLOriginalHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (view.hidden != value) view.hidden = value;
        }
        if (oldAlpha) {
            CGFloat value = oldAlpha.doubleValue;
            objc_setAssociatedObject(view, &NLOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (view.alpha != value) view.alpha = value;
        }
    }
}

static id NLSendId(id object, NSString *selectorName) {
    if (!object) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, sel);
}

static BOOL NLQueryLockedDirect(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    if (!cls) return NO;
    id manager = NLSendId(cls, @"sharedInstance");
    if (!manager) manager = NLSendId(cls, @"sharedInstanceIfExists");
    if (!manager) return NO;
    SEL sel = NSSelectorFromString(@"isUILocked");
    if (![manager respondsToSelector:sel]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(manager, sel);
}

static BOOL NLShouldHideStatus(void) {
    return NLHideStatusBar && NLQueryLockedDirect();
}

static BOOL NLShouldHideOtherText(void) {
    return NLHideOtherText && NLQueryLockedDirect();
}

#pragma mark - Test 12 custom Time / Date overlay

static void NLApplyCustomClockVisibility(UIView *dateView) {
    UIView *parent = dateView.superview;
    if (!parent) return;

    UIView *overlay = nil;
    for (UIView *candidate in parent.subviews) {
        if (candidate == dateView) continue;
        CGFloat z = candidate.layer.zPosition;
        if (z < 899.5 || z > 900.5) continue;
        if (candidate.userInteractionEnabled) continue;
        NSUInteger directLabels = 0;
        for (UIView *child in candidate.subviews) {
            if ([child isKindOfClass:[UILabel class]]) directLabels++;
        }
        if (directLabels >= 2) {
            overlay = candidate;
            break;
        }
    }
    if (!overlay) return;

    NSMutableArray<UILabel *> *labels = [NSMutableArray arrayWithCapacity:2];
    for (UIView *child in overlay.subviews) {
        if ([child isKindOfClass:[UILabel class]]) [labels addObject:(UILabel *)child];
    }
    if (labels.count < 2) return;

    // Test 12 creates the labels in this exact order: Time, then Date.
    NLCustomTimeLabel = labels[0];
    NLCustomDateLabel = labels[1];
    NLSetSuppressed(NLCustomTimeLabel, NLHideTime);
    NLSetSuppressed(NLCustomDateLabel, NLHideDate);
}

static void NLDateLayout(UIView *self, SEL _cmd) {
    if (NLOrigDateLayout) NLOrigDateLayout(self, _cmd);
    NLApplyCustomClockVisibility(self);
}

static void NLDateDidMove(UIView *self, SEL _cmd) {
    if (NLOrigDateDidMove) NLOrigDateDidMove(self, _cmd);
    if (!self.window) {
        NLSetSuppressed(NLCustomTimeLabel, NO);
        NLSetSuppressed(NLCustomDateLabel, NO);
        NLCustomTimeLabel = nil;
        NLCustomDateLabel = nil;
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NLApplyCustomClockVisibility(self);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (self.window) NLApplyCustomClockVisibility(self);
    });
}

#pragma mark - Camera / Flashlight

static BOOL NLHasCamera(id self, SEL _cmd) {
    if (NLHideCamera) return NO;
    return NLOrigHasCamera ? NLOrigHasCamera(self, _cmd) : YES;
}

static BOOL NLHasFlashlight(id self, SEL _cmd) {
    if (NLHideFlashlight) return NO;
    return NLOrigHasFlashlight ? NLOrigHasFlashlight(self, _cmd) : YES;
}

#pragma mark - CC / Home bars

static UIView *NLControlCenterGrabberView(id self, SEL _cmd) {
    UIView *view = NLOrigControlCenterGrabberView ? NLOrigControlCenterGrabberView(self, _cmd) : nil;
    NLCCGrabberView = view;
    NLSetSuppressed(view, NLHideBars);
    return view;
}

static UIView *NLHomeAffordanceViewGetter(id self, SEL _cmd) {
    UIView *view = NLOrigHomeAffordanceView ? NLOrigHomeAffordanceView(self, _cmd) : nil;
    NLHomeAffordanceView = view;
    NLSetSuppressed(view, NLHideBars);
    return view;
}

static UIView *NLHomeAffordanceContainerViewGetter(id self, SEL _cmd) {
    UIView *view = NLOrigHomeAffordanceContainerView ? NLOrigHomeAffordanceContainerView(self, _cmd) : nil;
    NLHomeAffordanceContainerView = view;
    NLSetSuppressed(view, NLHideBars);
    return view;
}

#pragma mark - Lock-state aware Status Bar / Other Text

static void NLApplyStateBoundViews(void) {
    BOOL status = NLShouldHideStatus();
    BOOL text = NLShouldHideOtherText();
    NLSetSuppressed(NLStatusBarView, status);
    NLSetSuppressed(NLStatusLegibilityView, status);
    NLSetSuppressed(NLCallToActionView, text);
    NLSetSuppressed(NLFocusActivityView, text);
    NLSetSuppressed(NLFixedFooterView, text);
    NLSetSuppressed(NLCCGrabberView, NLHideBars);
    NLSetSuppressed(NLHomeAffordanceView, NLHideBars);
    NLSetSuppressed(NLHomeAffordanceContainerView, NLHideBars);
    NLSetSuppressed(NLCustomTimeLabel, NLHideTime);
    NLSetSuppressed(NLCustomDateLabel, NLHideDate);
}

static BOOL NLIsUILockedHook(id self, SEL _cmd) {
    BOOL locked = NLOrigIsUILocked ? NLOrigIsUILocked(self, _cmd) : NO;
    if (locked != NLLastKnownLocked) {
        NLLastKnownLocked = locked;
        dispatch_async(dispatch_get_main_queue(), ^{
            NLApplyStateBoundViews();
        });
    }
    return locked;
}

static void NLStatusLayout(UIView *self, SEL _cmd) {
    if (NLOrigStatusLayout) NLOrigStatusLayout(self, _cmd);
    NLStatusBarView = self;
    NLSetSuppressed(self, NLShouldHideStatus());
}

static void NLStatusDidMove(UIView *self, SEL _cmd) {
    if (NLOrigStatusDidMove) NLOrigStatusDidMove(self, _cmd);
    NLStatusBarView = self.window ? self : nil;
    NLSetSuppressed(self, self.window && NLShouldHideStatus());
}

static void NLLegibilityLayout(UIView *self, SEL _cmd) {
    if (NLOrigLegibilityLayout) NLOrigLegibilityLayout(self, _cmd);
    NLStatusLegibilityView = self;
    NLSetSuppressed(self, NLShouldHideStatus());
}

static void NLLegibilityDidMove(UIView *self, SEL _cmd) {
    if (NLOrigLegibilityDidMove) NLOrigLegibilityDidMove(self, _cmd);
    NLStatusLegibilityView = self.window ? self : nil;
    NLSetSuppressed(self, self.window && NLShouldHideStatus());
}

static void NLCallLayout(UIView *self, SEL _cmd) {
    if (NLOrigCallLayout) NLOrigCallLayout(self, _cmd);
    NLCallToActionView = self;
    NLSetSuppressed(self, NLShouldHideOtherText());
}

static void NLCallDidMove(UIView *self, SEL _cmd) {
    if (NLOrigCallDidMove) NLOrigCallDidMove(self, _cmd);
    NLCallToActionView = self.window ? self : nil;
    NLSetSuppressed(self, self.window && NLShouldHideOtherText());
}

static void NLFocusLayout(UIView *self, SEL _cmd) {
    if (NLOrigFocusLayout) NLOrigFocusLayout(self, _cmd);
    NLFocusActivityView = self;
    NLSetSuppressed(self, NLShouldHideOtherText());
}

static void NLFocusDidMove(UIView *self, SEL _cmd) {
    if (NLOrigFocusDidMove) NLOrigFocusDidMove(self, _cmd);
    NLFocusActivityView = self.window ? self : nil;
    NLSetSuppressed(self, self.window && NLShouldHideOtherText());
}

static void NLFooterLayout(UIView *self, SEL _cmd) {
    if (NLOrigFooterLayout) NLOrigFooterLayout(self, _cmd);
    NLFixedFooterView = self;
    NLSetSuppressed(self, NLShouldHideOtherText());
}

static void NLFooterDidMove(UIView *self, SEL _cmd) {
    if (NLOrigFooterDidMove) NLOrigFooterDidMove(self, _cmd);
    NLFixedFooterView = self.window ? self : nil;
    NLSetSuppressed(self, self.window && NLShouldHideOtherText());
}

#pragma mark - Hook installation

static void NLHookIfAvailable(NSString *className, NSString *selectorName, IMP replacement, IMP *original) {
    Class cls = NSClassFromString(className);
    SEL sel = NSSelectorFromString(selectorName);
    if (!cls || !class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, replacement, original);
}

static void NLPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                           const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    NLReloadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{
        NLApplyStateBoundViews();
    });
}

__attribute__((constructor)) static void NLHideInit(void) {
    @autoreleasepool {
        NLReloadPrefs();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        NLPrefsChanged, NLPrefsChangedName, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        dispatch_async(dispatch_get_main_queue(), ^{
            NLHookIfAvailable(@"SBFLockScreenDateView", @"layoutSubviews",
                              (IMP)NLDateLayout, (IMP *)&NLOrigDateLayout);
            NLHookIfAvailable(@"SBFLockScreenDateView", @"didMoveToWindow",
                              (IMP)NLDateDidMove, (IMP *)&NLOrigDateDidMove);

            NLHookIfAvailable(@"CSQuickActionsViewController", @"hasCamera",
                              (IMP)NLHasCamera, (IMP *)&NLOrigHasCamera);
            NLHookIfAvailable(@"CSQuickActionsViewController", @"hasFlashlight",
                              (IMP)NLHasFlashlight, (IMP *)&NLOrigHasFlashlight);
            NLHookIfAvailable(@"CSTeachableMomentsContainerView", @"controlCenterGrabberView",
                              (IMP)NLControlCenterGrabberView, (IMP *)&NLOrigControlCenterGrabberView);
            NLHookIfAvailable(@"CSTeachableMomentsContainerView", @"homeAffordanceView",
                              (IMP)NLHomeAffordanceViewGetter, (IMP *)&NLOrigHomeAffordanceView);
            NLHookIfAvailable(@"CSTeachableMomentsContainerView", @"homeAffordanceContainerView",
                              (IMP)NLHomeAffordanceContainerViewGetter, (IMP *)&NLOrigHomeAffordanceContainerView);

            NLHookIfAvailable(@"SBLockScreenManager", @"isUILocked",
                              (IMP)NLIsUILockedHook, (IMP *)&NLOrigIsUILocked);
            NLHookIfAvailable(@"_UIStatusBar", @"layoutSubviews",
                              (IMP)NLStatusLayout, (IMP *)&NLOrigStatusLayout);
            NLHookIfAvailable(@"_UIStatusBar", @"didMoveToWindow",
                              (IMP)NLStatusDidMove, (IMP *)&NLOrigStatusDidMove);
            NLHookIfAvailable(@"SBFStatusBarLegibilityView", @"layoutSubviews",
                              (IMP)NLLegibilityLayout, (IMP *)&NLOrigLegibilityLayout);
            NLHookIfAvailable(@"SBFStatusBarLegibilityView", @"didMoveToWindow",
                              (IMP)NLLegibilityDidMove, (IMP *)&NLOrigLegibilityDidMove);
            NLHookIfAvailable(@"SBUICallToActionLabel", @"layoutSubviews",
                              (IMP)NLCallLayout, (IMP *)&NLOrigCallLayout);
            NLHookIfAvailable(@"SBUICallToActionLabel", @"didMoveToWindow",
                              (IMP)NLCallDidMove, (IMP *)&NLOrigCallDidMove);
            NLHookIfAvailable(@"CSFocusActivityView", @"layoutSubviews",
                              (IMP)NLFocusLayout, (IMP *)&NLOrigFocusLayout);
            NLHookIfAvailable(@"CSFocusActivityView", @"didMoveToWindow",
                              (IMP)NLFocusDidMove, (IMP *)&NLOrigFocusDidMove);
            NLHookIfAvailable(@"CSFixedFooterView", @"layoutSubviews",
                              (IMP)NLFooterLayout, (IMP *)&NLOrigFooterLayout);
            NLHookIfAvailable(@"CSFixedFooterView", @"didMoveToWindow",
                              (IMP)NLFooterDidMove, (IMP *)&NLOrigFooterDidMove);

            NLLastKnownLocked = NLQueryLockedDirect();
            NLApplyStateBoundViews();
            NSLog(@"[NextLockHideElements] Test15 loaded: Designer direct safe hooks active");
        });
    }
}
