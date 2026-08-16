#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

extern void MSHookMessageEx(Class _class, SEL message, IMP hook, IMP *old);

static NSString * const MGBackgroundDirectory = @"/var/mobile/Library/Preferences/NextSolutionTweaks/CCBackgrounds";
static NSString * const MGLogDirectory = @"/var/mobile/Library/Logs/NextSolution";
static NSString * const MGLogPath = @"/var/mobile/Library/Logs/NextSolution/module-glass.log";
static NSString * const MGPreviousLogPath = @"/var/mobile/Library/Logs/NextSolution/module-glass.previous.log";
static CFStringRef const MGPrefsDomain = CFSTR("com.nextsolution.unlockvibrate");
static NSInteger const MGImageTag = 0x4D470106;
static NSInteger const MGVolumeIconOverlayTag = 0x4D475649;
static NSInteger const MGVolumePercentageOverlayTag = 0x4D475650;

static NSHashTable *MGControllers;
static char MGLastDiagnosticKey;
static char MGVolumeOriginalAlphaKey;
static char MGVolumeOriginalIconAlphaKey;
static char MGVolumeIconOverlayKey;
static char MGVolumeOriginalPercentageAlphaKey;

static void (*MGOrigModuleViewDidLoad)(id, SEL);
static void (*MGOrigModuleLayout)(id, SEL);
static void (*MGOrigContentViewDidLoad)(id, SEL);
static void (*MGOrigContentLayout)(id, SEL);

static void MGApplyController(id controller, NSString *source);

#pragma mark - Logging / preferences

static void MGRotateLogIfNeeded(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDictionary *attrs = [fm attributesOfItemAtPath:MGLogPath error:nil];
    if ([attrs fileSize] < 1024 * 1024) return;
    [fm removeItemAtPath:MGPreviousLogPath error:nil];
    [fm moveItemAtPath:MGLogPath toPath:MGPreviousLogPath error:nil];
}

static void MGLog(NSString *format, ...) {
    if (!format) return;
    va_list args;
    va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:MGLogDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    MGRotateLogIfNeeded();
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", NSDate.date, body ?: @""];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (![fm fileExistsAtPath:MGLogPath]) [data writeToFile:MGLogPath atomically:YES];
    else {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:MGLogPath];
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
    }
}

static id MGPreference(NSString *key) {
    if (!key.length) return nil;
    CFPreferencesAppSynchronize(MGPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, MGPrefsDomain);
    return value ? CFBridgingRelease(value) : nil;
}

static BOOL MGBoolPreference(NSString *key, BOOL fallback) {
    id value = MGPreference(key);
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

static CGFloat MGFloatPreference(NSString *key, CGFloat fallback) {
    id value = MGPreference(key);
    if (![value respondsToSelector:@selector(doubleValue)]) return fallback;
    CGFloat result = (CGFloat)[value doubleValue];
    return isfinite(result) ? result : fallback;
}

static BOOL MGVerboseDiagnosticsEnabled(void) {
    NSDictionary *control = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.nextsolution.nextlog.plist"];
    if (![control[@"enabled"] boolValue]) return NO;
    NSString *active = [[control[@"activeTweak"] description] lowercaseString];
    return [active containsString:@"moduleglass"] || [active containsString:@"module glass"] ||
           [active containsString:@"cc-module-backgrounds"] || [active containsString:@"ccbackground"];
}

#pragma mark - Identifier mapping

static NSString *MGNormalize(NSString *input) {
    if (!input.length) return @"";
    NSMutableString *result = [NSMutableString string];
    NSCharacterSet *allowed = NSCharacterSet.alphanumericCharacterSet;
    NSString *lower = input.lowercaseString;
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        if ([allowed characterIsMember:c]) [result appendFormat:@"%C", c];
    }
    return result;
}

static void MGAddIdentifierValue(id value, NSMutableArray<NSString *> *out, NSInteger depth) {
    if (!value || depth > 2) return;
    if ([value isKindOfClass:NSString.class]) {
        if ([(NSString *)value length]) [out addObject:value];
        return;
    }
    [out addObject:NSStringFromClass([value class]) ?: @""];
    for (NSString *key in @[@"bundleIdentifier", @"displayName", @"moduleIdentifier", @"identifier"]) {
        @try {
            id nested = [value valueForKey:key];
            if (nested && nested != value) MGAddIdentifierValue(nested, out, depth + 1);
        } @catch (__unused NSException *e) {}
    }
}

static NSArray<NSString *> *MGCandidatesForController(id controller) {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    if (!controller) return result;
    [result addObject:NSStringFromClass([controller class]) ?: @""];

    for (NSString *key in @[@"moduleIdentifier", @"_moduleIdentifier", @"identifier", @"_identifier",
                            @"module", @"_module", @"contentModule", @"_contentModule",
                            @"moduleInstance", @"_moduleInstance", @"parentViewController"]) {
        @try {
            id value = [controller valueForKey:key];
            if (value && value != controller) MGAddIdentifierValue(value, result, 0);
        } @catch (__unused NSException *e) {}
    }
    return result;
}

static BOOL MGContainsAny(NSString *blob, NSArray<NSString *> *needles) {
    for (NSString *needle in needles) if ([blob containsString:needle]) return YES;
    return NO;
}

static NSString *MGSlotForController(id controller, NSArray<NSString *> **outCandidates) {
    NSArray<NSString *> *candidates = MGCandidatesForController(controller);
    if (outCandidates) *outCandidates = candidates;
    NSString *blob = MGNormalize([candidates componentsJoinedByString:@"|"]);

    if (MGContainsAny(blob, @[@"comapplemediaremotecontrolcenteraudio", @"mediacontrolsaudiomodule", @"audiomodule", @"volume"])) return @"volume";
    if (MGContainsAny(blob, @[@"comapplecontrolcenterdisplaymodule", @"ccuidisplaymodule", @"displaymodule", @"brightness"])) return @"brightness";
    if (MGContainsAny(blob, @[@"comapplemediaremotecontrolcenternowplaying", @"mediacontrolsmodule", @"nowplaying", @"mrui"])) return @"media";
    if (MGContainsAny(blob, @[@"comapplereplaykitcontrolcenterscreencapture", @"rpcontrolcentermodule", @"screencapture", @"screenrecord", @"recordingmodule"])) return @"screenrecording";
    if (MGContainsAny(blob, @[@"comapplemediaremotecontrolcenterairplaymirroring", @"mpavairplaymirroringmodule", @"screenmirror", @"airplaymirror"])) return @"screenmirroring";
    if (MGContainsAny(blob, @[@"comapplecontrolcenterconnectivitymodule", @"ccuiconnectivitymodule", @"airplane"])) return @"connectivity";
    if (MGContainsAny(blob, @[@"comapplecontrolcenterorientationlockmodule", @"ccuiorientationlockmodule", @"rotationlock"])) return @"orientation";
    if (MGContainsAny(blob, @[@"comapplecontrolcenterlowpowermodule", @"ccuilowpowermodule", @"batterysaver"])) return @"lowpower";
    if (MGContainsAny(blob, @[@"comapplefocusuimodule", @"fccccontrolcentermodule", @"donotdisturb"])) return @"focus";
    if (MGContainsAny(blob, @[@"comapplecontrolcenterflashlightmodule", @"ccuiflashlightmodule", @"torch"])) return @"flashlight";
    if (MGContainsAny(blob, @[@"comapplemobiletimercontrolcentertimer", @"mtcctimermodule", @"clockmodule"])) return @"timer";
    if ([blob containsString:@"calculator"]) return @"calculator";
    if (MGContainsAny(blob, @[@"comapplecontrolcentercameramodule", @"ccuicameramodule"])) return @"camera";
    if (MGContainsAny(blob, @[@"comappleaccessibilitycontrolcenterhearingdevices", @"hacccontentmodule", @"hearing"])) return @"hearing";
    if (MGContainsAny(blob, @[@"quicknote", @"notes"])) return @"notes";
    if (MGContainsAny(blob, @[@"homecontrol", @"homekit", @"homemodule"])) return @"home";
    return @"other";
}

#pragma mark - View selection

static BOOL MGIsExpanded(UIView *root) {
    if (!root) return YES;
    CGFloat w = CGRectGetWidth(root.bounds), h = CGRectGetHeight(root.bounds);
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat sw = MIN(screen.width, screen.height);
    CGFloat sh = MAX(screen.width, screen.height);
    CGFloat rw = MIN(w, h), rh = MAX(w, h);
    if (w <= 1 || h <= 1) return YES;
    return (rw >= sw * 0.72 && rh >= sh * 0.38) || rw >= sw * 0.90 || rh >= sh * 0.68;
}

static BOOL MGClassNameContains(UIView *view, NSArray<NSString *> *needles) {
    NSString *name = NSStringFromClass(view.class).lowercaseString;
    for (NSString *needle in needles) if ([name containsString:needle]) return YES;
    return NO;
}

static UIView *MGFindNativeBackground(UIView *root) {
    if (!root) return nil;
    for (UIView *view in root.subviews) {
        if (view.tag == MGImageTag) continue;
        if (MGClassNameContains(view, @[@"mtmaterialview", @"ccuimodulebackground", @"contentmodulebackground", @"modulebackground"])) return view;
    }
    for (UIView *view in root.subviews) {
        if (view.tag == MGImageTag) continue;
        UIView *found = MGFindNativeBackground(view);
        if (found) return found;
    }
    return nil;
}

static UIView *MGFindSliderView(UIView *root) {
    if (!root) return nil;
    if (MGClassNameContains(root, @[@"continuousslider", @"slider"])) return root;
    for (UIView *view in root.subviews) {
        if (view.tag == MGImageTag) continue;
        UIView *found = MGFindSliderView(view);
        if (found) return found;
    }
    return nil;
}

// Volume-only experiment. No other module calls these helpers.
static BOOL MGVolumeForegroundView(UIView *view) {
    if (!view) return NO;
    if ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class] || [view isKindOfClass:UIButton.class]) return YES;
    NSString *name = NSStringFromClass(view.class).lowercaseString;
    return [name containsString:@"label"] || [name containsString:@"glyph"] ||
           [name containsString:@"icon"] || [name containsString:@"button"] ||
           [name containsString:@"text"] || [name containsString:@"percentage"];
}

static BOOL MGVolumeSubtreeHasForeground(UIView *view) {
    if (!view) return NO;
    if (MGVolumeForegroundView(view)) return YES;
    for (UIView *child in view.subviews) {
        if (child.tag == MGImageTag) continue;
        if (MGVolumeSubtreeHasForeground(child)) return YES;
    }
    return NO;
}

static void MGRestoreVolumeVisuals(UIView *root) {
    if (!root) return;
    NSNumber *savedAlpha = objc_getAssociatedObject(root, &MGVolumeOriginalAlphaKey);
    if (savedAlpha) {
        root.alpha = savedAlpha.doubleValue;
        objc_setAssociatedObject(root, &MGVolumeOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *child in root.subviews) MGRestoreVolumeVisuals(child);
}

static BOOL MGVolumeObscuringVisual(UIView *view, UIView *slider, UIImageView *imageView) {
    if (!view || !slider || view == imageView || view.tag == MGImageTag) return NO;
    if ([imageView isDescendantOfView:view]) return NO;
    if ([view isKindOfClass:UIControl.class] || MGVolumeSubtreeHasForeground(view)) return NO;

    CGRect converted = [view convertRect:view.bounds toView:slider];
    CGFloat sliderArea = MAX(1.0, CGRectGetWidth(slider.bounds) * CGRectGetHeight(slider.bounds));
    CGFloat area = MAX(0.0, CGRectGetWidth(converted) * CGRectGetHeight(converted));
    CGFloat ratio = area / sliderArea;
    if (ratio < 0.10) return NO;

    NSString *name = NSStringFromClass(view.class).lowercaseString;
    BOOL namedVisual = [name containsString:@"material"] || [name containsString:@"effect"] ||
                       [name containsString:@"blur"] || [name containsString:@"fill"] ||
                       [name containsString:@"progress"] || [name containsString:@"background"] ||
                       [name containsString:@"tint"] || [name containsString:@"valueindicator"];
    BOOL plainLargeVisual = ([name isEqualToString:@"uiview"] || [name containsString:@"visualeffectsubview"]) && ratio >= 0.18;
    return namedVisual || plainLargeVisual;
}

static NSUInteger MGApplyVolumeImageMode(UIView *slider, UIImageView *imageView, NSMutableArray<NSString *> *suppressedClasses) {
    if (!slider || !imageView) return 0;
    NSUInteger count = 0;
    for (UIView *child in slider.subviews) {
        if (child.tag == MGImageTag) continue;
        if (MGVolumeObscuringVisual(child, slider, imageView)) {
            if (!objc_getAssociatedObject(child, &MGVolumeOriginalAlphaKey)) {
                objc_setAssociatedObject(child, &MGVolumeOriginalAlphaKey, @(child.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            child.alpha = 0.0;
            [suppressedClasses addObject:NSStringFromClass(child.class) ?: @"UIView"];
            count++;
            continue;
        }
        count += MGApplyVolumeImageMode(child, imageView, suppressedClasses);
    }
    return count;
}

static UIColor *MGVolumeColorFromHex(NSString *input) {
    if (![input isKindOfClass:NSString.class]) return nil;
    NSString *hex = [[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    if (hex.length != 6 && hex.length != 8) return nil;
    unsigned int value = 0;
    if (![[NSScanner scannerWithString:hex] scanHexInt:&value]) return nil;
    CGFloat r, g, b, a = 1.0;
    if (hex.length == 8) {
        r = ((value >> 24) & 0xFF) / 255.0;
        g = ((value >> 16) & 0xFF) / 255.0;
        b = ((value >> 8) & 0xFF) / 255.0;
        a = (value & 0xFF) / 255.0;
    } else {
        r = ((value >> 16) & 0xFF) / 255.0;
        g = ((value >> 8) & 0xFF) / 255.0;
        b = (value & 0xFF) / 255.0;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static void MGRestoreVolumeColorPresentation(UIView *root) {
    if (!root) return;
    for (UIView *child in [root.subviews copy]) {
        if (child.tag == MGVolumeIconOverlayTag || child.tag == MGVolumePercentageOverlayTag) {
            [child removeFromSuperview];
            continue;
        }
        MGRestoreVolumeColorPresentation(child);
    }
    if ([root isKindOfClass:UIImageView.class]) {
        NSNumber *savedAlpha = objc_getAssociatedObject(root, &MGVolumeOriginalIconAlphaKey);
        if (savedAlpha) {
            root.alpha = savedAlpha.doubleValue;
            objc_setAssociatedObject(root, &MGVolumeOriginalIconAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(root, &MGVolumeIconOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    if ([root isKindOfClass:UILabel.class]) {
        NSNumber *savedAlpha = objc_getAssociatedObject(root, &MGVolumeOriginalPercentageAlphaKey);
        if (savedAlpha) {
            root.alpha = savedAlpha.doubleValue;
            objc_setAssociatedObject(root, &MGVolumeOriginalPercentageAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static NSInteger MGVolumeIconScore(UIImageView *imageView, UIView *slider) {
    if (!imageView || !slider || imageView.tag == MGImageTag || imageView.tag == MGVolumeIconOverlayTag || !imageView.image || imageView.hidden) return -1;
    CGRect rect = [imageView convertRect:imageView.bounds toView:slider];
    CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
    if (w < 8.0 || h < 8.0 || w > 64.0 || h > 64.0) return -1;
    CGFloat area = w * h;
    NSInteger score = 1200 - (NSInteger)fabs(area - 576.0);
    CGFloat cy = CGRectGetMidY(rect);
    if (cy > CGRectGetHeight(slider.bounds) * 0.55) score += 1800;
    if (fabs(CGRectGetMidX(rect) - CGRectGetMidX(slider.bounds)) < CGRectGetWidth(slider.bounds) * 0.35) score += 900;
    NSString *names = @"";
    UIView *cursor = imageView;
    for (NSInteger i = 0; i < 5 && cursor; i++, cursor = cursor.superview) {
        names = [names stringByAppendingFormat:@" %@", NSStringFromClass(cursor.class).lowercaseString ?: @""];
    }
    for (NSString *needle in @[@"glyph", @"speaker", @"volume", @"audio", @"icon"]) {
        if ([names containsString:needle]) score += 3500;
    }
    return score;
}

static void MGCollectVolumeIconCandidates(UIView *root, UIView *slider, NSMutableArray<UIImageView *> *out) {
    if (!root) return;
    if ([root isKindOfClass:UIImageView.class] && root.tag != MGImageTag && root.tag != MGVolumeIconOverlayTag) {
        UIImageView *iv=(UIImageView *)root;
        if (MGVolumeIconScore(iv, slider) >= 0) [out addObject:iv];
    }
    for (UIView *child in root.subviews) MGCollectVolumeIconCandidates(child, slider, out);
}

static UIImageView *MGFindVolumeIcon(UIView *slider) {
    if (!slider) return nil;
    NSMutableArray<UIImageView *> *candidates=[NSMutableArray array];
    MGCollectVolumeIconCandidates(slider, slider, candidates);
    UIImageView *best=nil;
    NSInteger bestScore=-1;
    for (UIImageView *candidate in candidates) {
        NSInteger score=MGVolumeIconScore(candidate, slider);
        if (score > bestScore) { best=candidate; bestScore=score; }
    }
    return best;
}

static BOOL MGApplyVolumeIconTint(UIView *slider, UIColor *color, NSString **outClass, CGRect *outFrame) {
    if (!slider || !color) return NO;
    UIImageView *icon=MGFindVolumeIcon(slider);
    if (!icon || !icon.image || !icon.superview) return NO;

    NSNumber *storedAlpha=objc_getAssociatedObject(icon, &MGVolumeOriginalIconAlphaKey);
    CGFloat sourceAlpha=storedAlpha ? storedAlpha.doubleValue : icon.alpha;
    if (!storedAlpha) {
        objc_setAssociatedObject(icon, &MGVolumeOriginalIconAlphaKey, @(icon.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIImageView *overlay=[[UIImageView alloc] initWithFrame:CGRectZero];
    overlay.tag=MGVolumeIconOverlayTag;
    overlay.userInteractionEnabled=NO;
    overlay.backgroundColor=UIColor.clearColor;
    overlay.image=[icon.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    overlay.tintColor=color;
    overlay.contentMode=icon.contentMode;
    overlay.clipsToBounds=icon.clipsToBounds;
    overlay.bounds=icon.bounds;
    overlay.center=icon.center;
    overlay.transform=icon.transform;
    overlay.alpha=sourceAlpha;
    overlay.hidden=icon.hidden;
    overlay.layer.cornerRadius=icon.layer.cornerRadius;
    overlay.layer.masksToBounds=icon.layer.masksToBounds;
    [icon.superview insertSubview:overlay aboveSubview:icon];
    objc_setAssociatedObject(icon, &MGVolumeIconOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Keep Apple's image/state alive but make only the native pixels transparent.
    icon.alpha=0.0;

    if (outClass) *outClass=[NSString stringWithFormat:@"%@+overlay", NSStringFromClass(icon.class) ?: @"UIImageView"];
    if (outFrame) *outFrame=[overlay convertRect:overlay.bounds toView:slider];
    return YES;
}

static NSInteger MGVolumePercentageScore(UILabel *label, UIView *slider) {
    if (!label || !slider || label.tag == MGVolumePercentageOverlayTag || label.hidden) return -1;
    NSString *text = label.text ?: @"";
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return -1;

    CGRect rect = [label convertRect:label.bounds toView:slider];
    CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
    if (w < 8.0 || h < 8.0 || w > 120.0 || h > 70.0) return -1;

    NSInteger score = 0;
    if ([trimmed containsString:@"%"] ) score += 10000;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789% ."];
    if ([[trimmed stringByTrimmingCharactersInSet:allowed] length] == 0) score += 2500;

    NSString *names = @"";
    UIView *cursor = label;
    for (NSInteger i = 0; i < 5 && cursor; i++, cursor = cursor.superview) {
        names = [names stringByAppendingFormat:@" %@", NSStringFromClass(cursor.class).lowercaseString ?: @""];
    }
    for (NSString *needle in @[@"percentage", @"percent", @"value", @"volume", @"audio", @"slider"]) {
        if ([names containsString:needle]) score += 1200;
    }

    CGFloat midX = CGRectGetMidX(rect);
    if (fabs(midX - CGRectGetMidX(slider.bounds)) < CGRectGetWidth(slider.bounds) * 0.40) score += 700;
    return score;
}

static void MGCollectVolumePercentageCandidates(UIView *root, UIView *slider, NSMutableArray<UILabel *> *out) {
    if (!root) return;
    if ([root isKindOfClass:UILabel.class] && root.tag != MGVolumePercentageOverlayTag) {
        UILabel *label=(UILabel *)root;
        if (MGVolumePercentageScore(label, slider) >= 0) [out addObject:label];
    }
    for (UIView *child in root.subviews) MGCollectVolumePercentageCandidates(child, slider, out);
}

static UILabel *MGFindVolumePercentageLabel(UIView *slider) {
    if (!slider) return nil;
    NSMutableArray<UILabel *> *candidates=[NSMutableArray array];
    MGCollectVolumePercentageCandidates(slider, slider, candidates);
    UILabel *best=nil;
    NSInteger bestScore=-1;
    for (UILabel *candidate in candidates) {
        NSInteger score=MGVolumePercentageScore(candidate, slider);
        if (score > bestScore) { best=candidate; bestScore=score; }
    }
    return bestScore >= 2000 ? best : nil;
}

static BOOL MGApplyVolumePercentageTint(UIView *slider, UIColor *color, NSString **outClass, CGRect *outFrame, NSString **outText) {
    if (!slider || !color) return NO;
    UILabel *label=MGFindVolumePercentageLabel(slider);
    if (!label || !label.superview) return NO;

    NSNumber *storedAlpha=objc_getAssociatedObject(label, &MGVolumeOriginalPercentageAlphaKey);
    CGFloat sourceAlpha=storedAlpha ? storedAlpha.doubleValue : label.alpha;
    if (!storedAlpha) {
        objc_setAssociatedObject(label, &MGVolumeOriginalPercentageAlphaKey, @(label.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UILabel *overlay=[[UILabel alloc] initWithFrame:CGRectZero];
    overlay.tag=MGVolumePercentageOverlayTag;
    overlay.userInteractionEnabled=NO;
    overlay.backgroundColor=UIColor.clearColor;
    overlay.bounds=label.bounds;
    overlay.center=label.center;
    overlay.transform=label.transform;
    overlay.alpha=sourceAlpha;
    overlay.hidden=label.hidden;
    overlay.font=label.font;
    overlay.textAlignment=label.textAlignment;
    overlay.numberOfLines=label.numberOfLines;
    overlay.lineBreakMode=label.lineBreakMode;
    overlay.baselineAdjustment=label.baselineAdjustment;
    overlay.adjustsFontSizeToFitWidth=label.adjustsFontSizeToFitWidth;
    overlay.minimumScaleFactor=label.minimumScaleFactor;
    overlay.contentMode=label.contentMode;
    overlay.layer.cornerRadius=label.layer.cornerRadius;
    overlay.layer.masksToBounds=label.layer.masksToBounds;

    if (label.attributedText.length) {
        NSMutableAttributedString *a=[label.attributedText mutableCopy];
        [a addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(0, a.length)];
        overlay.attributedText=a;
    } else {
        overlay.text=label.text;
        overlay.textColor=color;
    }

    [label.superview insertSubview:overlay aboveSubview:label];
    label.alpha=0.0;

    if (outClass) *outClass=[NSString stringWithFormat:@"%@+overlay", NSStringFromClass(label.class) ?: @"UILabel"];
    if (outFrame) *outFrame=[overlay convertRect:overlay.bounds toView:slider];
    if (outText) *outText=overlay.text ?: overlay.attributedText.string ?: @"";
    return YES;
}

static void MGRemoveTaggedImages(UIView *root, UIView *except) {
    if (!root) return;
    for (UIView *view in [root.subviews copy]) {
        if (view.tag == MGImageTag && view != except) {
            [view removeFromSuperview];
            continue;
        }
        MGRemoveTaggedImages(view, except);
    }
}

static UIImageView *MGImageViewInParent(UIView *parent) {
    for (UIView *view in parent.subviews) if (view.tag == MGImageTag && [view isKindOfClass:UIImageView.class]) return (UIImageView *)view;
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    imageView.tag = MGImageTag;
    imageView.userInteractionEnabled = NO;
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.clipsToBounds = YES;
    imageView.layer.masksToBounds = YES;
    return imageView;
}

static void MGCopyCornerGeometry(UIImageView *imageView, UIView *source, UIView *fallback) {
    CALayer *layer = source.layer ?: fallback.layer;
    CGFloat radius = layer.cornerRadius;
    if (radius <= 0.0) radius = fallback.layer.cornerRadius;
    imageView.layer.cornerRadius = MAX(0.0, radius);
    if (@available(iOS 13.0, *)) imageView.layer.cornerCurve = layer.cornerCurve ?: kCACornerCurveContinuous;
    imageView.layer.maskedCorners = layer.maskedCorners ?: kCALayerAllCorners;
}

static BOOL MGPrepareInsertion(UIView *root, NSString *slot, UIView **outParent, UIView **outAnchor, CGRect *outFrame, UIView **outCornerSource, NSString **outStrategy) {
    BOOL sliderSlot = [slot isEqualToString:@"volume"] || [slot isEqualToString:@"brightness"];
    UIView *scope = root;
    NSString *strategy = @"generic-native";

    if (sliderSlot) {
        UIView *slider = MGFindSliderView(root);
        if (slider) {
            scope = slider;
            strategy = @"slider-native";
        } else {
            strategy = @"slider-fallback-root";
        }
    }

    UIView *native = MGFindNativeBackground(scope);
    if (native.superview) {
        if (outParent) *outParent = native.superview;
        if (outAnchor) *outAnchor = native;
        if (outFrame) *outFrame = native.frame;
        if (outCornerSource) *outCornerSource = native;
        if (outStrategy) *outStrategy = strategy;
        return YES;
    }

    if (sliderSlot && scope != root) {
        if (outParent) *outParent = scope;
        if (outAnchor) *outAnchor = nil;
        if (outFrame) *outFrame = scope.bounds;
        if (outCornerSource) *outCornerSource = scope;
        if (outStrategy) *outStrategy = @"slider-index0";
        return YES;
    }

    if (outParent) *outParent = root;
    if (outAnchor) *outAnchor = nil;
    if (outFrame) *outFrame = root.bounds;
    if (outCornerSource) *outCornerSource = root;
    if (outStrategy) *outStrategy = @"root-index0";
    return YES;
}

#pragma mark - Apply

static void MGDiagnosticOnce(id controller, NSString *signature, NSString *line) {
    if (!MGVerboseDiagnosticsEnabled()) return;
    NSString *previous = objc_getAssociatedObject(controller, &MGLastDiagnosticKey);
    if ([previous isEqualToString:signature]) return;
    objc_setAssociatedObject(controller, &MGLastDiagnosticKey, signature, OBJC_ASSOCIATION_COPY_NONATOMIC);
    MGLog(@"%@", line);
}

static void MGApplyController(id controller, NSString *source) {
    if (!controller || ![controller respondsToSelector:@selector(view)]) return;
    UIView *root = [controller view];
    if (!root) return;

    NSArray<NSString *> *candidates = nil;
    NSString *slot = MGSlotForController(controller, &candidates);
    MGRestoreVolumeColorPresentation(root);
    MGRestoreVolumeVisuals(root);
    BOOL expanded = MGIsExpanded(root);
    BOOL enabled = MGBoolPreference(@"CCModuleBackgroundsEnabled", YES);
    CGFloat opacity = MIN(1.0, MAX(0.0, MGFloatPreference(@"CCModuleBackgroundOpacity", 1.0)));
    BOOL removeBlur = MGBoolPreference(@"CCModuleRemoveBlur", NO);
    NSString *path = [MGBackgroundDirectory stringByAppendingPathComponent:[slot stringByAppendingString:@".jpg"]];
    BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:path];

    if (expanded) {
        MGRemoveTaggedImages(root, nil);
        NSString *sig = [NSString stringWithFormat:@"expanded|%@|%.0fx%.0f", slot, CGRectGetWidth(root.bounds), CGRectGetHeight(root.bounds)];
        MGDiagnosticOnce(controller, sig, [NSString stringWithFormat:@"expanded-bypass source=%@ controller=%@ slot=%@ frame=%@ candidates=%@", source, NSStringFromClass([controller class]), slot, NSStringFromCGRect(root.frame), candidates]);
        return;
    }

    BOOL volumeIconApplied = NO;
    NSString *volumeIconClass = @"<none>";
    CGRect volumeIconFrame = CGRectZero;
    BOOL volumePercentageApplied = NO;
    NSString *volumePercentageClass = @"<none>";
    CGRect volumePercentageFrame = CGRectZero;
    NSString *volumePercentageText = @"";
    BOOL volumeIconColorEnabled = [slot isEqualToString:@"volume"] && MGBoolPreference(@"CCModuleVolumeIconColorEnabled", NO);
    NSString *volumeIconColorHex = [[MGPreference(@"CCModuleVolumeIconColor") description] copy] ?: @"";
    if (volumeIconColorEnabled) {
        UIView *volumeSlider = MGFindSliderView(root);
        UIColor *volumeColor = MGVolumeColorFromHex(volumeIconColorHex);
        if (volumeSlider && volumeColor) {
            volumeIconApplied = MGApplyVolumeIconTint(volumeSlider, volumeColor, &volumeIconClass, &volumeIconFrame);
            volumePercentageApplied = MGApplyVolumePercentageTint(volumeSlider, volumeColor, &volumePercentageClass, &volumePercentageFrame, &volumePercentageText);
        }
    }

    if (!enabled || !exists) {
        MGRemoveTaggedImages(root, nil);
        NSString *sig = [NSString stringWithFormat:@"inactive|%@|%d|%d|icon=%d|%@", slot, enabled, exists, volumeIconApplied, volumeIconColorHex];
        MGDiagnosticOnce(controller, sig, [NSString stringWithFormat:@"apply source=%@ controller=%@ slot=%@ enabled=%d exists=%d expanded=0 result=removed volumeIconColorEnabled=%d volumeIconApplied=%d volumeIconColor=%@ volumeIconClass=%@ volumeIconFrame=%@ volumePercentageApplied=%d volumePercentageClass=%@ volumePercentageFrame=%@ volumePercentageText=%@", source, NSStringFromClass([controller class]), slot, enabled, exists, volumeIconColorEnabled, volumeIconApplied, volumeIconColorHex, volumeIconClass, NSStringFromCGRect(volumeIconFrame), volumePercentageApplied, volumePercentageClass, NSStringFromCGRect(volumePercentageFrame), volumePercentageText]);
        return;
    }

    UIView *parent = nil, *anchor = nil, *cornerSource = nil;
    CGRect imageFrame = CGRectZero;
    NSString *strategy = nil;
    if (!MGPrepareInsertion(root, slot, &parent, &anchor, &imageFrame, &cornerSource, &strategy) || !parent) return;

    UIImageView *imageView = MGImageViewInParent(parent);
    MGRemoveTaggedImages(root, imageView);

    if (imageView.superview != parent) [imageView removeFromSuperview];
    if (!imageView.superview) {
        if (anchor && anchor.superview == parent) [parent insertSubview:imageView aboveSubview:anchor];
        else [parent insertSubview:imageView atIndex:0];
    } else if (anchor && anchor.superview == parent) {
        [parent insertSubview:imageView aboveSubview:anchor];
    }

    NSString *loadedPath = objc_getAssociatedObject(imageView, @selector(setImage:));
    if (![loadedPath isEqualToString:path] || !imageView.image) {
        imageView.image = [UIImage imageWithContentsOfFile:path];
        objc_setAssociatedObject(imageView, @selector(setImage:), path, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    imageView.frame = imageFrame;
    imageView.alpha = opacity;
    imageView.hidden = imageView.image == nil;
    imageView.userInteractionEnabled = NO;
    MGCopyCornerGeometry(imageView, cornerSource, root);

    NSUInteger volumeSuppressed = 0;
    NSArray<NSString *> *volumeSuppressedClasses = @[];
    if ([slot isEqualToString:@"volume"]) {
        UIView *volumeSlider = MGFindSliderView(root);
        if (volumeSlider) {
            NSMutableArray<NSString *> *classes = [NSMutableArray array];
            volumeSuppressed = MGApplyVolumeImageMode(volumeSlider, imageView, classes);
            volumeSuppressedClasses = classes.copy;
            strategy = @"volume-image-first-test";
        } else {
            strategy = @"volume-no-slider-found";
        }
    }

    // Safety rule: these preferences are intentionally never implemented by mutating,
    // hiding, removing or reparenting Apple's material/effect views.
    BOOL glow = MGBoolPreference(@"CCModuleControlGlowEnabled", NO);
    CGFloat glowIntensity = MGFloatPreference(@"CCModuleControlGlowIntensity", 0.0);
    CGFloat glowWidth = MGFloatPreference(@"CCModuleControlGlowWidth", 0.0);

    NSString *sig = [NSString stringWithFormat:@"%@|%@|%d|%d|%.3f|%.0fx%.0f|%@", slot, strategy, enabled, exists, opacity, CGRectGetWidth(root.bounds), CGRectGetHeight(root.bounds), path];
    MGDiagnosticOnce(controller, sig,
                     [NSString stringWithFormat:@"apply source=%@ controller=%@ candidates=%@ slot=%@ path=%@ exists=%d enabled=%d imageLoaded=%d removeBlurPref=%d materialMutation=0 opacity=%.2f expanded=0 strategy=%@ root=%@ frame=%@ parent=%@ nativeBackground=%@ nativeFrame=%@ nativeRadius=%.2f imageFrame=%@ subviews=%lu imageView=%@ volumeSuppressed=%lu suppressedClasses=%@ volumeIconColorEnabled=%d volumeIconApplied=%d volumeIconColor=%@ volumeIconClass=%@ volumeIconFrame=%@ volumePercentageApplied=%d volumePercentageClass=%@ volumePercentageFrame=%@ volumePercentageText=%@ glowPref=%d glowIntensity=%.2f glowWidth=%.2f",
                      source, NSStringFromClass([controller class]), candidates, slot, path, exists, enabled, imageView.image != nil, removeBlur, opacity, strategy, NSStringFromClass(root.class), NSStringFromCGRect(root.frame), NSStringFromClass(parent.class), anchor ? NSStringFromClass(anchor.class) : @"<none>", anchor ? NSStringFromCGRect(anchor.frame) : @"<none>", cornerSource.layer.cornerRadius, NSStringFromCGRect(imageView.frame), (unsigned long)parent.subviews.count, imageView, (unsigned long)volumeSuppressed, volumeSuppressedClasses, volumeIconColorEnabled, volumeIconApplied, volumeIconColorHex, volumeIconClass, NSStringFromCGRect(volumeIconFrame), volumePercentageApplied, volumePercentageClass, NSStringFromCGRect(volumePercentageFrame), volumePercentageText, glow, glowIntensity, glowWidth]);
}

static void MGTrackAndApply(id controller, NSString *source) {
    if (!controller) return;
    @synchronized (MGControllers) { [MGControllers addObject:controller]; }
    MGApplyController(controller, source);
}

static void MGRefreshAll(NSString *source, BOOL forceReloadImages) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *controllers = nil;
        @synchronized (MGControllers) { controllers = MGControllers.allObjects; }
        for (id controller in controllers) {
            if (forceReloadImages && [controller respondsToSelector:@selector(view)]) MGRemoveTaggedImages([controller view], nil);
            objc_setAssociatedObject(controller, &MGLastDiagnosticKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
            MGApplyController(controller, source);
        }
        MGLog(@"refresh source=%@ controllers=%lu enabled=%d directoryExists=%d directory=%@", source, (unsigned long)controllers.count, MGBoolPreference(@"CCModuleBackgroundsEnabled", YES), [NSFileManager.defaultManager fileExistsAtPath:MGBackgroundDirectory], MGBackgroundDirectory);
    });
}

#pragma mark - Hooks

static void MGModuleViewDidLoad(id self, SEL _cmd) {
    if (MGOrigModuleViewDidLoad) MGOrigModuleViewDidLoad(self, _cmd);
    MGTrackAndApply(self, @"CCUIModuleContainerViewController.viewDidLoad");
}
static void MGModuleLayout(id self, SEL _cmd) {
    if (MGOrigModuleLayout) MGOrigModuleLayout(self, _cmd);
    MGTrackAndApply(self, @"CCUIModuleContainerViewController.layout");
}
static void MGContentViewDidLoad(id self, SEL _cmd) {
    if (MGOrigContentViewDidLoad) MGOrigContentViewDidLoad(self, _cmd);
    MGTrackAndApply(self, @"CCUIContentModuleContainerViewController.viewDidLoad");
}
static void MGContentLayout(id self, SEL _cmd) {
    if (MGOrigContentLayout) MGOrigContentLayout(self, _cmd);
    MGTrackAndApply(self, @"CCUIContentModuleContainerViewController.layout");
}

static void MGHookController(Class cls, IMP loadHook, IMP layoutHook, IMP *oldLoad, IMP *oldLayout) {
    if (!cls) return;
    SEL loadSel = @selector(viewDidLoad);
    SEL layoutSel = @selector(viewDidLayoutSubviews);
    if (class_getInstanceMethod(cls, loadSel)) MSHookMessageEx(cls, loadSel, loadHook, oldLoad);
    if (class_getInstanceMethod(cls, layoutSel)) MSHookMessageEx(cls, layoutSel, layoutHook, oldLayout);
}

static void MGPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *source = (__bridge NSString *)name ?: @"preferences.changed";
    MGRefreshAll(source, YES);
}

__attribute__((constructor)) static void MGInit(void) {
    @autoreleasepool {
        MGControllers = [NSHashTable weakObjectsHashTable];
        void *handle = dlopen("/System/Library/PrivateFrameworks/ControlCenterUI.framework/ControlCenterUI", RTLD_LAZY);
        Class moduleClass = NSClassFromString(@"CCUIModuleContainerViewController");
        Class contentClass = NSClassFromString(@"CCUIContentModuleContainerViewController");

        MGHookController(moduleClass, (IMP)MGModuleViewDidLoad, (IMP)MGModuleLayout, (IMP *)&MGOrigModuleViewDidLoad, (IMP *)&MGOrigModuleLayout);
        MGHookController(contentClass, (IMP)MGContentViewDidLoad, (IMP)MGContentLayout, (IMP *)&MGOrigContentViewDidLoad, (IMP *)&MGOrigContentLayout);

        CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterAddObserver(darwin, NULL, MGPrefsChanged, CFSTR("com.nextsolution.unlockvibrate/preferences.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(darwin, NULL, MGPrefsChanged, CFSTR("preferences.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(darwin, NULL, MGPrefsChanged, CFSTR("com.nextsolution.nextlog/control.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

        [NSFileManager.defaultManager createDirectoryAtPath:MGBackgroundDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        MGLog(@"ModuleGlassRuntime 1.0.10 Volume Icon+Percentage Color loaded SpringBoard=%@ prefsEnabled=%d", NSBundle.mainBundle.bundleIdentifier, MGBoolPreference(@"CCModuleBackgroundsEnabled", YES));
        MGLog(@"Volume-isolated image-first runtime with persistent icon color overlay process=%@ pid=%d dlopen=%p moduleClass=%@ contentClass=%@", NSProcessInfo.processInfo.processName, getpid(), handle, moduleClass, contentClass);
        MGLog(@"diagnostic-control active=%d prefsDomain=%@ backgroundDirectory=%@ log=%@", MGVerboseDiagnosticsEnabled(), (__bridge NSString *)MGPrefsDomain, MGBackgroundDirectory, MGLogPath);
    }
}
