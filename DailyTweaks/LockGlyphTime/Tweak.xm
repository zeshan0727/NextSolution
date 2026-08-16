#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString * const LGTPrefsDomain = @"com.nextsolution.lockglyphtime";
static CFStringRef const LGTReloadNotification = CFSTR("com.nextsolution.lockglyphtime/ReloadPrefs");
static const void *LGTIconAssociationKey = &LGTIconAssociationKey;
static const void *LGTLabelStateAssociationKey = &LGTLabelStateAssociationKey;

@interface LGTLabelState : NSObject
@property(nonatomic, assign) CGAffineTransform transform;
@property(nonatomic, strong) UIFont *font;
@property(nonatomic, strong) UIColor *textColor;
@property(nonatomic, assign) NSTextAlignment textAlignment;
@property(nonatomic, strong) UIColor *shadowColor;
@property(nonatomic, assign) CGSize shadowOffset;
@property(nonatomic, strong) UIColor *layerShadowColor;
@property(nonatomic, assign) float layerShadowOpacity;
@property(nonatomic, assign) CGFloat layerShadowRadius;
@property(nonatomic, assign) CGSize layerShadowOffset;
@end

@implementation LGTLabelState
@end

static BOOL gEnabled = YES;

// Time
static BOOL gCustomTimeEnabled = YES;
static CGFloat gTimeScale = 1.0;
static NSString *gTimeColor = @"#FFFFFF";
static CGFloat gTimeOffsetX = 0.0;
static CGFloat gTimeOffsetY = 0.0;
static NSInteger gTimeAlignment = 0;
static NSString *gTimeFont = @"Original";
static NSInteger gTimeFontWeight = 3;
static NSInteger gTimeStyle = 0;
static BOOL gTimeShadowEnabled = NO;
static NSString *gTimeShadowColor = @"#000000";
static CGFloat gTimeShadowOpacity = 0.45;
static CGFloat gTimeShadowRadius = 2.0;
static CGFloat gTimeShadowOffsetX = 0.0;
static CGFloat gTimeShadowOffsetY = 1.0;

// Date
static BOOL gCustomDateEnabled = YES;
static CGFloat gDateScale = 1.0;
static NSString *gDateColor = @"#FFFFFF";
static CGFloat gDateOffsetX = 0.0;
static CGFloat gDateOffsetY = 0.0;
static NSInteger gDateAlignment = 0;
static NSString *gDateFont = @"Original";
static NSInteger gDateFontWeight = 3;
static NSInteger gDateStyle = 0;
static NSString *gDateFormat = @"system";
static NSString *gCustomDateFormat = @"EEEE, MMMM d";
static BOOL gDateShadowEnabled = NO;
static NSString *gDateShadowColor = @"#000000";
static CGFloat gDateShadowOpacity = 0.45;
static CGFloat gDateShadowRadius = 2.0;
static CGFloat gDateShadowOffsetX = 0.0;
static CGFloat gDateShadowOffsetY = 1.0;

// Icon (backward-compatible preference keys)
static BOOL gIconEnabled = YES;
static NSString *gIconName = @"sparkles";
static CGFloat gIconSize = 22.0;
static NSString *gIconColor = @"#FFFFFF";
static NSInteger gAnchorTarget = 0; // 0 = time, 1 = date
static NSInteger gIconPosition = 1; // 0 left, 1 right, 2 above, 3 below
static CGFloat gIconOffsetX = 0.0;
static CGFloat gIconOffsetY = 0.0;
static BOOL gShadowEnabled = YES;
static NSString *gShadowColor = @"#000000";
static CGFloat gShadowOpacity = 0.45;
static CGFloat gShadowRadius = 2.0;
static CGFloat gShadowOffsetX = 0.0;
static CGFloat gShadowOffsetY = 1.0;

static UIColor *gTimeUIColor = nil;
static UIColor *gDateUIColor = nil;
static UIColor *gTimeShadowUIColor = nil;
static UIColor *gDateShadowUIColor = nil;
static UIColor *gIconUIColor = nil;
static UIColor *gIconShadowUIColor = nil;
static NSDateFormatter *gDateFormatter = nil;
static NSMutableDictionary<NSString *, UIFont *> *gFontCache = nil;
static NSHashTable<UIView *> *gKnownContainers = nil;

static CGFloat LGTClamped(CGFloat value, CGFloat minValue, CGFloat maxValue) {
    return MAX(minValue, MIN(maxValue, value));
}

static UIColor *LGTColorFromHex(NSString *hex, UIColor *fallback) {
    if (![hex isKindOfClass:NSString.class]) return fallback;
    NSString *clean = [[hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([clean hasPrefix:@"#"]) clean = [clean substringFromIndex:1];

    if (clean.length == 3) {
        unichar r = [clean characterAtIndex:0];
        unichar g = [clean characterAtIndex:1];
        unichar b = [clean characterAtIndex:2];
        clean = [NSString stringWithFormat:@"%C%C%C%C%C%C", r, r, g, g, b, b];
    }

    if (clean.length != 6 && clean.length != 8) return fallback;

    unsigned long long value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexLongLong:&value] || !scanner.isAtEnd) return fallback;

    CGFloat alpha = 1.0;
    CGFloat red = 0.0, green = 0.0, blue = 0.0;
    if (clean.length == 8) {
        red = ((value >> 24) & 0xFF) / 255.0;
        green = ((value >> 16) & 0xFF) / 255.0;
        blue = ((value >> 8) & 0xFF) / 255.0;
        alpha = (value & 0xFF) / 255.0;
    } else {
        red = ((value >> 16) & 0xFF) / 255.0;
        green = ((value >> 8) & 0xFF) / 255.0;
        blue = (value & 0xFF) / 255.0;
    }

    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

static UIFontWeight LGTWeightForValue(NSInteger value) {
    switch (value) {
        case 0: return UIFontWeightUltraLight;
        case 1: return UIFontWeightThin;
        case 2: return UIFontWeightLight;
        case 4: return UIFontWeightMedium;
        case 5: return UIFontWeightSemibold;
        case 6: return UIFontWeightBold;
        case 7: return UIFontWeightHeavy;
        case 8: return UIFontWeightBlack;
        default: return UIFontWeightRegular;
    }
}

static UIFontDescriptorSymbolicTraits LGTStyleTraits(NSInteger style) {
    switch (style) {
        case 2: return UIFontDescriptorTraitBold;
        case 3: return UIFontDescriptorTraitItalic;
        case 4: return (UIFontDescriptorTraitBold | UIFontDescriptorTraitItalic);
        default: return 0;
    }
}

static BOOL LGTUsesSystemFamily(NSString *name) {
    return [name isEqualToString:@"System"] ||
           [name isEqualToString:@"System Rounded"] ||
           [name isEqualToString:@"System Serif / New York"] ||
           [name isEqualToString:@"System Monospaced"];
}

static UIFont *LGTSafeFont(NSString *fontName,
                           CGFloat size,
                           NSInteger weightValue,
                           NSInteger style,
                           UIFont *fallbackFont) {
    if (!fallbackFont) fallbackFont = [UIFont systemFontOfSize:MAX(size, 12.0)];
    size = MAX(1.0, size);

    NSString *name = fontName.length ? fontName : @"Original";
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%.2f|%ld|%ld|%@",
                          name, size, (long)weightValue, (long)style, fallbackFont.fontName ?: @"fallback"];
    UIFont *cached = gFontCache[cacheKey];
    if (cached) return cached;

    UIFont *font = nil;
    UIFontDescriptorSymbolicTraits styleTraits = LGTStyleTraits(style);

    if ([name isEqualToString:@"Original"]) {
        font = fallbackFont;
    } else if (LGTUsesSystemFamily(name)) {
        UIFont *base = [UIFont systemFontOfSize:size weight:LGTWeightForValue(weightValue)];
        UIFontDescriptor *descriptor = base.fontDescriptor;

        if ([name isEqualToString:@"System Rounded"]) {
            UIFontDescriptor *designed = [descriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
            if (designed) descriptor = designed;
        } else if ([name isEqualToString:@"System Serif / New York"]) {
            UIFontDescriptor *designed = [descriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignSerif];
            if (designed) descriptor = designed;
        } else if ([name isEqualToString:@"System Monospaced"]) {
            UIFontDescriptor *designed = [descriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignMonospaced];
            if (designed) descriptor = designed;
        }

        if (styleTraits != 0) {
            UIFontDescriptor *styled = [descriptor fontDescriptorWithSymbolicTraits:(descriptor.symbolicTraits | styleTraits)];
            if (styled) descriptor = styled;
        }
        font = [UIFont fontWithDescriptor:descriptor size:size];
    } else {
        font = [UIFont fontWithName:name size:size];
        if (font && styleTraits != 0) {
            UIFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorWithSymbolicTraits:(font.fontDescriptor.symbolicTraits | styleTraits)];
            if (descriptor) {
                UIFont *styled = [UIFont fontWithDescriptor:descriptor size:size];
                if (styled) font = styled;
            }
        }
    }

    if (!font) font = fallbackFont;
    if (font) gFontCache[cacheKey] = font;
    return font;
}

static NSTextAlignment LGTAlignmentForValue(NSInteger value, NSTextAlignment fallback) {
    switch (value) {
        case 1: return NSTextAlignmentLeft;
        case 2: return NSTextAlignmentCenter;
        case 3: return NSTextAlignmentRight;
        default: return fallback;
    }
}

static LGTLabelState *LGTStateForLabel(UILabel *label) {
    if (!label) return nil;
    LGTLabelState *state = objc_getAssociatedObject(label, LGTLabelStateAssociationKey);
    if (!state) {
        state = [LGTLabelState new];
        state.transform = label.transform;
        state.font = label.font ?: [UIFont systemFontOfSize:17.0];
        state.textColor = label.textColor ?: UIColor.whiteColor;
        state.textAlignment = label.textAlignment;
        state.shadowColor = label.shadowColor;
        state.shadowOffset = label.shadowOffset;
        state.layerShadowColor = label.layer.shadowColor ? [UIColor colorWithCGColor:label.layer.shadowColor] : nil;
        state.layerShadowOpacity = label.layer.shadowOpacity;
        state.layerShadowRadius = label.layer.shadowRadius;
        state.layerShadowOffset = label.layer.shadowOffset;
        objc_setAssociatedObject(label, LGTLabelStateAssociationKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static void LGTRestoreLabel(UILabel *label, LGTLabelState *state) {
    if (!label || !state) return;
    NSString *currentText = label.text ?: @"";
    label.attributedText = nil;
    label.text = currentText;
    label.transform = state.transform;
    label.font = state.font;
    label.textColor = state.textColor;
    label.textAlignment = state.textAlignment;
    label.shadowColor = state.shadowColor;
    label.shadowOffset = state.shadowOffset;
    label.layer.shadowColor = state.layerShadowColor.CGColor;
    label.layer.shadowOpacity = state.layerShadowOpacity;
    label.layer.shadowRadius = state.layerShadowRadius;
    label.layer.shadowOffset = state.layerShadowOffset;
    label.layer.masksToBounds = NO;
}

static void LGTConfigureDateFormatter(void) {
    gDateFormatter = nil;
    if ([gDateFormat isEqualToString:@"system"]) return;

    NSString *format = gDateFormat;
    if ([gDateFormat isEqualToString:@"custom"]) {
        format = gCustomDateFormat.length ? gCustomDateFormat : @"EEEE, MMMM d";
    }

    if (!format.length) return;

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = NSLocale.currentLocale;
    formatter.calendar = NSCalendar.currentCalendar;
    formatter.timeZone = NSTimeZone.localTimeZone;
    formatter.dateFormat = format;
    gDateFormatter = formatter;
}

static void LGTRequestRelayout(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIView *view in gKnownContainers.allObjects) {
            [view setNeedsLayout];
            [view layoutIfNeeded];
        }
    });
}

static void LGTLoadPrefs(void) {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain];
    id value = nil;
    NSString *stringValue = nil;

    value = [prefs objectForKey:@"enabled"];
    gEnabled = value ? [value boolValue] : YES;

    // Time
    value = [prefs objectForKey:@"customTimeEnabled"];
    gCustomTimeEnabled = value ? [value boolValue] : YES;
    value = [prefs objectForKey:@"timeScale"];
    gTimeScale = LGTClamped(value ? [value doubleValue] : 1.0, 0.50, 2.50);
    stringValue = [prefs stringForKey:@"timeColor"];
    gTimeColor = stringValue.length ? stringValue : @"#FFFFFF";
    value = [prefs objectForKey:@"timeOffsetX"];
    gTimeOffsetX = LGTClamped(value ? [value doubleValue] : 0.0, -150.0, 150.0);
    value = [prefs objectForKey:@"timeOffsetY"];
    gTimeOffsetY = LGTClamped(value ? [value doubleValue] : 0.0, -150.0, 150.0);
    value = [prefs objectForKey:@"timeAlignment"];
    gTimeAlignment = value ? [value integerValue] : 0;
    stringValue = [prefs stringForKey:@"timeFont"];
    gTimeFont = stringValue.length ? stringValue : @"Original";
    value = [prefs objectForKey:@"timeFontWeight"];
    gTimeFontWeight = value ? [value integerValue] : 3;
    value = [prefs objectForKey:@"timeStyle"];
    gTimeStyle = value ? [value integerValue] : 0;
    value = [prefs objectForKey:@"timeShadowEnabled"];
    gTimeShadowEnabled = value ? [value boolValue] : NO;
    stringValue = [prefs stringForKey:@"timeShadowColor"];
    gTimeShadowColor = stringValue.length ? stringValue : @"#000000";
    value = [prefs objectForKey:@"timeShadowOpacity"];
    gTimeShadowOpacity = LGTClamped(value ? [value doubleValue] : 0.45, 0.0, 1.0);
    value = [prefs objectForKey:@"timeShadowRadius"];
    gTimeShadowRadius = LGTClamped(value ? [value doubleValue] : 2.0, 0.0, 20.0);
    value = [prefs objectForKey:@"timeShadowOffsetX"];
    gTimeShadowOffsetX = LGTClamped(value ? [value doubleValue] : 0.0, -20.0, 20.0);
    value = [prefs objectForKey:@"timeShadowOffsetY"];
    gTimeShadowOffsetY = LGTClamped(value ? [value doubleValue] : 1.0, -20.0, 20.0);

    // Date
    value = [prefs objectForKey:@"customDateEnabled"];
    gCustomDateEnabled = value ? [value boolValue] : YES;
    value = [prefs objectForKey:@"dateScale"];
    gDateScale = LGTClamped(value ? [value doubleValue] : 1.0, 0.50, 2.50);
    stringValue = [prefs stringForKey:@"dateColor"];
    gDateColor = stringValue.length ? stringValue : @"#FFFFFF";
    value = [prefs objectForKey:@"dateOffsetX"];
    gDateOffsetX = LGTClamped(value ? [value doubleValue] : 0.0, -150.0, 150.0);
    value = [prefs objectForKey:@"dateOffsetY"];
    gDateOffsetY = LGTClamped(value ? [value doubleValue] : 0.0, -150.0, 150.0);
    value = [prefs objectForKey:@"dateAlignment"];
    gDateAlignment = value ? [value integerValue] : 0;
    stringValue = [prefs stringForKey:@"dateFont"];
    gDateFont = stringValue.length ? stringValue : @"Original";
    value = [prefs objectForKey:@"dateFontWeight"];
    gDateFontWeight = value ? [value integerValue] : 3;
    value = [prefs objectForKey:@"dateStyle"];
    gDateStyle = value ? [value integerValue] : 0;
    stringValue = [prefs stringForKey:@"dateFormat"];
    gDateFormat = stringValue.length ? stringValue : @"system";
    stringValue = [prefs stringForKey:@"customDateFormat"];
    gCustomDateFormat = stringValue.length ? stringValue : @"EEEE, MMMM d";
    value = [prefs objectForKey:@"dateShadowEnabled"];
    gDateShadowEnabled = value ? [value boolValue] : NO;
    stringValue = [prefs stringForKey:@"dateShadowColor"];
    gDateShadowColor = stringValue.length ? stringValue : @"#000000";
    value = [prefs objectForKey:@"dateShadowOpacity"];
    gDateShadowOpacity = LGTClamped(value ? [value doubleValue] : 0.45, 0.0, 1.0);
    value = [prefs objectForKey:@"dateShadowRadius"];
    gDateShadowRadius = LGTClamped(value ? [value doubleValue] : 2.0, 0.0, 20.0);
    value = [prefs objectForKey:@"dateShadowOffsetX"];
    gDateShadowOffsetX = LGTClamped(value ? [value doubleValue] : 0.0, -20.0, 20.0);
    value = [prefs objectForKey:@"dateShadowOffsetY"];
    gDateShadowOffsetY = LGTClamped(value ? [value doubleValue] : 1.0, -20.0, 20.0);

    // Icon (existing keys preserved)
    value = [prefs objectForKey:@"iconEnabled"];
    gIconEnabled = value ? [value boolValue] : YES;
    stringValue = [prefs stringForKey:@"iconName"];
    gIconName = stringValue.length ? stringValue : @"sparkles";
    value = [prefs objectForKey:@"iconSize"];
    gIconSize = LGTClamped(value ? [value doubleValue] : 22.0, 10.0, 80.0);
    stringValue = [prefs stringForKey:@"iconColor"];
    gIconColor = stringValue.length ? stringValue : @"#FFFFFF";
    value = [prefs objectForKey:@"anchorTarget"];
    gAnchorTarget = value ? [value integerValue] : 0;
    value = [prefs objectForKey:@"iconPosition"];
    gIconPosition = value ? [value integerValue] : 1;
    value = [prefs objectForKey:@"iconOffsetX"];
    gIconOffsetX = LGTClamped(value ? [value doubleValue] : 0.0, -120.0, 120.0);
    value = [prefs objectForKey:@"iconOffsetY"];
    gIconOffsetY = LGTClamped(value ? [value doubleValue] : 0.0, -120.0, 120.0);
    value = [prefs objectForKey:@"shadowEnabled"];
    gShadowEnabled = value ? [value boolValue] : YES;
    stringValue = [prefs stringForKey:@"shadowColor"];
    gShadowColor = stringValue.length ? stringValue : @"#000000";
    value = [prefs objectForKey:@"shadowOpacity"];
    gShadowOpacity = LGTClamped(value ? [value doubleValue] : 0.45, 0.0, 1.0);
    value = [prefs objectForKey:@"shadowRadius"];
    gShadowRadius = LGTClamped(value ? [value doubleValue] : 2.0, 0.0, 20.0);
    value = [prefs objectForKey:@"shadowOffsetX"];
    gShadowOffsetX = LGTClamped(value ? [value doubleValue] : 0.0, -20.0, 20.0);
    value = [prefs objectForKey:@"shadowOffsetY"];
    gShadowOffsetY = LGTClamped(value ? [value doubleValue] : 1.0, -20.0, 20.0);

    [gFontCache removeAllObjects];
    gTimeUIColor = LGTColorFromHex(gTimeColor, UIColor.whiteColor);
    gDateUIColor = LGTColorFromHex(gDateColor, UIColor.whiteColor);
    gTimeShadowUIColor = LGTColorFromHex(gTimeShadowColor, UIColor.blackColor);
    gDateShadowUIColor = LGTColorFromHex(gDateShadowColor, UIColor.blackColor);
    gIconUIColor = LGTColorFromHex(gIconColor, UIColor.whiteColor);
    gIconShadowUIColor = LGTColorFromHex(gShadowColor, UIColor.blackColor);
    LGTConfigureDateFormatter();
}

static void LGTReloadCallback(CFNotificationCenterRef center,
                              void *observer,
                              CFStringRef name,
                              const void *object,
                              CFDictionaryRef userInfo) {
    LGTLoadPrefs();
    LGTRequestRelayout();
}

static void LGTCollectLabels(UIView *view, NSMutableArray<UILabel *> *labels) {
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        if ((label.text.length > 0 || label.attributedText.length > 0) && label.font.pointSize > 0.0 && !label.hidden) {
            [labels addObject:label];
        }
    }
    for (UIView *subview in view.subviews) {
        LGTCollectLabels(subview, labels);
    }
}

static NSString *LGTSearchProbeForLabel(UILabel *label) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (label.accessibilityIdentifier.length) [parts addObject:label.accessibilityIdentifier];
    if (label.accessibilityLabel.length) [parts addObject:label.accessibilityLabel];
    [parts addObject:NSStringFromClass(label.class)];
    if (label.superview) [parts addObject:NSStringFromClass(label.superview.class)];
    return [[parts componentsJoinedByString:@" "] lowercaseString];
}

static NSInteger LGTTimeScore(UILabel *label) {
    NSInteger score = (NSInteger)round(label.font.pointSize * 10.0);
    NSString *text = label.text ?: label.attributedText.string ?: @"";
    NSString *probe = LGTSearchProbeForLabel(label);

    if ([probe containsString:@"time"]) score += 1000;
    if ([probe containsString:@"clock"]) score += 800;
    if ([probe containsString:@"date"]) score -= 500;

    NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
    NSUInteger digitCount = 0;
    for (NSUInteger i = 0; i < text.length; i++) {
        if ([digits characterIsMember:[text characterAtIndex:i]]) digitCount++;
    }
    if (digitCount >= 3 && ([text containsString:@":"] || [text containsString:@"."])) score += 1500;
    if (digitCount >= 3) score += 250;

    return score;
}

static NSInteger LGTDateScore(UILabel *label) {
    NSInteger score = (NSInteger)round(label.font.pointSize * 8.0);
    NSString *text = label.text ?: label.attributedText.string ?: @"";
    NSString *probe = LGTSearchProbeForLabel(label);

    if ([probe containsString:@"date"]) score += 1200;
    if ([probe containsString:@"subtitle"]) score += 350;
    if ([probe containsString:@"time"] || [probe containsString:@"clock"]) score -= 800;

    NSCharacterSet *letters = NSCharacterSet.letterCharacterSet;
    NSUInteger letterCount = 0;
    for (NSUInteger i = 0; i < text.length; i++) {
        if ([letters characterIsMember:[text characterAtIndex:i]]) letterCount++;
    }
    if (letterCount >= 3) score += 500;
    if ([text containsString:@":"]) score -= 700;

    return score;
}

static void LGTResolveTimeAndDateLabels(UIView *container, UILabel **timeLabel, UILabel **dateLabel) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    LGTCollectLabels(container, labels);

    UILabel *bestTime = nil;
    UILabel *bestDate = nil;
    NSInteger bestTimeScore = NSIntegerMin;
    NSInteger bestDateScore = NSIntegerMin;

    for (UILabel *label in labels) {
        NSInteger score = LGTTimeScore(label);
        if (score > bestTimeScore) {
            bestTimeScore = score;
            bestTime = label;
        }
    }

    for (UILabel *label in labels) {
        if (label == bestTime) continue;
        NSInteger score = LGTDateScore(label);
        if (score > bestDateScore) {
            bestDateScore = score;
            bestDate = label;
        }
    }

    if (!bestTime && labels.count > 0) {
        [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
            if (a.font.pointSize > b.font.pointSize) return NSOrderedAscending;
            if (a.font.pointSize < b.font.pointSize) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        bestTime = labels.firstObject;
        if (labels.count > 1) bestDate = labels[1];
    }

    if (timeLabel) *timeLabel = bestTime;
    if (dateLabel) *dateLabel = bestDate;
}

static void LGTApplyLayerShadow(UILabel *label,
                                BOOL enabled,
                                UIColor *color,
                                CGFloat opacity,
                                CGFloat radius,
                                CGFloat offsetX,
                                CGFloat offsetY,
                                NSInteger style,
                                BOOL isDate,
                                UIColor *textColor) {
    if (!label) return;

    if (enabled) {
        label.layer.shadowColor = color.CGColor;
        label.layer.shadowOpacity = (float)opacity;
        label.layer.shadowRadius = radius;
        label.layer.shadowOffset = CGSizeMake(offsetX, offsetY);
    } else if (style == (isDate ? 8 : 6)) {
        label.layer.shadowColor = UIColor.blackColor.CGColor;
        label.layer.shadowOpacity = 0.60f;
        label.layer.shadowRadius = 2.0;
        label.layer.shadowOffset = CGSizeMake(0.0, 1.0);
    } else if (style == (isDate ? 9 : 7)) {
        label.layer.shadowColor = textColor.CGColor;
        label.layer.shadowOpacity = 0.85f;
        label.layer.shadowRadius = 6.0;
        label.layer.shadowOffset = CGSizeZero;
    }
    label.layer.masksToBounds = NO;
}

static void LGTApplyAttributedStyle(UILabel *label,
                                    UIFont *font,
                                    UIColor *color,
                                    NSInteger style,
                                    BOOL isDate) {
    if (!label) return;

    NSString *text = label.text ?: label.attributedText.string ?: @"";
    if (isDate) {
        if (style == 5) text = text.uppercaseString;
        else if (style == 6) text = text.lowercaseString;
    }

    NSMutableDictionary *attributes = [@{
        NSFontAttributeName: font ?: label.font,
        NSForegroundColorAttributeName: color ?: label.textColor
    } mutableCopy];

    NSInteger outlineStyle = isDate ? 7 : 5;
    if (style == outlineStyle) {
        attributes[NSStrokeColorAttributeName] = color ?: label.textColor;
        attributes[NSStrokeWidthAttributeName] = @(-2.5);
    }

    label.attributedText = [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

static void LGTApplyTimeAppearance(UILabel *timeLabel) {
    if (!timeLabel) return;
    LGTLabelState *state = LGTStateForLabel(timeLabel);
    LGTRestoreLabel(timeLabel, state);

    if (!gEnabled || !gCustomTimeEnabled) return;

    UIColor *color = gTimeUIColor ?: state.textColor ?: UIColor.whiteColor;
    UIFont *font = LGTSafeFont(gTimeFont, state.font.pointSize, gTimeFontWeight, gTimeStyle, state.font);
    timeLabel.font = font;
    timeLabel.textColor = color;
    timeLabel.textAlignment = LGTAlignmentForValue(gTimeAlignment, state.textAlignment);

    CGAffineTransform custom = CGAffineTransformMakeTranslation(gTimeOffsetX, gTimeOffsetY);
    custom = CGAffineTransformScale(custom, gTimeScale, gTimeScale);
    timeLabel.transform = CGAffineTransformConcat(state.transform, custom);

    LGTApplyAttributedStyle(timeLabel, font, color, gTimeStyle, NO);
    LGTApplyLayerShadow(timeLabel,
                        gTimeShadowEnabled,
                        gTimeShadowUIColor ?: UIColor.blackColor,
                        gTimeShadowOpacity,
                        gTimeShadowRadius,
                        gTimeShadowOffsetX,
                        gTimeShadowOffsetY,
                        gTimeStyle,
                        NO,
                        color);
}

static void LGTApplyDateAppearance(UILabel *dateLabel) {
    if (!dateLabel) return;
    LGTLabelState *state = LGTStateForLabel(dateLabel);
    LGTRestoreLabel(dateLabel, state);

    if (!gEnabled || !gCustomDateEnabled) return;

    if (gDateFormatter) {
        NSString *formatted = [gDateFormatter stringFromDate:[NSDate date]];
        if (formatted.length) dateLabel.text = formatted;
    }

    UIColor *color = gDateUIColor ?: state.textColor ?: UIColor.whiteColor;
    UIFont *font = LGTSafeFont(gDateFont, state.font.pointSize, gDateFontWeight, gDateStyle, state.font);
    dateLabel.font = font;
    dateLabel.textColor = color;
    dateLabel.textAlignment = LGTAlignmentForValue(gDateAlignment, state.textAlignment);

    CGAffineTransform custom = CGAffineTransformMakeTranslation(gDateOffsetX, gDateOffsetY);
    custom = CGAffineTransformScale(custom, gDateScale, gDateScale);
    dateLabel.transform = CGAffineTransformConcat(state.transform, custom);

    LGTApplyAttributedStyle(dateLabel, font, color, gDateStyle, YES);
    LGTApplyLayerShadow(dateLabel,
                        gDateShadowEnabled,
                        gDateShadowUIColor ?: UIColor.blackColor,
                        gDateShadowOpacity,
                        gDateShadowRadius,
                        gDateShadowOffsetX,
                        gDateShadowOffsetY,
                        gDateStyle,
                        YES,
                        color);
}

static UIImage *LGTSystemImage(NSString *symbolName) {
    UIImage *image = [UIImage systemImageNamed:symbolName];
    if (!image) image = [UIImage systemImageNamed:@"star.fill"];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static CGRect LGTFrameForIcon(CGRect anchorFrame, CGFloat size, NSInteger position) {
    const CGFloat spacing = 8.0;
    CGFloat x = CGRectGetMaxX(anchorFrame) + spacing;
    CGFloat y = CGRectGetMidY(anchorFrame) - (size / 2.0);

    switch (position) {
        case 0:
            x = CGRectGetMinX(anchorFrame) - size - spacing;
            y = CGRectGetMidY(anchorFrame) - (size / 2.0);
            break;
        case 2:
            x = CGRectGetMidX(anchorFrame) - (size / 2.0);
            y = CGRectGetMinY(anchorFrame) - size - spacing;
            break;
        case 3:
            x = CGRectGetMidX(anchorFrame) - (size / 2.0);
            y = CGRectGetMaxY(anchorFrame) + spacing;
            break;
        default:
            break;
    }

    x += gIconOffsetX;
    y += gIconOffsetY;
    return CGRectMake(x, y, size, size);
}

static void LGTApplyIconAppearance(UIView *container, UILabel *timeLabel, UILabel *dateLabel) {
    UIImageView *iconView = objc_getAssociatedObject(container, LGTIconAssociationKey);

    if (!gEnabled || !gIconEnabled || !timeLabel) {
        [iconView removeFromSuperview];
        objc_setAssociatedObject(container, LGTIconAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (!iconView) {
        iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        iconView.userInteractionEnabled = NO;
        [container addSubview:iconView];
        objc_setAssociatedObject(container, LGTIconAssociationKey, iconView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    iconView.image = LGTSystemImage(gIconName);
    iconView.tintColor = gIconUIColor ?: UIColor.whiteColor;
    iconView.layer.shadowOpacity = gShadowEnabled ? (float)gShadowOpacity : 0.0f;
    iconView.layer.shadowRadius = gShadowRadius;
    iconView.layer.shadowOffset = CGSizeMake(gShadowOffsetX, gShadowOffsetY);
    iconView.layer.shadowColor = (gIconShadowUIColor ?: UIColor.blackColor).CGColor;
    iconView.layer.masksToBounds = NO;

    UILabel *anchorLabel = (gAnchorTarget == 1 && dateLabel) ? dateLabel : timeLabel;
    CGRect anchorFrame = [anchorLabel convertRect:anchorLabel.bounds toView:container];
    iconView.frame = LGTFrameForIcon(anchorFrame, gIconSize, gIconPosition);
    [container bringSubviewToFront:iconView];
}

static void LGTApplyToDateContainer(UIView *container) {
    if (!container) return;
    if (gKnownContainers) [gKnownContainers addObject:container];

    UILabel *timeLabel = nil;
    UILabel *dateLabel = nil;
    LGTResolveTimeAndDateLabels(container, &timeLabel, &dateLabel);

    if (!timeLabel) {
        UIImageView *iconView = objc_getAssociatedObject(container, LGTIconAssociationKey);
        [iconView removeFromSuperview];
        return;
    }

    LGTApplyTimeAppearance(timeLabel);
    if (dateLabel) LGTApplyDateAppearance(dateLabel);

    // Icon is intentionally last so it follows the final customized anchor geometry.
    LGTApplyIconAppearance(container, timeLabel, dateLabel);
}

typedef void (*LGTLayoutIMP)(id, SEL);
static LGTLayoutIMP gOriginalLayout = NULL;

static void LGTHookedLayout(id self, SEL _cmd) {
    if (gOriginalLayout) gOriginalLayout(self, _cmd);
    if ([self isKindOfClass:UIView.class]) {
        LGTApplyToDateContainer((UIView *)self);
    }
}

static Class LGTResolveDateContainerClass(void) {
    NSArray<NSString *> *candidates = @[
        @"SBFLockScreenDateView",
        @"CSDateView",
        @"SBFLockScreenDateSubtitleView"
    ];

    for (NSString *name in candidates) {
        Class cls = NSClassFromString(name);
        if (cls && class_getInstanceMethod(cls, @selector(layoutSubviews))) {
            return cls;
        }
    }
    return Nil;
}

%ctor {
    @autoreleasepool {
        gFontCache = [NSMutableDictionary dictionary];
        gKnownContainers = [NSHashTable weakObjectsHashTable];
        LGTLoadPrefs();

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        LGTReloadCallback,
                                        LGTReloadNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        Class dateContainerClass = LGTResolveDateContainerClass();
        if (dateContainerClass) {
            MSHookMessageEx(dateContainerClass,
                            @selector(layoutSubviews),
                            (IMP)LGTHookedLayout,
                            (IMP *)&gOriginalLayout);
        }
    }
}
