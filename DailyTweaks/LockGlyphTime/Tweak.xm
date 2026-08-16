#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString * const LGTPrefsDomain = @"com.nextsolution.lockglyphtime";
static CFStringRef const LGTReloadNotification = CFSTR("com.nextsolution.lockglyphtime/ReloadPrefs");
static const void *LGTIconAssociationKey = &LGTIconAssociationKey;

static BOOL gEnabled = YES;
static CGFloat gTimeScale = 1.0;
static CGFloat gDateScale = 1.0;
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

static CGFloat LGTClamped(CGFloat value, CGFloat minValue, CGFloat maxValue) {
    return MAX(minValue, MIN(maxValue, value));
}

static UIColor *LGTColorFromHex(NSString *hex, UIColor *fallback) {
    if (![hex isKindOfClass:NSString.class]) return fallback;
    NSString *clean = [[hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([clean hasPrefix:@"#"]) clean = [clean substringFromIndex:1];
    if (clean.length != 6 && clean.length != 8) return fallback;

    unsigned long long value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexLongLong:&value]) return fallback;

    CGFloat alpha = 1.0;
    CGFloat red, green, blue;
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

static void LGTLoadPrefs(void) {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain];

    id value = [prefs objectForKey:@"enabled"];
    gEnabled = value ? [value boolValue] : YES;

    value = [prefs objectForKey:@"timeScale"];
    gTimeScale = LGTClamped(value ? [value doubleValue] : 1.0, 0.50, 2.00);

    value = [prefs objectForKey:@"dateScale"];
    gDateScale = LGTClamped(value ? [value doubleValue] : 1.0, 0.50, 2.00);

    value = [prefs objectForKey:@"iconEnabled"];
    gIconEnabled = value ? [value boolValue] : YES;

    NSString *iconName = [prefs stringForKey:@"iconName"];
    gIconName = iconName.length ? iconName : @"sparkles";

    value = [prefs objectForKey:@"iconSize"];
    gIconSize = LGTClamped(value ? [value doubleValue] : 22.0, 10.0, 80.0);

    NSString *iconColor = [prefs stringForKey:@"iconColor"];
    gIconColor = iconColor.length ? iconColor : @"#FFFFFF";

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

    NSString *shadowColor = [prefs stringForKey:@"shadowColor"];
    gShadowColor = shadowColor.length ? shadowColor : @"#000000";

    value = [prefs objectForKey:@"shadowOpacity"];
    gShadowOpacity = LGTClamped(value ? [value doubleValue] : 0.45, 0.0, 1.0);

    value = [prefs objectForKey:@"shadowRadius"];
    gShadowRadius = LGTClamped(value ? [value doubleValue] : 2.0, 0.0, 20.0);

    value = [prefs objectForKey:@"shadowOffsetX"];
    gShadowOffsetX = LGTClamped(value ? [value doubleValue] : 0.0, -20.0, 20.0);

    value = [prefs objectForKey:@"shadowOffsetY"];
    gShadowOffsetY = LGTClamped(value ? [value doubleValue] : 1.0, -20.0, 20.0);
}

static void LGTReloadCallback(CFNotificationCenterRef center,
                              void *observer,
                              CFStringRef name,
                              const void *object,
                              CFDictionaryRef userInfo) {
    LGTLoadPrefs();
}

static void LGTCollectLabels(UIView *view, NSMutableArray<UILabel *> *labels) {
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        if (label.text.length > 0 && label.font.pointSize > 0.0) {
            [labels addObject:label];
        }
    }
    for (UIView *subview in view.subviews) {
        LGTCollectLabels(subview, labels);
    }
}

static void LGTResolveTimeAndDateLabels(UIView *container, UILabel **timeLabel, UILabel **dateLabel) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    LGTCollectLabels(container, labels);
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        if (a.font.pointSize > b.font.pointSize) return NSOrderedAscending;
        if (a.font.pointSize < b.font.pointSize) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    if (timeLabel) *timeLabel = labels.count > 0 ? labels[0] : nil;
    if (dateLabel) *dateLabel = labels.count > 1 ? labels[1] : nil;
}

static UIImage *LGTSystemImage(NSString *symbolName) {
    UIImage *image = [UIImage systemImageNamed:symbolName];
    return image ?: [UIImage systemImageNamed:@"star.fill"];
}

static CGRect LGTFrameForIcon(CGRect anchorFrame, CGFloat size, NSInteger position) {
    const CGFloat spacing = 8.0;
    CGFloat x = CGRectGetMaxX(anchorFrame) + spacing;
    CGFloat y = CGRectGetMidY(anchorFrame) - (size / 2.0);

    switch (position) {
        case 0: // left
            x = CGRectGetMinX(anchorFrame) - size - spacing;
            y = CGRectGetMidY(anchorFrame) - (size / 2.0);
            break;
        case 2: // above
            x = CGRectGetMidX(anchorFrame) - (size / 2.0);
            y = CGRectGetMinY(anchorFrame) - size - spacing;
            break;
        case 3: // below
            x = CGRectGetMidX(anchorFrame) - (size / 2.0);
            y = CGRectGetMaxY(anchorFrame) + spacing;
            break;
        default: // right
            break;
    }

    x += gIconOffsetX;
    y += gIconOffsetY;
    return CGRectMake(x, y, size, size);
}

static void LGTApplyToDateContainer(UIView *container) {
    UIImageView *iconView = objc_getAssociatedObject(container, LGTIconAssociationKey);

    if (!gEnabled) {
        [iconView removeFromSuperview];
        objc_setAssociatedObject(container, LGTIconAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    UILabel *timeLabel = nil;
    UILabel *dateLabel = nil;
    LGTResolveTimeAndDateLabels(container, &timeLabel, &dateLabel);
    if (!timeLabel) return;

    timeLabel.transform = CGAffineTransformMakeScale(gTimeScale, gTimeScale);
    if (dateLabel) dateLabel.transform = CGAffineTransformMakeScale(gDateScale, gDateScale);

    if (!gIconEnabled) {
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
    iconView.tintColor = LGTColorFromHex(gIconColor, UIColor.whiteColor);

    iconView.layer.shadowOpacity = gShadowEnabled ? (float)gShadowOpacity : 0.0f;
    iconView.layer.shadowRadius = gShadowRadius;
    iconView.layer.shadowOffset = CGSizeMake(gShadowOffsetX, gShadowOffsetY);
    iconView.layer.shadowColor = LGTColorFromHex(gShadowColor, UIColor.blackColor).CGColor;
    iconView.layer.masksToBounds = NO;

    UILabel *anchorLabel = (gAnchorTarget == 1 && dateLabel) ? dateLabel : timeLabel;
    iconView.frame = LGTFrameForIcon(anchorLabel.frame, gIconSize, gIconPosition);
    [container bringSubviewToFront:iconView];
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
    // Ordered from the most stable known SpringBoardFoundation class to fallbacks.
    // Add new private class names here after validating on future iOS builds.
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
