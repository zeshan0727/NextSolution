#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <os/lock.h>
#import <objc/runtime.h>

extern void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result);

static NSString * const NLPrefsDomain = @"com.nextsolution.lockglyphtime";
static const CFStringRef NLPrefsChangedName = CFSTR("com.nextsolution.lockglyphtime/ReloadPrefs");

__attribute__((used)) static const char *NLMarker =
    "NextLockCustomClock 1.1.5-test12 replacement-time-date independent-ui";

static os_unfair_lock NLConfigLock = OS_UNFAIR_LOCK_INIT;

static BOOL NLTimeEnabled = YES;
static BOOL NLDateEnabled = YES;
static CGFloat NLTimeXPercent = 50.0;
static CGFloat NLTimeYPercent = 16.0;
static CGFloat NLDateXPercent = 50.0;
static CGFloat NLDateYPercent = 23.0;
static CGFloat NLTimeScale = 1.0;
static CGFloat NLDateScale = 1.0;
static NSInteger NLTimeWeight = 3;
static NSInteger NLDateWeight = 3;
static NSInteger NLTimeStyle = 0;
static NSInteger NLDateStyle = 0;
static NSString *NLTimeFontName = @"Original";
static NSString *NLDateFontName = @"Original";
static NSString *NLTimeMode = @"system";
static BOOL NLShowSeconds = NO;
static NSString *NLDateFormat = @"system";
static NSString *NLCustomDateFormat = @"EEEE, MMMM d";
static UIColor *NLTimeColor = nil;
static UIColor *NLDateColor = nil;
static BOOL NLTimeShadowEnabled = NO;
static BOOL NLDateShadowEnabled = NO;
static UIColor *NLTimeShadowColor = nil;
static UIColor *NLDateShadowColor = nil;
static CGFloat NLTimeShadowOpacity = 0.45;
static CGFloat NLDateShadowOpacity = 0.45;
static CGFloat NLTimeShadowRadius = 2.0;
static CGFloat NLDateShadowRadius = 2.0;
static CGFloat NLTimeShadowX = 0.0;
static CGFloat NLTimeShadowY = 2.0;
static CGFloat NLDateShadowX = 0.0;
static CGFloat NLDateShadowY = 2.0;

static __weak UIView *NLDateContainer = nil;
static __weak UIView *NLNativeTimeLabel = nil;
static __weak UIView *NLOverlayParent = nil;
static UIView *NLOverlay = nil;
static UILabel *NLCustomTimeLabel = nil;
static UILabel *NLCustomDateLabel = nil;
static dispatch_source_t NLClockTimer = nil;

static void (*NLOrigDateViewLayout)(UIView *, SEL) = NULL;
static void (*NLOrigDateViewDidMove)(UIView *, SEL) = NULL;
static void (*NLOrigSubtitleLayout)(UIView *, SEL) = NULL;
static void (*NLOrigSubtitleDidMove)(UIView *, SEL) = NULL;

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

static double NLCopyDouble(CFStringRef key, double fallback) {
    CFTypeRef value = NLCopyPref(key);
    if (!value) return fallback;
    double result = fallback;
    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &result);
    }
    CFRelease(value);
    return result;
}

static NSInteger NLCopyInteger(CFStringRef key, NSInteger fallback) {
    CFTypeRef value = NLCopyPref(key);
    if (!value) return fallback;
    NSInteger result = fallback;
    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)value, kCFNumberNSIntegerType, &result);
    }
    CFRelease(value);
    return result;
}

static NSString *NLCopyString(CFStringRef key, NSString *fallback) {
    CFTypeRef value = NLCopyPref(key);
    if (!value) return fallback;
    NSString *result = fallback;
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        result = [(__bridge NSString *)value copy];
    }
    CFRelease(value);
    return result;
}

static UIColor *NLColorFromString(NSString *text) {
    if (![text isKindOfClass:[NSString class]]) return nil;
    NSString *s = [[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
    if ([s hasPrefix:@"0X"]) s = [s substringFromIndex:2];

    if (s.length == 6 || s.length == 8) {
        unsigned long long value = 0;
        NSScanner *scanner = [NSScanner scannerWithString:s];
        if ([scanner scanHexLongLong:&value]) {
            CGFloat r, g, b, a;
            if (s.length == 6) {
                r = ((value >> 16) & 0xff) / 255.0;
                g = ((value >> 8) & 0xff) / 255.0;
                b = (value & 0xff) / 255.0;
                a = 1.0;
            } else {
                r = ((value >> 24) & 0xff) / 255.0;
                g = ((value >> 16) & 0xff) / 255.0;
                b = ((value >> 8) & 0xff) / 255.0;
                a = (value & 0xff) / 255.0;
            }
            return [UIColor colorWithRed:r green:g blue:b alpha:a];
        }
    }

    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@",;: "];
    NSArray<NSString *> *parts = [text componentsSeparatedByCharactersInSet:separators];
    NSMutableArray<NSNumber *> *numbers = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length == 0) continue;
        NSScanner *scanner = [NSScanner scannerWithString:part];
        double n = 0;
        if ([scanner scanDouble:&n]) [numbers addObject:@(n)];
    }
    if (numbers.count >= 3) {
        CGFloat r = numbers[0].doubleValue;
        CGFloat g = numbers[1].doubleValue;
        CGFloat b = numbers[2].doubleValue;
        CGFloat a = numbers.count >= 4 ? numbers[3].doubleValue : 1.0;
        if (r > 1 || g > 1 || b > 1 || a > 1) {
            r /= 255.0; g /= 255.0; b /= 255.0;
            if (a > 1) a /= 255.0;
        }
        return [UIColor colorWithRed:MAX(0, MIN(1, r))
                               green:MAX(0, MIN(1, g))
                                blue:MAX(0, MIN(1, b))
                               alpha:MAX(0, MIN(1, a))];
    }
    return nil;
}

static UIColor *NLCopyColor(CFStringRef key) {
    CFTypeRef value = NLCopyPref(key);
    if (!value) return nil;
    UIColor *result = nil;

    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        result = NLColorFromString((__bridge NSString *)value);
    } else if (CFGetTypeID(value) == CFDataGetTypeID()) {
        NSData *data = (__bridge NSData *)value;
        @try {
            NSError *error = nil;
            NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
            if (unarchiver && !error) {
                unarchiver.requiresSecureCoding = NO;
                id object = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
                if ([object isKindOfClass:[UIColor class]]) result = object;
                [unarchiver finishDecoding];
            }
        } @catch (__unused NSException *exception) {}
    }

    CFRelease(value);
    return result;
}

static void NLReloadPrefs(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NLPrefsDomain);

    BOOL timeEnabled = NLCopyBool(CFSTR("customTimeEnabled"), YES);
    BOOL dateEnabled = NLCopyBool(CFSTR("customDateEnabled"), YES);
    CGFloat tx = (CGFloat)NLCopyDouble(CFSTR("customTimeXPercent"), 50.0);
    CGFloat ty = (CGFloat)NLCopyDouble(CFSTR("customTimeYPercent"), 16.0);
    CGFloat dx = (CGFloat)NLCopyDouble(CFSTR("customDateXPercent"), 50.0);
    CGFloat dy = (CGFloat)NLCopyDouble(CFSTR("customDateYPercent"), 23.0);
    CGFloat timeScale = (CGFloat)NLCopyDouble(CFSTR("timeScale"), 1.0);
    CGFloat dateScale = (CGFloat)NLCopyDouble(CFSTR("dateScale"), 1.0);
    NSInteger timeWeight = NLCopyInteger(CFSTR("timeFontWeight"), 3);
    NSInteger dateWeight = NLCopyInteger(CFSTR("dateFontWeight"), 3);
    NSInteger timeStyle = NLCopyInteger(CFSTR("timeStyle"), 0);
    NSInteger dateStyle = NLCopyInteger(CFSTR("dateStyle"), 0);
    NSString *timeFont = NLCopyString(CFSTR("timeFont"), @"Original");
    NSString *dateFont = NLCopyString(CFSTR("dateFont"), @"Original");
    NSString *timeMode = NLCopyString(CFSTR("customClockTimeMode"), @"system");
    BOOL seconds = NLCopyBool(CFSTR("customClockShowSeconds"), NO);
    NSString *dateFormat = NLCopyString(CFSTR("dateFormat"), @"system");
    NSString *customDateFormat = NLCopyString(CFSTR("customDateFormat"), @"EEEE, MMMM d");
    UIColor *timeColor = NLCopyColor(CFSTR("timeColor"));
    UIColor *dateColor = NLCopyColor(CFSTR("dateColor"));
    BOOL timeShadow = NLCopyBool(CFSTR("timeShadowEnabled"), NO);
    BOOL dateShadow = NLCopyBool(CFSTR("dateShadowEnabled"), NO);
    UIColor *timeShadowColor = NLCopyColor(CFSTR("timeShadowColor"));
    UIColor *dateShadowColor = NLCopyColor(CFSTR("dateShadowColor"));
    CGFloat timeShadowOpacity = (CGFloat)NLCopyDouble(CFSTR("timeShadowOpacity"), 0.45);
    CGFloat dateShadowOpacity = (CGFloat)NLCopyDouble(CFSTR("dateShadowOpacity"), 0.45);
    CGFloat timeShadowRadius = (CGFloat)NLCopyDouble(CFSTR("timeShadowRadius"), 2.0);
    CGFloat dateShadowRadius = (CGFloat)NLCopyDouble(CFSTR("dateShadowRadius"), 2.0);
    CGFloat timeShadowX = (CGFloat)NLCopyDouble(CFSTR("timeShadowOffsetX"), 0.0);
    CGFloat timeShadowY = (CGFloat)NLCopyDouble(CFSTR("timeShadowOffsetY"), 2.0);
    CGFloat dateShadowX = (CGFloat)NLCopyDouble(CFSTR("dateShadowOffsetX"), 0.0);
    CGFloat dateShadowY = (CGFloat)NLCopyDouble(CFSTR("dateShadowOffsetY"), 2.0);

    tx = MAX(0, MIN(100, tx)); ty = MAX(0, MIN(100, ty));
    dx = MAX(0, MIN(100, dx)); dy = MAX(0, MIN(100, dy));
    timeScale = MAX(0.3, MIN(3.0, timeScale));
    dateScale = MAX(0.3, MIN(3.0, dateScale));
    timeShadowOpacity = MAX(0, MIN(1, timeShadowOpacity));
    dateShadowOpacity = MAX(0, MIN(1, dateShadowOpacity));
    timeShadowRadius = MAX(0, MIN(40, timeShadowRadius));
    dateShadowRadius = MAX(0, MIN(40, dateShadowRadius));

    os_unfair_lock_lock(&NLConfigLock);
    NLTimeEnabled = timeEnabled; NLDateEnabled = dateEnabled;
    NLTimeXPercent = tx; NLTimeYPercent = ty; NLDateXPercent = dx; NLDateYPercent = dy;
    NLTimeScale = timeScale; NLDateScale = dateScale;
    NLTimeWeight = timeWeight; NLDateWeight = dateWeight;
    NLTimeStyle = timeStyle; NLDateStyle = dateStyle;
    NLTimeFontName = timeFont; NLDateFontName = dateFont;
    NLTimeMode = timeMode; NLShowSeconds = seconds;
    NLDateFormat = dateFormat; NLCustomDateFormat = customDateFormat;
    NLTimeColor = timeColor; NLDateColor = dateColor;
    NLTimeShadowEnabled = timeShadow; NLDateShadowEnabled = dateShadow;
    NLTimeShadowColor = timeShadowColor; NLDateShadowColor = dateShadowColor;
    NLTimeShadowOpacity = timeShadowOpacity; NLDateShadowOpacity = dateShadowOpacity;
    NLTimeShadowRadius = timeShadowRadius; NLDateShadowRadius = dateShadowRadius;
    NLTimeShadowX = timeShadowX; NLTimeShadowY = timeShadowY;
    NLDateShadowX = dateShadowX; NLDateShadowY = dateShadowY;
    os_unfair_lock_unlock(&NLConfigLock);
}

#pragma mark - Formatting

static UIFontWeight NLWeightForIndex(NSInteger index) {
    static const UIFontWeight weights[] = {
        UIFontWeightUltraLight, UIFontWeightThin, UIFontWeightLight,
        UIFontWeightRegular, UIFontWeightMedium, UIFontWeightSemibold,
        UIFontWeightBold, UIFontWeightHeavy, UIFontWeightBlack
    };
    index = MAX(0, MIN(8, index));
    return weights[index];
}

static UIFont *NLFontWithDesign(CGFloat size, UIFontWeight weight, UIFontDescriptorSystemDesign design) {
    UIFont *base = [UIFont systemFontOfSize:size weight:weight];
    UIFontDescriptor *descriptor = [base.fontDescriptor fontDescriptorWithDesign:design];
    return descriptor ? [UIFont fontWithDescriptor:descriptor size:size] : base;
}

static UIFont *NLBuildFont(NSString *fontName, NSInteger weightIndex, NSInteger style, CGFloat size, BOOL isDate) {
    BOOL styleBold = (style == 2 || style == 4);
    BOOL styleItalic = (style == 3 || style == 4);
    UIFontWeight weight = styleBold ? UIFontWeightBold : NLWeightForIndex(weightIndex);
    UIFont *font = nil;

    if ([fontName isEqualToString:@"System Rounded"]) {
        font = NLFontWithDesign(size, weight, UIFontDescriptorSystemDesignRounded);
    } else if ([fontName isEqualToString:@"System Serif / New York"]) {
        font = NLFontWithDesign(size, weight, UIFontDescriptorSystemDesignSerif);
    } else if ([fontName isEqualToString:@"System Monospaced"]) {
        font = [UIFont monospacedSystemFontOfSize:size weight:weight];
    } else if ([fontName isEqualToString:@"Original"] || [fontName isEqualToString:@"System"] || fontName.length == 0) {
        font = isDate ? [UIFont systemFontOfSize:size weight:weight] : NLFontWithDesign(size, weight, UIFontDescriptorSystemDesignRounded);
    } else {
        font = [UIFont fontWithName:fontName size:size];
        if (!font) font = [UIFont systemFontOfSize:size weight:weight];
    }

    UIFontDescriptorSymbolicTraits traits = font.fontDescriptor.symbolicTraits;
    if (styleBold) traits |= UIFontDescriptorTraitBold;
    if (styleItalic) traits |= UIFontDescriptorTraitItalic;
    UIFontDescriptor *styled = [font.fontDescriptor fontDescriptorWithSymbolicTraits:traits];
    if (styled) font = [UIFont fontWithDescriptor:styled size:size];
    return font;
}

static NSString *NLTimeString(NSDate *date, NSString *mode, BOOL showSeconds) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale currentLocale];
    NSString *format = nil;
    if ([mode isEqualToString:@"12"]) {
        format = showSeconds ? @"h:mm:ss" : @"h:mm";
    } else if ([mode isEqualToString:@"24"]) {
        format = showSeconds ? @"HH:mm:ss" : @"HH:mm";
    } else {
        NSString *template = showSeconds ? @"j:mm:ss" : @"j:mm";
        format = [NSDateFormatter dateFormatFromTemplate:template options:0 locale:[NSLocale currentLocale]];
    }
    formatter.dateFormat = format;
    return [formatter stringFromDate:date];
}

static NSString *NLDateString(NSDate *date, NSString *format, NSString *customFormat, NSInteger style) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale currentLocale];
    if ([format isEqualToString:@"custom"]) formatter.dateFormat = customFormat.length ? customFormat : @"EEEE, MMMM d";
    else if ([format isEqualToString:@"system"] || format.length == 0) formatter.dateFormat = @"EEEE, MMMM d";
    else formatter.dateFormat = format;

    NSString *result = [formatter stringFromDate:date];
    if (style == 5) result = result.uppercaseString;
    else if (style == 6) result = result.lowercaseString;
    return result;
}

#pragma mark - Custom labels

static void NLEnsureOverlay(UIView *container) {
    UIView *parent = container.superview;
    if (!parent) return;

    if (NLOverlayParent != parent || !NLOverlay || NLOverlay.superview != parent) {
        [NLOverlay removeFromSuperview];
        NLOverlayParent = parent;
        NLOverlay = [[UIView alloc] initWithFrame:parent.bounds];
        NLOverlay.backgroundColor = UIColor.clearColor;
        NLOverlay.userInteractionEnabled = NO;
        NLOverlay.clipsToBounds = NO;
        NLOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        NLOverlay.layer.zPosition = 900.0;

        NLCustomTimeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        NLCustomDateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        for (UILabel *label in @[NLCustomTimeLabel, NLCustomDateLabel]) {
            label.backgroundColor = UIColor.clearColor;
            label.textAlignment = NSTextAlignmentCenter;
            label.numberOfLines = 1;
            label.userInteractionEnabled = NO;
            label.layer.masksToBounds = NO;
            [NLOverlay addSubview:label];
        }
        [parent addSubview:NLOverlay];
    } else {
        NLOverlay.frame = parent.bounds;
        [parent bringSubviewToFront:NLOverlay];
    }
}

static void NLConfigureShadow(UILabel *label, BOOL enabled, BOOL glow, UIColor *shadowColor,
                              UIColor *fallbackColor, CGFloat opacity, CGFloat radius,
                              CGFloat x, CGFloat y) {
    BOOL active = enabled || glow;
    if (!active) {
        label.layer.shadowOpacity = 0.0f;
        label.shadowColor = nil;
        return;
    }
    UIColor *color = shadowColor ?: fallbackColor ?: UIColor.blackColor;
    label.layer.shadowColor = color.CGColor;
    label.layer.shadowOpacity = (float)(glow ? MAX(opacity, 0.85) : opacity);
    label.layer.shadowRadius = glow ? MAX(radius, 8.0) : radius;
    label.layer.shadowOffset = glow ? CGSizeZero : CGSizeMake(x, y);
    label.layer.masksToBounds = NO;
    label.shadowColor = color;
    label.shadowOffset = glow ? CGSizeZero : CGSizeMake(x, y);
}

static void NLSetStyledText(UILabel *label, NSString *text, UIColor *color, UIFont *font,
                            NSInteger style, BOOL isDate) {
    label.font = font;
    label.textColor = color;

    BOOL outline = (!isDate && style == 5) || (isDate && style == 7);
    if (outline) {
        NSDictionary *attrs = @{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: color,
            NSStrokeColorAttributeName: color,
            NSStrokeWidthAttributeName: @(-2.0)
        };
        label.attributedText = [[NSAttributedString alloc] initWithString:text attributes:attrs];
    } else {
        label.attributedText = nil;
        label.text = text;
    }
}

static void NLPositionLabel(UILabel *label, CGFloat xPercent, CGFloat yPercent, UIView *container) {
    if (!label || !NLOverlay || !container.window) return;
    [label sizeToFit];
    CGRect b = label.bounds;
    b.size.width += 30.0;
    b.size.height += 12.0;
    label.bounds = b;

    UIWindow *window = container.window;
    CGRect wb = window.bounds;
    CGPoint windowPoint = CGPointMake(CGRectGetMinX(wb) + CGRectGetWidth(wb) * (xPercent / 100.0),
                                      CGRectGetMinY(wb) + CGRectGetHeight(wb) * (yPercent / 100.0));
    CGPoint parentPoint = [NLOverlayParent convertPoint:windowPoint fromView:window];
    CGPoint overlayPoint = [NLOverlay convertPoint:parentPoint fromView:NLOverlayParent];
    label.center = overlayPoint;
}

static void NLRefreshCustomClock(void) {
    UIView *container = NLDateContainer;
    if (!container || !container.window) {
        NLOverlay.hidden = YES;
        return;
    }
    NLEnsureOverlay(container);
    NLOverlay.hidden = NO;

    BOOL timeEnabled, dateEnabled, showSeconds, timeShadow, dateShadow;
    CGFloat tx,ty,dx,dy,timeScale,dateScale,timeShadowOpacity,dateShadowOpacity,timeShadowRadius,dateShadowRadius;
    CGFloat timeShadowX,timeShadowY,dateShadowX,dateShadowY;
    NSInteger timeWeight,dateWeight,timeStyle,dateStyle;
    NSString *timeFont,*dateFont,*timeMode,*dateFormat,*customDateFormat;
    UIColor *timeColor,*dateColor,*timeShadowColor,*dateShadowColor;

    os_unfair_lock_lock(&NLConfigLock);
    timeEnabled=NLTimeEnabled; dateEnabled=NLDateEnabled;
    tx=NLTimeXPercent; ty=NLTimeYPercent; dx=NLDateXPercent; dy=NLDateYPercent;
    timeScale=NLTimeScale; dateScale=NLDateScale;
    timeWeight=NLTimeWeight; dateWeight=NLDateWeight;
    timeStyle=NLTimeStyle; dateStyle=NLDateStyle;
    timeFont=NLTimeFontName; dateFont=NLDateFontName;
    timeMode=NLTimeMode; showSeconds=NLShowSeconds;
    dateFormat=NLDateFormat; customDateFormat=NLCustomDateFormat;
    timeColor=NLTimeColor ?: UIColor.whiteColor; dateColor=NLDateColor ?: UIColor.whiteColor;
    timeShadow=NLTimeShadowEnabled; dateShadow=NLDateShadowEnabled;
    timeShadowColor=NLTimeShadowColor; dateShadowColor=NLDateShadowColor;
    timeShadowOpacity=NLTimeShadowOpacity; dateShadowOpacity=NLDateShadowOpacity;
    timeShadowRadius=NLTimeShadowRadius; dateShadowRadius=NLDateShadowRadius;
    timeShadowX=NLTimeShadowX; timeShadowY=NLTimeShadowY;
    dateShadowX=NLDateShadowX; dateShadowY=NLDateShadowY;
    os_unfair_lock_unlock(&NLConfigLock);

    NSDate *now = [NSDate date];
    NLCustomTimeLabel.hidden = !timeEnabled;
    NLCustomDateLabel.hidden = !dateEnabled;

    if (timeEnabled) {
        NSString *text = NLTimeString(now, timeMode, showSeconds);
        UIFont *font = NLBuildFont(timeFont, timeWeight, timeStyle, 82.0 * timeScale, NO);
        NLSetStyledText(NLCustomTimeLabel, text, timeColor, font, timeStyle, NO);
        BOOL styleShadow = timeStyle == 6;
        BOOL styleGlow = timeStyle == 7;
        NLConfigureShadow(NLCustomTimeLabel, timeShadow || styleShadow, styleGlow,
                          timeShadowColor, timeColor, timeShadowOpacity, timeShadowRadius,
                          timeShadowX, timeShadowY);
        NLPositionLabel(NLCustomTimeLabel, tx, ty, container);
    }

    if (dateEnabled) {
        NSString *text = NLDateString(now, dateFormat, customDateFormat, dateStyle);
        UIFont *font = NLBuildFont(dateFont, dateWeight, dateStyle, 20.0 * dateScale, YES);
        NLSetStyledText(NLCustomDateLabel, text, dateColor, font, dateStyle, YES);
        BOOL styleShadow = dateStyle == 8;
        BOOL styleGlow = dateStyle == 9;
        NLConfigureShadow(NLCustomDateLabel, dateShadow || styleShadow, styleGlow,
                          dateShadowColor, dateColor, dateShadowOpacity, dateShadowRadius,
                          dateShadowX, dateShadowY);
        NLPositionLabel(NLCustomDateLabel, dx, dy, container);
    }
}

static void NLHideNativeTime(UIView *container) {
    @try {
        id label = [container valueForKey:@"_timeLabel"];
        if ([label isKindOfClass:[UIView class]]) {
            NLNativeTimeLabel = label;
            ((UIView *)label).hidden = YES;
            ((UIView *)label).alpha = 0.0;
        }
    } @catch (__unused NSException *exception) {}
}

#pragma mark - Hooks

static void NLDateViewLayout(UIView *self, SEL _cmd) {
    if (NLOrigDateViewLayout) NLOrigDateViewLayout(self, _cmd);
    NLDateContainer = self;
    NLHideNativeTime(self);
    NLEnsureOverlay(self);
    NLPositionLabel(NLCustomTimeLabel, NLTimeXPercent, NLTimeYPercent, self);
    NLPositionLabel(NLCustomDateLabel, NLDateXPercent, NLDateYPercent, self);
}

static void NLDateViewDidMove(UIView *self, SEL _cmd) {
    if (NLOrigDateViewDidMove) NLOrigDateViewDidMove(self, _cmd);
    NLDateContainer = self;
    if (self.window) {
        NLHideNativeTime(self);
        NLEnsureOverlay(self);
        NLRefreshCustomClock();
    } else {
        [NLOverlay removeFromSuperview];
        NLOverlay = nil;
        NLCustomTimeLabel = nil;
        NLCustomDateLabel = nil;
        NLOverlayParent = nil;
    }
}

static void NLSubtitleLayout(UIView *self, SEL _cmd) {
    if (NLOrigSubtitleLayout) NLOrigSubtitleLayout(self, _cmd);
    self.hidden = YES;
    self.alpha = 0.0;
}

static void NLSubtitleDidMove(UIView *self, SEL _cmd) {
    if (NLOrigSubtitleDidMove) NLOrigSubtitleDidMove(self, _cmd);
    self.hidden = YES;
    self.alpha = 0.0;
}

static void NLPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                           const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    NLReloadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{
        NLRefreshCustomClock();
    });
}

static void NLStartTimer(void) {
    if (NLClockTimer) return;
    NLClockTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(NLClockTimer,
                              dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                              NSEC_PER_SEC,
                              100 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(NLClockTimer, ^{
        NLRefreshCustomClock();
    });
    dispatch_resume(NLClockTimer);
}

__attribute__((constructor)) static void NLInit(void) {
    @autoreleasepool {
        NLReloadPrefs();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        NLPrefsChanged, NLPrefsChangedName, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        dispatch_async(dispatch_get_main_queue(), ^{
            Class dateView = NSClassFromString(@"SBFLockScreenDateView");
            if (dateView) {
                MSHookMessageEx(dateView, @selector(layoutSubviews), (IMP)NLDateViewLayout,
                                (IMP *)&NLOrigDateViewLayout);
                MSHookMessageEx(dateView, @selector(didMoveToWindow), (IMP)NLDateViewDidMove,
                                (IMP *)&NLOrigDateViewDidMove);
            }

            Class subtitleView = NSClassFromString(@"SBFLockScreenDateSubtitleView");
            if (subtitleView) {
                MSHookMessageEx(subtitleView, @selector(layoutSubviews), (IMP)NLSubtitleLayout,
                                (IMP *)&NLOrigSubtitleLayout);
                MSHookMessageEx(subtitleView, @selector(didMoveToWindow), (IMP)NLSubtitleDidMove,
                                (IMP *)&NLOrigSubtitleDidMove);
            }
            NLStartTimer();
            NSLog(@"[NextLockCustomClock] Test12 loaded: native time/date text replaced by independent custom labels");
        });
    }
}
