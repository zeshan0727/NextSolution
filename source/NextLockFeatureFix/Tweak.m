#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <os/lock.h>
#include <string.h>

extern void MSHookFunction(void *symbol, void *replace, void **result);

static const uint8_t kNextLock114Arm64eUUID[16] = {
    0x7B, 0xE1, 0x42, 0x8A, 0xC4, 0xB0, 0x38, 0xF8,
    0x81, 0x20, 0x7B, 0xAC, 0xBF, 0x22, 0x07, 0x31
};

// Verified arm64e entries in LockGlyphTime 1.1.4.
// +0x8388 = Time update, +0x86B8 = Date update.
static const uintptr_t kTimeUpdateOffset = 0x8388;
static const uintptr_t kDateUpdateOffset = 0x86B8;

static void (*NLOriginalTimeUpdate)(id host) = NULL;
static void (*NLOriginalDateUpdate)(id host) = NULL;
static os_unfair_lock NLConfigLock = OS_UNFAIR_LOCK_INIT;
static os_unfair_lock NLInstallLock = OS_UNFAIR_LOCK_INIT;
static BOOL NLInstalled = NO;

static BOOL NLTimeEnabled = YES;
static BOOL NLDateEnabled = YES;
static CGFloat NLTimeX = 0.0, NLTimeY = 0.0;
static CGFloat NLDateX = 0.0, NLDateY = 0.0;
static BOOL NLTimeShadowEnabled = NO, NLDateShadowEnabled = NO;
static CGFloat NLTimeShadowOpacity = 0.45, NLDateShadowOpacity = 0.45;
static CGFloat NLTimeShadowRadius = 2.0, NLDateShadowRadius = 2.0;
static CGFloat NLTimeShadowX = 0.0, NLTimeShadowY = 2.0;
static CGFloat NLDateShadowX = 0.0, NLDateShadowY = 2.0;
static NSInteger NLTimeStyle = 0, NLDateStyle = 0;
static UIColor *NLTimeColor = nil, *NLDateColor = nil;
static UIColor *NLTimeShadowColor = nil, *NLDateShadowColor = nil;

__attribute__((used)) static const char *NLFeatureFixMarker =
    "NextLockFeatureFix 1.1.5-test11 live-position-color-shadow arm64e";

static CFTypeRef NLCopyPref(CFStringRef key) {
    return CFPreferencesCopyAppValue(key, CFSTR("com.nextsolution.lockglyphtime"));
}

static BOOL NLCopyBool(CFStringRef key, BOOL fallback) {
    CFTypeRef v = NLCopyPref(key);
    if (!v) return fallback;
    BOOL out = fallback;
    if (CFGetTypeID(v) == CFBooleanGetTypeID()) out = CFBooleanGetValue((CFBooleanRef)v);
    else if (CFGetTypeID(v) == CFNumberGetTypeID()) {
        int n = 0; CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n); out = n != 0;
    }
    CFRelease(v); return out;
}

static double NLCopyDouble(CFStringRef key, double fallback) {
    CFTypeRef v = NLCopyPref(key);
    if (!v) return fallback;
    double out = fallback;
    if (CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &out);
    CFRelease(v); return out;
}

static NSInteger NLCopyInteger(CFStringRef key, NSInteger fallback) {
    CFTypeRef v = NLCopyPref(key);
    if (!v) return fallback;
    NSInteger out = fallback;
    if (CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberNSIntegerType, &out);
    CFRelease(v); return out;
}

static UIColor *NLColorFromString(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return nil;
    NSString *x = [[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([x hasPrefix:@"#"]) x = [x substringFromIndex:1];
    if ([x hasPrefix:@"0X"]) x = [x substringFromIndex:2];
    if (x.length != 6 && x.length != 8) return nil;
    unsigned long long value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:x];
    if (![scanner scanHexLongLong:&value]) return nil;
    CGFloat r,g,b,a;
    if (x.length == 6) {
        r=((value>>16)&0xff)/255.0; g=((value>>8)&0xff)/255.0; b=(value&0xff)/255.0; a=1.0;
    } else {
        r=((value>>24)&0xff)/255.0; g=((value>>16)&0xff)/255.0; b=((value>>8)&0xff)/255.0; a=(value&0xff)/255.0;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static UIColor *NLCopyColor(CFStringRef key) {
    CFTypeRef v = NLCopyPref(key);
    if (!v) return nil;
    UIColor *out = nil;
    if (CFGetTypeID(v) == CFStringGetTypeID()) {
        out = NLColorFromString((__bridge NSString *)v);
    } else if (CFGetTypeID(v) == CFDataGetTypeID()) {
        @try {
            id obj = [NSKeyedUnarchiver unarchiveObjectWithData:(__bridge NSData *)v];
            if ([obj isKindOfClass:[UIColor class]]) out = obj;
        } @catch (__unused NSException *e) {}
    }
    CFRelease(v);
    return out;
}

static void NLReloadConfig(void) {
    CFPreferencesAppSynchronize(CFSTR("com.nextsolution.lockglyphtime"));

    BOOL te = NLCopyBool(CFSTR("customTimeEnabled"), YES);
    BOOL de = NLCopyBool(CFSTR("customDateEnabled"), YES);
    CGFloat tx = (CGFloat)NLCopyDouble(CFSTR("timeOffsetX"), 0.0);
    CGFloat ty = (CGFloat)NLCopyDouble(CFSTR("timeOffsetY"), 0.0);
    CGFloat dx = (CGFloat)NLCopyDouble(CFSTR("dateOffsetX"), 0.0);
    CGFloat dy = (CGFloat)NLCopyDouble(CFSTR("dateOffsetY"), 0.0);
    UIColor *tc = NLCopyColor(CFSTR("timeColor"));
    UIColor *dc = NLCopyColor(CFSTR("dateColor"));
    BOOL tse = NLCopyBool(CFSTR("timeShadowEnabled"), NO);
    BOOL dse = NLCopyBool(CFSTR("dateShadowEnabled"), NO);
    UIColor *tsc = NLCopyColor(CFSTR("timeShadowColor"));
    UIColor *dsc = NLCopyColor(CFSTR("dateShadowColor"));
    CGFloat tso = (CGFloat)NLCopyDouble(CFSTR("timeShadowOpacity"), 0.45);
    CGFloat dso = (CGFloat)NLCopyDouble(CFSTR("dateShadowOpacity"), 0.45);
    CGFloat tsr = (CGFloat)NLCopyDouble(CFSTR("timeShadowRadius"), 2.0);
    CGFloat dsr = (CGFloat)NLCopyDouble(CFSTR("dateShadowRadius"), 2.0);
    CGFloat tsx = (CGFloat)NLCopyDouble(CFSTR("timeShadowOffsetX"), 0.0);
    CGFloat tsy = (CGFloat)NLCopyDouble(CFSTR("timeShadowOffsetY"), 2.0);
    CGFloat dsx = (CGFloat)NLCopyDouble(CFSTR("dateShadowOffsetX"), 0.0);
    CGFloat dsy = (CGFloat)NLCopyDouble(CFSTR("dateShadowOffsetY"), 2.0);
    NSInteger tstyle = NLCopyInteger(CFSTR("timeStyle"), 0);
    NSInteger dstyle = NLCopyInteger(CFSTR("dateStyle"), 0);

    tx = MAX(-300.0, MIN(300.0, tx)); ty = MAX(-300.0, MIN(300.0, ty));
    dx = MAX(-300.0, MIN(300.0, dx)); dy = MAX(-300.0, MIN(300.0, dy));
    tso = MAX(0.0, MIN(1.0, tso)); dso = MAX(0.0, MIN(1.0, dso));
    tsr = MAX(0.0, MIN(40.0, tsr)); dsr = MAX(0.0, MIN(40.0, dsr));

    os_unfair_lock_lock(&NLConfigLock);
    NLTimeEnabled=te; NLDateEnabled=de; NLTimeX=tx; NLTimeY=ty; NLDateX=dx; NLDateY=dy;
    NLTimeColor=tc; NLDateColor=dc;
    NLTimeShadowEnabled=tse; NLDateShadowEnabled=dse;
    NLTimeShadowColor=tsc; NLDateShadowColor=dsc;
    NLTimeShadowOpacity=tso; NLDateShadowOpacity=dso;
    NLTimeShadowRadius=tsr; NLDateShadowRadius=dsr;
    NLTimeShadowX=tsx; NLTimeShadowY=tsy; NLDateShadowX=dsx; NLDateShadowY=dsy;
    NLTimeStyle=tstyle; NLDateStyle=dstyle;
    os_unfair_lock_unlock(&NLConfigLock);
}

static void NLPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                           const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    NLReloadConfig();
}

static void NLApply(id host, BOOL isDate) {
    if (![host isKindOfClass:[UIView class]]) return;
    UIView *view = (UIView *)host;

    BOOL enabled, shadowEnabled;
    CGFloat x,y,opacity,radius,sx,sy;
    NSInteger style;
    UIColor *color, *shadowColor;
    os_unfair_lock_lock(&NLConfigLock);
    enabled = isDate ? NLDateEnabled : NLTimeEnabled;
    x = isDate ? NLDateX : NLTimeX; y = isDate ? NLDateY : NLTimeY;
    color = isDate ? NLDateColor : NLTimeColor;
    shadowEnabled = isDate ? NLDateShadowEnabled : NLTimeShadowEnabled;
    shadowColor = isDate ? NLDateShadowColor : NLTimeShadowColor;
    opacity = isDate ? NLDateShadowOpacity : NLTimeShadowOpacity;
    radius = isDate ? NLDateShadowRadius : NLTimeShadowRadius;
    sx = isDate ? NLDateShadowX : NLTimeShadowX; sy = isDate ? NLDateShadowY : NLTimeShadowY;
    style = isDate ? NLDateStyle : NLTimeStyle;
    os_unfair_lock_unlock(&NLConfigLock);
    if (!enabled) return;

    // Keep NextLock's scale/style matrix, but make X/Y movement authoritative.
    CGAffineTransform tr = view.transform;
    tr.tx = x;
    tr.ty = y;
    view.transform = tr;

    if (color != nil && [host respondsToSelector:@selector(setTextColor:)]) {
        [(UILabel *)host setTextColor:color];
    }

    BOOL styleShadow = (!isDate && style == 6) || (isDate && style == 8);
    BOOL styleGlow = (!isDate && style == 7) || (isDate && style == 9);
    BOOL useShadow = shadowEnabled || styleShadow || styleGlow;
    CALayer *layer = view.layer;
    if (useShadow) {
        UIColor *effective = shadowColor ?: color ?: [UIColor blackColor];
        CGFloat effectiveOpacity = styleGlow ? MAX(opacity, 0.85) : opacity;
        CGFloat effectiveRadius = styleGlow ? MAX(radius, 8.0) : radius;
        CGSize offset = styleGlow ? CGSizeZero : CGSizeMake(sx, sy);
        layer.shadowColor = effective.CGColor;
        layer.shadowOpacity = (float)effectiveOpacity;
        layer.shadowRadius = effectiveRadius;
        layer.shadowOffset = offset;
        layer.masksToBounds = NO;
        if ([host respondsToSelector:@selector(setShadowColor:)]) [(UILabel *)host setShadowColor:effective];
        if ([host respondsToSelector:@selector(setShadowOffset:)]) [(UILabel *)host setShadowOffset:offset];
    } else {
        layer.shadowOpacity = 0.0f;
        if ([host respondsToSelector:@selector(setShadowColor:)]) [(UILabel *)host setShadowColor:nil];
    }
}

static void NLTimeUpdate(id host) {
    if (NLOriginalTimeUpdate) NLOriginalTimeUpdate(host);
    NLApply(host, NO);
}

static void NLDateUpdate(id host) {
    if (NLOriginalDateUpdate) NLOriginalDateUpdate(host);
    NLApply(host, YES);
}

static BOOL NLReadUUID(const struct mach_header *mh, const uint8_t **uuidOut) {
    if (!mh || !uuidOut || mh->magic != MH_MAGIC_64) return NO;
    const struct mach_header_64 *h64 = (const struct mach_header_64 *)mh;
    const uint8_t *cursor = (const uint8_t *)(h64 + 1);
    for (uint32_t i=0; i<h64->ncmds; i++) {
        const struct load_command *lc=(const struct load_command *)cursor;
        if (lc->cmdsize < sizeof(struct load_command)) return NO;
        if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command)) {
            *uuidOut=((const struct uuid_command *)lc)->uuid; return YES;
        }
        cursor += lc->cmdsize;
    }
    return NO;
}

static void NLInstallForImage(const struct mach_header *mh) {
    const uint8_t *uuid=NULL;
    if (!NLReadUUID(mh,&uuid) || memcmp(uuid,kNextLock114Arm64eUUID,16)!=0) return;

    os_unfair_lock_lock(&NLInstallLock);
    if (NLInstalled) { os_unfair_lock_unlock(&NLInstallLock); return; }

    MSHookFunction((void *)((uintptr_t)mh + kTimeUpdateOffset), (void *)&NLTimeUpdate,
                   (void **)&NLOriginalTimeUpdate);
    MSHookFunction((void *)((uintptr_t)mh + kDateUpdateOffset), (void *)&NLDateUpdate,
                   (void **)&NLOriginalDateUpdate);
    NLInstalled = (NLOriginalTimeUpdate != NULL && NLOriginalDateUpdate != NULL);
    os_unfair_lock_unlock(&NLInstallLock);

    if (NLInstalled) NSLog(@"[NextLockFeatureFix] Test11 installed: direct Time/Date position, color, shadow");
}

__attribute__((constructor)) static void NLFeatureFixInit(void) {
    @autoreleasepool {
        NLReloadConfig();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        NLPrefsChanged,
                                        CFSTR("com.nextsolution.lockglyphtime/ReloadPrefs"),
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        _dyld_register_func_for_add_image(NLInstallForImage);
    }
}
