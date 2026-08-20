#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

extern void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result);

static CFStringRef const NLPrefsDomain = CFSTR("com.nextsolution.lockglyphtime");
static CFStringRef const NLPrefsChangedName = CFSTR("com.nextsolution.lockglyphtime/ReloadPrefs");

__attribute__((used)) static const char *NLBatteryMarker =
    "NextLockBatteryItems 1.1.5-test18 movable-percent-icon full-photo-migration";

static BOOL NLShowBatteryPercent = NO;
static BOOL NLShowBatteryIcon = NO;
static CGFloat NLBatteryPercentX = 50.0;
static CGFloat NLBatteryPercentY = 27.0;
static CGFloat NLBatteryPercentSize = 18.0;
static CGFloat NLBatteryIconX = 62.0;
static CGFloat NLBatteryIconY = 27.0;
static CGFloat NLBatteryIconScale = 1.0;

static __weak UIView *NLDateContainer = nil;
static __weak UIView *NLOverlayParent = nil;
static UIView *NLBatteryOverlay = nil;
static UILabel *NLBatteryPercentLabel = nil;

static void (*NLOrigDateLayout)(UIView *, SEL) = NULL;
static void (*NLOrigDateDidMove)(UIView *, SEL) = NULL;

static BOOL NLCopyBool(CFStringRef key, BOOL fallback) {
    CFTypeRef value = CFPreferencesCopyAppValue(key, NLPrefsDomain);
    if (!value) return fallback;
    BOOL result = fallback;
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
        result = CFBooleanGetValue((CFBooleanRef)value);
    } else if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        int n = 0;
        CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &n);
        result = (n != 0);
    }
    CFRelease(value);
    return result;
}

static CGFloat NLCopyCGFloat(CFStringRef key, CGFloat fallback) {
    CFTypeRef value = CFPreferencesCopyAppValue(key, NLPrefsDomain);
    if (!value) return fallback;
    double result = fallback;
    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &result);
    }
    CFRelease(value);
    return (CGFloat)result;
}

static CGFloat NLClamp(CGFloat v, CGFloat lo, CGFloat hi) {
    return MAX(lo, MIN(hi, v));
}

static void NLReloadPrefs(void) {
    CFPreferencesAppSynchronize(NLPrefsDomain);
    NLShowBatteryPercent = NLCopyBool(CFSTR("customBatteryPercentEnabled"), NO);
    NLShowBatteryIcon = NLCopyBool(CFSTR("customBatteryIconEnabled"), NO);
    NLBatteryPercentX = NLClamp(NLCopyCGFloat(CFSTR("customBatteryPercentXPercent"), 50.0), 0.0, 100.0);
    NLBatteryPercentY = NLClamp(NLCopyCGFloat(CFSTR("customBatteryPercentYPercent"), 27.0), 0.0, 100.0);
    NLBatteryPercentSize = NLClamp(NLCopyCGFloat(CFSTR("customBatteryPercentSize"), 18.0), 10.0, 60.0);
    NLBatteryIconX = NLClamp(NLCopyCGFloat(CFSTR("customBatteryIconXPercent"), 62.0), 0.0, 100.0);
    NLBatteryIconY = NLClamp(NLCopyCGFloat(CFSTR("customBatteryIconYPercent"), 27.0), 0.0, 100.0);
    NLBatteryIconScale = NLClamp(NLCopyCGFloat(CFSTR("customBatteryIconScale"), 1.0), 0.5, 3.0);
}

static void NLRunFullPhotoMigrationIfNeeded(void) {
    if (NLCopyBool(CFSTR("test18FullPhotoMigrationDone"), NO)) return;

    for (NSUInteger i = 1; i <= 4; i++) {
        CFStringRef key = CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
                                                   CFSTR("photoFrame%luContentMode"),
                                                   (unsigned long)i);
        NSNumber *fullPhoto = @2;
        CFPreferencesSetAppValue(key, (__bridge CFPropertyListRef)fullPhoto, NLPrefsDomain);
        CFRelease(key);
    }
    CFPreferencesSetAppValue(CFSTR("test18FullPhotoMigrationDone"),
                             kCFBooleanTrue, NLPrefsDomain);
    CFPreferencesAppSynchronize(NLPrefsDomain);
}

@interface NLBatteryIconView : UIView
@property (nonatomic) CGFloat batteryLevel;
@property (nonatomic) BOOL charging;
@end

@implementation NLBatteryIconView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        _batteryLevel = 0.5;
    }
    return self;
}

- (void)setBatteryLevel:(CGFloat)batteryLevel {
    _batteryLevel = NLClamp(batteryLevel, 0.0, 1.0);
    [self setNeedsDisplay];
}

- (void)setCharging:(BOOL)charging {
    _charging = charging;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    UIColor *color = UIColor.whiteColor;
    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat h = CGRectGetHeight(self.bounds);
    CGFloat terminalW = MAX(2.0, w * 0.07);
    CGFloat bodyW = MAX(8.0, w - terminalW - 2.0);
    CGRect body = CGRectMake(1.0, 1.0, bodyW - 2.0, h - 2.0);
    CGFloat radius = MAX(2.0, h * 0.20);

    CGContextSetStrokeColorWithColor(ctx, color.CGColor);
    CGContextSetLineWidth(ctx, MAX(1.4, h * 0.09));
    UIBezierPath *outline = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:radius];
    [outline stroke];

    CGRect terminal = CGRectMake(CGRectGetMaxX(body) + 1.0,
                                 CGRectGetMidY(body) - h * 0.16,
                                 terminalW,
                                 h * 0.32);
    UIBezierPath *terminalPath = [UIBezierPath bezierPathWithRoundedRect:terminal
                                                            cornerRadius:terminalW * 0.45];
    [color setFill];
    [terminalPath fill];

    CGRect inner = CGRectInset(body, MAX(2.0, h * 0.16), MAX(2.0, h * 0.16));
    CGFloat fillW = CGRectGetWidth(inner) * self.batteryLevel;
    if (fillW > 0.4) {
        CGRect fillRect = inner;
        fillRect.size.width = fillW;
        UIBezierPath *fillPath = [UIBezierPath bezierPathWithRoundedRect:fillRect
                                                            cornerRadius:MAX(1.0, CGRectGetHeight(inner) * 0.20)];
        [fillPath fill];
    }

    if (self.charging && w >= 24.0 && h >= 12.0) {
        CGFloat cx = CGRectGetMidX(body);
        CGFloat cy = CGRectGetMidY(body);
        UIBezierPath *bolt = [UIBezierPath bezierPath];
        [bolt moveToPoint:CGPointMake(cx + h * 0.05, cy - h * 0.28)];
        [bolt addLineToPoint:CGPointMake(cx - h * 0.12, cy + h * 0.02)];
        [bolt addLineToPoint:CGPointMake(cx, cy + h * 0.02)];
        [bolt addLineToPoint:CGPointMake(cx - h * 0.05, cy + h * 0.29)];
        [bolt addLineToPoint:CGPointMake(cx + h * 0.15, cy - h * 0.05)];
        [bolt addLineToPoint:CGPointMake(cx + h * 0.03, cy - h * 0.05)];
        [bolt closePath];
        [UIColor.blackColor setFill];
        [bolt fill];
    }
}
@end

static NLBatteryIconView *NLBatteryIcon = nil;

static CGPoint NLPointForPercent(CGFloat xPercent, CGFloat yPercent) {
    if (!NLBatteryOverlay || !NLBatteryOverlay.window) return CGPointZero;
    UIWindow *window = NLBatteryOverlay.window;
    CGRect bounds = window.bounds;
    CGPoint pointInWindow = CGPointMake(CGRectGetMinX(bounds) + CGRectGetWidth(bounds) * (xPercent / 100.0),
                                        CGRectGetMinY(bounds) + CGRectGetHeight(bounds) * (yPercent / 100.0));
    return [NLBatteryOverlay convertPoint:pointInWindow fromView:window];
}

static void NLEnsureBatteryOverlay(UIView *dateView) {
    UIView *parent = dateView.superview;
    if (!parent) return;

    if (NLOverlayParent != parent || !NLBatteryOverlay || NLBatteryOverlay.superview != parent) {
        [NLBatteryOverlay removeFromSuperview];
        NLBatteryOverlay = [[UIView alloc] initWithFrame:parent.bounds];
        NLBatteryOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        NLBatteryOverlay.backgroundColor = UIColor.clearColor;
        NLBatteryOverlay.userInteractionEnabled = NO;
        NLBatteryOverlay.layer.zPosition = 950.0;
        [parent addSubview:NLBatteryOverlay];
        NLOverlayParent = parent;

        NLBatteryPercentLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        NLBatteryPercentLabel.backgroundColor = UIColor.clearColor;
        NLBatteryPercentLabel.textColor = UIColor.whiteColor;
        NLBatteryPercentLabel.textAlignment = NSTextAlignmentCenter;
        NLBatteryPercentLabel.userInteractionEnabled = NO;
        [NLBatteryOverlay addSubview:NLBatteryPercentLabel];

        NLBatteryIcon = [[NLBatteryIconView alloc] initWithFrame:CGRectZero];
        [NLBatteryOverlay addSubview:NLBatteryIcon];
    }
}

static void NLUpdateBatteryData(void) {
    UIDevice *device = UIDevice.currentDevice;
    CGFloat level = device.batteryLevel;
    if (level < 0.0 || level > 1.0) level = 0.0;
    NSInteger percent = (NSInteger)lrint(level * 100.0);
    UIDeviceBatteryState state = device.batteryState;
    BOOL charging = (state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull);

    NLBatteryPercentLabel.text = [NSString stringWithFormat:@"%ld%%", (long)percent];
    NLBatteryIcon.batteryLevel = level;
    NLBatteryIcon.charging = charging;
}

static void NLApplyBatteryLayout(void) {
    if (!NLBatteryOverlay) return;

    NLBatteryPercentLabel.hidden = !NLShowBatteryPercent;
    NLBatteryIcon.hidden = !NLShowBatteryIcon;

    if (NLShowBatteryPercent) {
        NLBatteryPercentLabel.font = [UIFont systemFontOfSize:NLBatteryPercentSize weight:UIFontWeightSemibold];
        [NLBatteryPercentLabel sizeToFit];
        CGRect b = NLBatteryPercentLabel.bounds;
        b.size.width += 16.0;
        b.size.height += 8.0;
        NLBatteryPercentLabel.bounds = b;
        NLBatteryPercentLabel.center = NLPointForPercent(NLBatteryPercentX, NLBatteryPercentY);
    }

    if (NLShowBatteryIcon) {
        CGSize size = CGSizeMake(42.0 * NLBatteryIconScale, 20.0 * NLBatteryIconScale);
        NLBatteryIcon.bounds = (CGRect){CGPointZero, size};
        NLBatteryIcon.center = NLPointForPercent(NLBatteryIconX, NLBatteryIconY);
        [NLBatteryIcon setNeedsDisplay];
    }
}

static void NLRefreshBatteryItems(void) {
    UIView *container = NLDateContainer;
    if (!container || !container.window) {
        NLBatteryOverlay.hidden = YES;
        return;
    }
    NLEnsureBatteryOverlay(container);
    NLBatteryOverlay.hidden = NO;
    NLUpdateBatteryData();
    NLApplyBatteryLayout();
}

static void NLDateLayout(UIView *self, SEL _cmd) {
    if (NLOrigDateLayout) NLOrigDateLayout(self, _cmd);
    NLDateContainer = self;
    NLEnsureBatteryOverlay(self);
    NLRefreshBatteryItems();
}

static void NLDateDidMove(UIView *self, SEL _cmd) {
    if (NLOrigDateDidMove) NLOrigDateDidMove(self, _cmd);
    NLDateContainer = self;
    if (self.window) {
        NLEnsureBatteryOverlay(self);
        NLRefreshBatteryItems();
    } else {
        [NLBatteryOverlay removeFromSuperview];
        NLBatteryOverlay = nil;
        NLBatteryPercentLabel = nil;
        NLBatteryIcon = nil;
        NLOverlayParent = nil;
    }
}

static void NLPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                           const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    NLReloadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{
        NLRefreshBatteryItems();
    });
}

static void NLHookIfAvailable(NSString *className, NSString *selectorName, IMP replacement, IMP *original) {
    Class cls = NSClassFromString(className);
    SEL sel = NSSelectorFromString(selectorName);
    if (!cls || !class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, replacement, original);
}

__attribute__((constructor)) static void NLBatteryInit(void) {
    @autoreleasepool {
        NLReloadPrefs();
        NLRunFullPhotoMigrationIfNeeded();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        NLPrefsChanged, NLPrefsChangedName, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        dispatch_async(dispatch_get_main_queue(), ^{
            UIDevice.currentDevice.batteryMonitoringEnabled = YES;
            NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
            [nc addObserverForName:UIDeviceBatteryLevelDidChangeNotification
                            object:nil queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification *note) { NLRefreshBatteryItems(); }];
            [nc addObserverForName:UIDeviceBatteryStateDidChangeNotification
                            object:nil queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification *note) { NLRefreshBatteryItems(); }];

            NLHookIfAvailable(@"SBFLockScreenDateView", @"layoutSubviews",
                              (IMP)NLDateLayout, (IMP *)&NLOrigDateLayout);
            NLHookIfAvailable(@"SBFLockScreenDateView", @"didMoveToWindow",
                              (IMP)NLDateDidMove, (IMP *)&NLOrigDateDidMove);

            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 NLPrefsChangedName, NULL, NULL, true);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC),
                           dispatch_get_main_queue(), ^{
                CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                     NLPrefsChangedName, NULL, NULL, true);
                NLRefreshBatteryItems();
            });
            NSLog(@"[NextLockBatteryItems] Test18 loaded: movable battery percentage/icon + full-photo migration");
        });
    }
}
