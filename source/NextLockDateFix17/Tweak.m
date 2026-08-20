#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

extern void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result);

static NSString * const NLPrefsDomain = @"com.nextsolution.lockglyphtime";
static const CFStringRef NLPrefsChangedName = CFSTR("com.nextsolution.lockglyphtime/ReloadPrefs");

__attribute__((used)) static const char *NL17Marker =
    "NextLockDateFix17 1.1.5-test17 prominent-subtitle-container-date-fix";

static BOOL NLHideDate = NO;
static __weak UIView *NLSubtitleView = nil;
static __weak UIView *NLDateView = nil;
static __weak UIView *NLCompactDateView = nil;
static __weak UIView *NLDateTextLabel = nil;

static char NL17OriginalHiddenKey;
static char NL17OriginalAlphaKey;

static void (*NLOrigSubtitleLayout)(UIView *, SEL) = NULL;
static void (*NLOrigSubtitleSetDate)(id, SEL, id) = NULL;
static void (*NLOrigDateUpdateLabel)(id, SEL) = NULL;
static void (*NLOrigDateSetDate)(id, SEL, id) = NULL;

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
    NLHideDate = NLCopyBool(CFSTR("hideLockScreenDate"), NO);
}

static void NLSetSuppressed(UIView *view, BOOL suppress) {
    if (!view) return;
    NSNumber *oldHidden = objc_getAssociatedObject(view, &NL17OriginalHiddenKey);
    NSNumber *oldAlpha = objc_getAssociatedObject(view, &NL17OriginalAlphaKey);

    if (suppress) {
        if (!oldHidden) {
            objc_setAssociatedObject(view, &NL17OriginalHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!oldAlpha) {
            objc_setAssociatedObject(view, &NL17OriginalAlphaKey, @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        view.hidden = YES;
        view.alpha = 0.0;
    } else {
        if (oldHidden) {
            view.hidden = oldHidden.boolValue;
            objc_setAssociatedObject(view, &NL17OriginalHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (oldAlpha) {
            view.alpha = oldAlpha.doubleValue;
            objc_setAssociatedObject(view, &NL17OriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static id NLSendId(id object, NSString *selectorName) {
    if (!object) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, sel);
}

static void NLApplyInnerDateView(UIView *view) {
    if (!view) return;
    NLSetSuppressed(view, NLHideDate);
    id label = NLSendId(view, @"textLabel");
    if ([label isKindOfClass:[UIView class]]) {
        NLDateTextLabel = label;
        NLSetSuppressed((UIView *)label, NLHideDate);
    }
}

static void NLApplySubtitleHierarchy(UIView *subtitle) {
    if (!subtitle) return;
    NLSubtitleView = subtitle;

    // iOS 16 CSProminentSubtitleView owns both normal and compact date variants.
    id dateView = NLSendId(subtitle, @"dateView");
    id compactDateView = NLSendId(subtitle, @"compactDateView");
    if ([dateView isKindOfClass:[UIView class]]) NLDateView = dateView;
    if ([compactDateView isKindOfClass:[UIView class]]) NLCompactDateView = compactDateView;

    NLSetSuppressed(subtitle, NLHideDate);
    NLApplyInnerDateView(NLDateView);
    NLApplyInnerDateView(NLCompactDateView);
}

static void NLSubtitleLayout(UIView *self, SEL _cmd) {
    if (NLOrigSubtitleLayout) NLOrigSubtitleLayout(self, _cmd);
    NLApplySubtitleHierarchy(self);
}

static void NLSubtitleSetDate(id self, SEL _cmd, id date) {
    if (NLOrigSubtitleSetDate) NLOrigSubtitleSetDate(self, _cmd, date);
    if ([self isKindOfClass:[UIView class]]) NLApplySubtitleHierarchy((UIView *)self);
}

static void NLDateUpdateLabel(id self, SEL _cmd) {
    if (NLOrigDateUpdateLabel) NLOrigDateUpdateLabel(self, _cmd);
    if ([self isKindOfClass:[UIView class]]) {
        NLDateView = (UIView *)self;
        NLApplyInnerDateView((UIView *)self);
    }
}

static void NLDateSetDate(id self, SEL _cmd, id date) {
    if (NLOrigDateSetDate) NLOrigDateSetDate(self, _cmd, date);
    if ([self isKindOfClass:[UIView class]]) {
        NLDateView = (UIView *)self;
        NLApplyInnerDateView((UIView *)self);
    }
}

static void NLApplyKnownViews(void) {
    NLSetSuppressed(NLSubtitleView, NLHideDate);
    NLApplyInnerDateView(NLDateView);
    NLApplyInnerDateView(NLCompactDateView);
    NLSetSuppressed(NLDateTextLabel, NLHideDate);
}

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
        NLApplyKnownViews();
    });
}

__attribute__((constructor)) static void NL17Init(void) {
    @autoreleasepool {
        NLReloadPrefs();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        NLPrefsChanged, NLPrefsChangedName, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        dispatch_async(dispatch_get_main_queue(), ^{
            // CSProminentSubtitleView is the iOS 16 native date container and owns
            // both dateView and compactDateView. This keeps NextLock's custom date
            // overlay untouched while hiding every stock date variant.
            NLHookIfAvailable(@"CSProminentSubtitleView", @"layoutSubviews",
                              (IMP)NLSubtitleLayout, (IMP *)&NLOrigSubtitleLayout);
            NLHookIfAvailable(@"CSProminentSubtitleView", @"setDate:",
                              (IMP)NLSubtitleSetDate, (IMP *)&NLOrigSubtitleSetDate);

            // Backstop the concrete native date view whenever Apple refreshes its label.
            NLHookIfAvailable(@"CSProminentSubtitleDateView", @"_updateLabel",
                              (IMP)NLDateUpdateLabel, (IMP *)&NLOrigDateUpdateLabel);
            NLHookIfAvailable(@"CSProminentSubtitleDateView", @"setDate:",
                              (IMP)NLDateSetDate, (IMP *)&NLOrigDateSetDate);

            NLApplyKnownViews();
            NSLog(@"[NextLockDateFix17] Test17 loaded: CSProminentSubtitleView date container fix active");
        });
    }
}
