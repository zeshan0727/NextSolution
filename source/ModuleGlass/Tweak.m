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
static NSInteger const MGForegroundRepairOverlayTag = 0x4D474652;

static NSHashTable *MGControllers;
static char MGLastDiagnosticKey;
static char MGVolumeOriginalAlphaKey;
static char MGVolumeOriginalIconAlphaKey;
static char MGVolumeIconOverlayKey;
static char MGVolumeOriginalPercentageAlphaKey;
static char MGVolumePercentageColorKey;
static char MGVolumeOriginalPercentageTextColorKey;
static char MGVolumeOriginalPercentageAttributedKey;
static char MGBrightnessOriginalLayerOpacityKey;

static void (*MGOrigLabelSetText)(UILabel *, SEL, NSString *);
static void (*MGOrigLabelSetAttributedText)(UILabel *, SEL, NSAttributedString *);
static void (*MGOrigLabelSetTextColor)(UILabel *, SEL, UIColor *);

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

// Image-first helpers validated on Volume and now shared by all mapped compact modules.
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

static BOOL MGBrightnessObscuringVisual(UIView *view, UIView *slider, UIImageView *imageView) {
    if (!view || !slider || view == imageView || view.tag == MGImageTag) return NO;
    if ([imageView isDescendantOfView:view]) return NO;
    if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UILabel.class] || [view isKindOfClass:UIButton.class]) return NO;

    CGRect converted = [view convertRect:view.bounds toView:slider];
    CGFloat sliderArea = MAX(1.0, CGRectGetWidth(slider.bounds) * CGRectGetHeight(slider.bounds));
    CGFloat area = MAX(0.0, CGRectGetWidth(converted) * CGRectGetHeight(converted));
    CGFloat ratio = area / sliderArea;
    if (ratio < 0.08) return NO;

    NSString *name = NSStringFromClass(view.class).lowercaseString ?: @"";
    BOOL namedForeground = [name containsString:@"label"] || [name containsString:@"glyph"] ||
                           [name containsString:@"icon"] || [name containsString:@"button"] ||
                           [name containsString:@"text"] || [name containsString:@"percentage"] ||
                           [name containsString:@"sun"];
    if (namedForeground) return NO;

    if ([view isKindOfClass:UIImageView.class] && ratio < 0.16) return NO;

    BOOL namedVisual = [name containsString:@"material"] || [name containsString:@"effect"] ||
                       [name containsString:@"blur"] || [name containsString:@"fill"] ||
                       [name containsString:@"progress"] || [name containsString:@"background"] ||
                       [name containsString:@"tint"] || [name containsString:@"valueindicator"];
    BOOL largeImageVisual = [view isKindOfClass:UIImageView.class] && ratio >= 0.16;
    BOOL plainLargeVisual = ([name isEqualToString:@"uiview"] || [name containsString:@"visualeffectsubview"]) && ratio >= 0.18 && !MGVolumeSubtreeHasForeground(view);
    return namedVisual || largeImageVisual || plainLargeVisual;
}

static NSUInteger MGApplyBrightnessImageMode(UIView *slider, UIImageView *imageView, NSMutableArray<NSString *> *suppressedClasses) {
    if (!slider || !imageView) return 0;
    NSUInteger count = 0;
    for (UIView *child in slider.subviews) {
        if (child.tag == MGImageTag) continue;
        if (MGBrightnessObscuringVisual(child, slider, imageView)) {
            if (!objc_getAssociatedObject(child, &MGVolumeOriginalAlphaKey)) {
                objc_setAssociatedObject(child, &MGVolumeOriginalAlphaKey, @(child.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            child.alpha = 0.0;
            [suppressedClasses addObject:NSStringFromClass(child.class) ?: @"UIView"];
            count++;
            continue;
        }
        count += MGApplyBrightnessImageMode(child, imageView, suppressedClasses);
    }
    return count;
}

static void MGRestoreBrightnessLayers(CALayer *layer) {
    if (!layer) return;
    NSNumber *saved = objc_getAssociatedObject(layer, &MGBrightnessOriginalLayerOpacityKey);
    if (saved) {
        layer.opacity = saved.floatValue;
        objc_setAssociatedObject(layer, &MGBrightnessOriginalLayerOpacityKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (CALayer *child in layer.sublayers.copy) MGRestoreBrightnessLayers(child);
}

static BOOL MGLayerContainsLayer(CALayer *ancestor, CALayer *candidate) {
    CALayer *cursor = candidate;
    while (cursor) {
        if (cursor == ancestor) return YES;
        cursor = cursor.superlayer;
    }
    return NO;
}

static BOOL MGBrightnessObscuringLayer(CALayer *layer, CALayer *sliderLayer, CALayer *imageLayer) {
    if (!layer || !sliderLayer || layer == imageLayer || MGLayerContainsLayer(layer, imageLayer)) return NO;
    CGRect converted = [layer convertRect:layer.bounds toLayer:sliderLayer];
    CGFloat sliderArea = MAX(1.0, CGRectGetWidth(sliderLayer.bounds) * CGRectGetHeight(sliderLayer.bounds));
    CGFloat area = MAX(0.0, CGRectGetWidth(converted) * CGRectGetHeight(converted));
    CGFloat ratio = area / sliderArea;
    if (ratio < 0.10) return NO;
    NSString *name = NSStringFromClass(layer.class).lowercaseString ?: @"";
    BOOL namedVisual = [name containsString:@"fill"] || [name containsString:@"progress"] ||
                       [name containsString:@"background"] || [name containsString:@"material"] ||
                       [name containsString:@"tint"] || [name containsString:@"backdrop"];
    BOOL leafSolid = layer.sublayers.count == 0 && layer.backgroundColor != NULL && ratio >= 0.16;
    BOOL leafImage = layer.sublayers.count == 0 && layer.contents != nil && ratio >= 0.18;
    return namedVisual || leafSolid || leafImage;
}

static NSUInteger MGApplyBrightnessLayerMode(CALayer *layer, CALayer *sliderLayer, CALayer *imageLayer, NSMutableArray<NSString *> *classes) {
    if (!layer || !sliderLayer || !imageLayer) return 0;
    NSUInteger count = 0;
    for (CALayer *child in layer.sublayers.copy) {
        if (child == imageLayer) continue;
        if (MGBrightnessObscuringLayer(child, sliderLayer, imageLayer)) {
            if (!objc_getAssociatedObject(child, &MGBrightnessOriginalLayerOpacityKey))
                objc_setAssociatedObject(child, &MGBrightnessOriginalLayerOpacityKey, @(child.opacity), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            child.opacity = 0.0f;
            [classes addObject:[NSString stringWithFormat:@"layer:%@", NSStringFromClass(child.class) ?: @"CALayer"]];
            count++;
            continue;
        }
        count += MGApplyBrightnessLayerMode(child, sliderLayer, imageLayer, classes);
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
        UILabel *label=(UILabel *)root;
        UIColor *custom=objc_getAssociatedObject(label, &MGVolumePercentageColorKey);
        if (custom) {
            objc_setAssociatedObject(label, &MGVolumePercentageColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            id originalColor=objc_getAssociatedObject(label, &MGVolumeOriginalPercentageTextColorKey);
            NSAttributedString *originalAttributed=objc_getAssociatedObject(label, &MGVolumeOriginalPercentageAttributedKey);
            if (MGOrigLabelSetTextColor) {
                MGOrigLabelSetTextColor(label, @selector(setTextColor:), [originalColor isKindOfClass:UIColor.class] ? originalColor : nil);
            } else {
                label.textColor=[originalColor isKindOfClass:UIColor.class] ? originalColor : nil;
            }
            if (originalAttributed) {
                if (MGOrigLabelSetAttributedText) MGOrigLabelSetAttributedText(label, @selector(setAttributedText:), originalAttributed);
                else label.attributedText=originalAttributed;
            }
            objc_setAssociatedObject(label, &MGVolumeOriginalPercentageTextColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(label, &MGVolumeOriginalPercentageAttributedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSNumber *savedAlpha=objc_getAssociatedObject(label, &MGVolumeOriginalPercentageAlphaKey);
        if (savedAlpha) {
            label.alpha=savedAlpha.doubleValue;
            objc_setAssociatedObject(label, &MGVolumeOriginalPercentageAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

static NSAttributedString *MGAttributedStringWithColor(NSAttributedString *input, UIColor *color) {
    if (!input || !color || input.length == 0) return input;
    NSMutableAttributedString *result=[input mutableCopy];
    [result addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(0, result.length)];
    return result;
}

static void MGLabelSetText(UILabel *label, SEL _cmd, NSString *text) {
    if (MGOrigLabelSetText) MGOrigLabelSetText(label, _cmd, text);
    UIColor *custom=objc_getAssociatedObject(label, &MGVolumePercentageColorKey);
    if (custom && MGOrigLabelSetTextColor) MGOrigLabelSetTextColor(label, @selector(setTextColor:), custom);
}

static void MGLabelSetAttributedText(UILabel *label, SEL _cmd, NSAttributedString *text) {
    UIColor *custom=objc_getAssociatedObject(label, &MGVolumePercentageColorKey);
    if (!custom) {
        if (MGOrigLabelSetAttributedText) MGOrigLabelSetAttributedText(label, _cmd, text);
        return;
    }
    if (text) objc_setAssociatedObject(label, &MGVolumeOriginalPercentageAttributedKey, [text copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSAttributedString *colored=MGAttributedStringWithColor(text, custom);
    if (MGOrigLabelSetAttributedText) MGOrigLabelSetAttributedText(label, _cmd, colored);
}

static void MGLabelSetTextColor(UILabel *label, SEL _cmd, UIColor *color) {
    UIColor *custom=objc_getAssociatedObject(label, &MGVolumePercentageColorKey);
    if (!custom) {
        if (MGOrigLabelSetTextColor) MGOrigLabelSetTextColor(label, _cmd, color);
        return;
    }
    objc_setAssociatedObject(label, &MGVolumeOriginalPercentageTextColorKey, color ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (MGOrigLabelSetTextColor) MGOrigLabelSetTextColor(label, _cmd, custom);
}

static BOOL MGApplyVolumePercentageTint(UIView *slider, UIColor *color, NSString **outClass, CGRect *outFrame, NSString **outText) {
    if (!slider || !color) return NO;
    UILabel *label=MGFindVolumePercentageLabel(slider);
    if (!label) return NO;

    if (!objc_getAssociatedObject(label, &MGVolumeOriginalPercentageTextColorKey)) {
        objc_setAssociatedObject(label, &MGVolumeOriginalPercentageTextColorKey, label.textColor ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (label.attributedText.length && !objc_getAssociatedObject(label, &MGVolumeOriginalPercentageAttributedKey)) {
        objc_setAssociatedObject(label, &MGVolumeOriginalPercentageAttributedKey, [label.attributedText copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(label, &MGVolumePercentageColorKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (label.attributedText.length) {
        NSAttributedString *colored=MGAttributedStringWithColor(label.attributedText, color);
        if (MGOrigLabelSetAttributedText) MGOrigLabelSetAttributedText(label, @selector(setAttributedText:), colored);
        else label.attributedText=colored;
    }
    if (MGOrigLabelSetTextColor) MGOrigLabelSetTextColor(label, @selector(setTextColor:), color);
    else label.textColor=color;

    if (outClass) *outClass=[NSString stringWithFormat:@"%@+live-native", NSStringFromClass(label.class) ?: @"UILabel"];
    if (outFrame) *outFrame=[label convertRect:label.bounds toView:slider];
    if (outText) *outText=label.text ?: label.attributedText.string ?: @"";
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
    UIView *geometrySource = source ?: fallback;
    CALayer *layer = geometrySource.layer ?: fallback.layer;
    CGFloat radius = layer.cornerRadius;
    if (radius <= 0.0) radius = fallback.layer.cornerRadius;
    imageView.layer.cornerRadius = MAX(0.0, radius);
    if (@available(iOS 13.0, *)) imageView.layer.cornerCurve = layer.cornerCurve ?: kCACornerCurveContinuous;
    imageView.layer.maskedCorners = layer.maskedCorners ?: kCALayerAllCorners;
    imageView.clipsToBounds = YES;
    imageView.layer.masksToBounds = YES;
    imageView.layer.mask = nil;
    if ([layer.mask isKindOfClass:CAShapeLayer.class] && ((CAShapeLayer *)layer.mask).path) {
        CAShapeLayer *sourceMask = (CAShapeLayer *)layer.mask;
        CGRect srcBounds = geometrySource.bounds;
        CGRect dstBounds = imageView.bounds;
        CGFloat sx = CGRectGetWidth(srcBounds) > 0.0 ? CGRectGetWidth(dstBounds) / CGRectGetWidth(srcBounds) : 1.0;
        CGFloat sy = CGRectGetHeight(srcBounds) > 0.0 ? CGRectGetHeight(dstBounds) / CGRectGetHeight(srcBounds) : 1.0;
        CGAffineTransform transform = CGAffineTransformMakeScale(sx, sy);
        CGPathRef scaledPath = CGPathCreateCopyByTransformingPath(sourceMask.path, &transform);
        CAShapeLayer *maskCopy = [CAShapeLayer layer];
        maskCopy.frame = imageView.bounds;
        maskCopy.path = scaledPath;
        maskCopy.fillRule = sourceMask.fillRule;
        imageView.layer.mask = maskCopy;
        if (scaledPath) CGPathRelease(scaledPath);
    } else if (layer.mask) {
        CGSize src = geometrySource.bounds.size;
        CGSize dst = imageView.bounds.size;
        if (fabs(src.width - dst.width) <= 2.0 && fabs(src.height - dst.height) <= 2.0) {
            CALayer *maskCopy = [layer.mask copy];
            maskCopy.frame = imageView.bounds;
            imageView.layer.mask = maskCopy;
        }
    }
}

static NSInteger MGShapeCandidateScore(UIView *candidate, UIView *root, CGRect targetRect) {
    if (!candidate || !root || candidate.tag == MGImageTag || candidate.hidden) return NSIntegerMin;
    CALayer *layer = candidate.layer;
    BOOL hasMask = layer.mask != nil || candidate.maskView != nil;
    BOOL hasRadius = layer.cornerRadius > 1.0;
    if (!hasMask && !hasRadius) return NSIntegerMin;

    CGRect rect = [candidate convertRect:candidate.bounds toView:root];
    CGFloat tw = CGRectGetWidth(targetRect), th = CGRectGetHeight(targetRect);
    CGFloat rw = CGRectGetWidth(rect), rh = CGRectGetHeight(rect);
    if (tw <= 1.0 || th <= 1.0 || rw <= 1.0 || rh <= 1.0) return NSIntegerMin;

    CGFloat widthDiff = fabs(rw - tw);
    CGFloat heightDiff = fabs(rh - th);
    CGFloat centerDiff = hypot(CGRectGetMidX(rect) - CGRectGetMidX(targetRect), CGRectGetMidY(rect) - CGRectGetMidY(targetRect));
    if (widthDiff > 10.0 || heightDiff > 10.0 || centerDiff > 10.0) return NSIntegerMin;

    NSInteger score = 10000;
    score -= (NSInteger)(widthDiff * 100.0 + heightDiff * 100.0 + centerDiff * 80.0);
    if (hasMask) score += 5000;
    if (hasRadius) score += 3000;
    NSString *name = NSStringFromClass(candidate.class).lowercaseString ?: @"";
    if ([name containsString:@"background"] || [name containsString:@"material"] || [name containsString:@"module"] || [name containsString:@"container"]) score += 800;
    return score;
}

static void MGFindMatchingShapeRecursive(UIView *node, UIView *root, CGRect targetRect, UIView **best, NSInteger *bestScore) {
    if (!node || !root) return;
    NSInteger score = MGShapeCandidateScore(node, root, targetRect);
    if (score > *bestScore) {
        *best = node;
        *bestScore = score;
    }
    for (UIView *child in node.subviews) {
        if (child.tag == MGImageTag) continue;
        MGFindMatchingShapeRecursive(child, root, targetRect, best, bestScore);
    }
}

static UIView *MGFindMatchingAppleShape(UIView *native, UIView *root) {
    if (!native || !root) return nil;
    CGRect targetRect = [native convertRect:native.bounds toView:root];
    UIView *best = nil;
    NSInteger bestScore = NSIntegerMin;
    MGFindMatchingShapeRecursive(root, root, targetRect, &best, &bestScore);
    return best;
}

static void MGApplyModuleShapeFallback(UIImageView *imageView, NSString *slot) {
    if (!imageView || [slot isEqualToString:@"volume"]) return; // validated Volume path stays untouched
    if (imageView.layer.mask || imageView.layer.cornerRadius > 1.0) return;

    CGFloat w = CGRectGetWidth(imageView.bounds);
    CGFloat h = CGRectGetHeight(imageView.bounds);
    CGFloat d = MIN(w, h);
    if (d <= 1.0) return;

    // Sliders are pills. Standard iOS 16 Control Center modules use roughly 22pt corners
    // at 77pt and ~30-32pt at larger compact sizes. This is only a fallback when Apple
    // exposes no usable mask/radius in the live hierarchy.
    CGFloat radius = [slot isEqualToString:@"brightness"] ? (d * 0.5) : MIN(32.0, d * 0.285);
    imageView.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) imageView.layer.cornerCurve = kCACornerCurveContinuous;
    imageView.clipsToBounds = YES;
    imageView.layer.masksToBounds = YES;
}

static CGFloat MGViewArea(UIView *view) {
    if (!view) return 0.0;
    return MAX(0.0, CGRectGetWidth(view.bounds) * CGRectGetHeight(view.bounds));
}

static NSInteger MGCompactHostScore(UIView *view, UIView *root, UIView *native) {
    if (!view || !root) return NSIntegerMin;
    CGFloat rootArea = MAX(1.0, MGViewArea(root));
    CGFloat area = MGViewArea(view);
    if (area < 16.0) return NSIntegerMin;
    CGFloat ratio = area / rootArea;
    NSInteger score = 0;
    if (view.layer.mask) score += 7000;
    if (view.clipsToBounds || view.layer.masksToBounds) score += 3000;
    if (view.layer.cornerRadius > 1.0) score += 2400;
    if (ratio >= 0.72 && ratio <= 1.28) score += 2200;
    else if (ratio >= 0.45 && ratio <= 1.45) score += 900;
    else score -= 1200;
    NSString *name = NSStringFromClass(view.class).lowercaseString ?: @"";
    if ([name containsString:@"module"] || [name containsString:@"container"]) score += 500;
    if ([name containsString:@"background"] || [name containsString:@"material"]) score += 650;
    if (view == native) score += 350;
    if (view == root) score -= 250;
    return score;
}

static UIView *MGFindCompactClipHost(UIView *native, UIView *root) {
    if (!native || !root) return native ?: root;
    UIView *best = native;
    NSInteger bestScore = MGCompactHostScore(native, root, native);
    UIView *cursor = native.superview;
    NSInteger depth = 0;
    while (cursor && depth++ < 8) {
        NSInteger score = MGCompactHostScore(cursor, root, native);
        if (score > bestScore) { best = cursor; bestScore = score; }
        if (cursor == root) break;
        cursor = cursor.superview;
    }
    return best ?: native;
}

static BOOL MGPrepareInsertion(UIView *root, NSString *slot, UIView **outParent, UIView **outAnchor, CGRect *outFrame, UIView **outCornerSource, NSString **outStrategy) {
    // Freeze the already-validated Volume path exactly as it was in 1.0.15.
    if ([slot isEqualToString:@"volume"]) {
        UIView *scope = MGFindSliderView(root) ?: root;
        UIView *native = MGFindNativeBackground(scope);
        if (native.superview) {
            if (outParent) *outParent = native.superview;
            if (outAnchor) *outAnchor = native;
            if (outFrame) *outFrame = native.frame;
            if (outCornerSource) *outCornerSource = native;
            if (outStrategy) *outStrategy = @"slider-native";
            return YES;
        }
        if (scope != root) {
            if (outParent) *outParent = scope;
            if (outAnchor) *outAnchor = nil;
            if (outFrame) *outFrame = scope.bounds;
            if (outCornerSource) *outCornerSource = scope;
            if (outStrategy) *outStrategy = @"slider-index0";
            return YES;
        }
    }

    // Brightness remains a slider, but uses its own fill-aware visual pass below.
    if ([slot isEqualToString:@"brightness"]) {
        UIView *scope = MGFindSliderView(root) ?: root;
        UIView *native = MGFindNativeBackground(scope);
        if (native.superview) {
            UIView *matchingShape = MGFindMatchingAppleShape(native, root);
            if (outParent) *outParent = native.superview;
            if (outAnchor) *outAnchor = native;
            if (outFrame) *outFrame = native.frame;
            if (outCornerSource) *outCornerSource = matchingShape ?: native;
            if (outStrategy) *outStrategy = @"brightness-volume-pattern-native-sibling";
            return YES;
        }
        if (scope != root) {
            if (outParent) *outParent = scope;
            if (outAnchor) *outAnchor = nil;
            if (outFrame) *outFrame = scope.bounds;
            if (outCornerSource) *outCornerSource = scope;
            if (outStrategy) *outStrategy = @"brightness-slider-index0";
            return YES;
        }
    }

    // Standard compact modules use the exact successful Volume placement:
    // image is a sibling immediately above Apple's native background.
    UIView *native = MGFindNativeBackground(root);
    if (native && native.superview) {
        UIView *matchingShape = MGFindMatchingAppleShape(native, root);
        UIView *geometryHost = matchingShape ?: MGFindCompactClipHost(native, root);
        if (outParent) *outParent = native.superview;
        if (outAnchor) *outAnchor = native;
        if (outFrame) *outFrame = native.frame;
        if (outCornerSource) *outCornerSource = geometryHost ?: native;
        if (outStrategy) *outStrategy = matchingShape ? @"volume-pattern-native-sibling-apple-shape" : @"volume-pattern-native-sibling-fallback-shape";
        return YES;
    }

    if (outParent) *outParent = root;
    if (outAnchor) *outAnchor = nil;
    if (outFrame) *outFrame = root.bounds;
    if (outCornerSource) *outCornerSource = root;
    if (outStrategy) *outStrategy = @"root-index0";
    return YES;
}


static void MGRemoveForegroundRepairOverlays(UIView *root) {
    if (!root) return;
    for (UIView *child in [root.subviews copy]) {
        if (child.tag == MGForegroundRepairOverlayTag) {
            [child removeFromSuperview];
            continue;
        }
        MGRemoveForegroundRepairOverlays(child);
    }
}

static CGFloat MGClamp01(CGFloat value) {
    if (!isfinite(value)) return -1.0;
    return MIN(1.0, MAX(0.0, value));
}

static CGFloat MGVolumeValueFraction(UIView *slider) {
    if (!slider) return -1.0;

    // The live percentage label is the most reliable source on iOS 16 because it is
    // the same value Apple is presenting to the user.
    UILabel *percentage = MGFindVolumePercentageLabel(slider);
    NSString *text = percentage.text ?: percentage.attributedText.string ?: @"";
    NSScanner *scanner = [NSScanner scannerWithString:text];
    double percent = 0.0;
    if ([scanner scanDouble:&percent] && [text containsString:@"%"] && percent >= 0.0 && percent <= 100.0) {
        return MGClamp01((CGFloat)(percent / 100.0));
    }

    // Fallback to common slider value keys. Values in 0...1 are used directly;
    // 0...100 is treated as a percentage.
    for (NSString *key in @[@"value", @"_value", @"normalizedValue", @"valueFraction", @"percentage"]) {
        @try {
            id obj = [slider valueForKey:key];
            if ([obj respondsToSelector:@selector(doubleValue)]) {
                double v = [obj doubleValue];
                if (isfinite(v)) {
                    if (v >= 0.0 && v <= 1.0) return MGClamp01((CGFloat)v);
                    if (v >= 0.0 && v <= 100.0) return MGClamp01((CGFloat)(v / 100.0));
                }
            }
        } @catch (__unused NSException *e) {}
    }
    return -1.0;
}

static CGRect MGVolumeValueSizedFrame(CGRect fullFrame, UIView *slider, CGFloat *outFraction) {
    CGFloat fraction = MGVolumeValueFraction(slider);
    if (outFraction) *outFraction = fraction;
    if (fraction < 0.0) return fullFrame;

    CGFloat fullHeight = CGRectGetHeight(fullFrame);
    CGFloat width = CGRectGetWidth(fullFrame);
    if (fullHeight <= 1.0 || width <= 1.0) return fullFrame;

    // Match the visual behavior the user approved on Brightness: the visible pill
    // shrinks upward/downward with the value but never becomes thinner than one
    // circular cap, which is how Apple's continuous slider fill behaves at low values.
    CGFloat minCap = MIN(width, fullHeight);
    CGFloat visibleHeight = MAX(minCap, fullHeight * fraction);
    visibleHeight = MIN(fullHeight, visibleHeight);

    CGRect frame = fullFrame;
    frame.origin.y = CGRectGetMaxY(fullFrame) - visibleHeight;
    frame.size.height = visibleHeight;
    return frame;
}

static UIView *MGTopChildUnderParent(UIView *view, UIView *parent) {
    if (!view || !parent) return nil;
    UIView *cursor = view;
    UIView *previous = view;
    while (cursor && cursor != parent) {
        previous = cursor;
        cursor = cursor.superview;
    }
    return cursor == parent ? previous : nil;
}

static BOOL MGImageViewLooksLikeSmallGlyph(UIImageView *iv, UIView *parent) {
    if (!iv || !iv.image || iv.hidden || iv.tag == MGImageTag ||
        iv.tag == MGVolumeIconOverlayTag || iv.tag == MGForegroundRepairOverlayTag) return NO;
    CGRect rect = [iv convertRect:iv.bounds toView:parent];
    CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
    if (w < 6.0 || h < 6.0 || w > 68.0 || h > 68.0) return NO;
    return YES;
}

static NSUInteger MGRepairCoveredForegroundImagesRecursive(UIView *node, UIView *parent, UIImageView *backgroundImage) {
    if (!node || !parent || !backgroundImage) return 0;
    NSUInteger count = 0;

    if ([node isKindOfClass:UIImageView.class]) {
        UIImageView *source = (UIImageView *)node;
        if (MGImageViewLooksLikeSmallGlyph(source, parent)) {
            UIView *top = MGTopChildUnderParent(source, parent);
            NSInteger imageIndex = [parent.subviews indexOfObject:backgroundImage];
            NSInteger topIndex = top ? [parent.subviews indexOfObject:top] : NSNotFound;
            BOOL covered = top && imageIndex != NSNotFound && topIndex != NSNotFound && topIndex < imageIndex;
            if (covered) {
                CGRect frame = [source convertRect:source.bounds toView:parent];
                UIImageView *overlay = [[UIImageView alloc] initWithFrame:frame];
                overlay.tag = MGForegroundRepairOverlayTag;
                overlay.userInteractionEnabled = NO;
                overlay.backgroundColor = UIColor.clearColor;
                overlay.image = source.image;
                overlay.tintColor = source.tintColor;
                overlay.contentMode = source.contentMode;
                overlay.clipsToBounds = source.clipsToBounds;
                overlay.alpha = source.alpha;
                overlay.layer.cornerRadius = source.layer.cornerRadius;
                overlay.layer.masksToBounds = source.layer.masksToBounds;
                [parent addSubview:overlay];
                count++;
            }
        }
    }

    for (UIView *child in node.subviews) {
        if (child.tag == MGImageTag || child.tag == MGForegroundRepairOverlayTag) continue;
        count += MGRepairCoveredForegroundImagesRecursive(child, parent, backgroundImage);
    }
    return count;
}

static NSUInteger MGRepairCoveredForegroundImages(UIView *root, UIView *parent, UIImageView *backgroundImage, NSString *slot) {
    if (!root || !parent || !backgroundImage) return 0;
    // Slider foreground is already handled by its native controls and the dedicated
    // Volume icon/percentage logic. This repair is only for standard compact modules.
    if ([slot isEqualToString:@"volume"] || [slot isEqualToString:@"brightness"]) return 0;
    return MGRepairCoveredForegroundImagesRecursive(root, parent, backgroundImage);
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
    MGRemoveForegroundRepairOverlays(root);
    MGRestoreVolumeColorPresentation(root);
    MGRestoreVolumeVisuals(root);
    MGRestoreBrightnessLayers(root.layer);
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
    CGFloat volumeValueFraction = -1.0;
    if ([slot isEqualToString:@"volume"]) {
        UIView *volumeSlider = MGFindSliderView(root);
        imageFrame = MGVolumeValueSizedFrame(imageFrame, volumeSlider, &volumeValueFraction);
    }
    imageView.frame = imageFrame;
    imageView.alpha = opacity;
    imageView.hidden = imageView.image == nil;
    imageView.userInteractionEnabled = NO;
    MGCopyCornerGeometry(imageView, cornerSource, root);
    MGApplyModuleShapeFallback(imageView, slot);
    if ([slot isEqualToString:@"volume"] && volumeValueFraction >= 0.0) {
        CGFloat cap = MIN(CGRectGetWidth(imageView.bounds), CGRectGetHeight(imageView.bounds));
        imageView.layer.cornerRadius = cap * 0.5;
        if (@available(iOS 13.0, *)) imageView.layer.cornerCurve = kCACornerCurveContinuous;
        imageView.layer.mask = nil;
        imageView.clipsToBounds = YES;
        imageView.layer.masksToBounds = YES;
    }

    NSUInteger imageFirstSuppressed = 0;
    NSArray<NSString *> *imageFirstSuppressedClasses = @[];
    if (imageView.image) {
        UIView *imageScope = [slot isEqualToString:@"volume"] ? MGFindSliderView(root) : root;
        if (!imageScope) imageScope=root;
        if (imageScope) {
            NSMutableArray<NSString *> *classes=[NSMutableArray array];
            if ([slot isEqualToString:@"brightness"]) {
                imageFirstSuppressed = MGApplyBrightnessImageMode(imageScope, imageView, classes);
                imageFirstSuppressed += MGApplyBrightnessLayerMode(root.layer, root.layer, imageView.layer, classes);
                strategy = @"brightness-volume-pattern-root-fill-aware";
            } else {
                imageFirstSuppressed = MGApplyVolumeImageMode(imageScope, imageView, classes);
                strategy = [NSString stringWithFormat:@"%@-image-first", slot];
            }
            imageFirstSuppressedClasses = classes.copy;
        } else {
            strategy=[NSString stringWithFormat:@"%@-no-host", slot];
        }
    }

    NSUInteger repairedForegroundGlyphs = MGRepairCoveredForegroundImages(root, parent, imageView, slot);
    if ([slot isEqualToString:@"volume"] && volumeValueFraction >= 0.0) {
        strategy = [NSString stringWithFormat:@"volume-value-sized-%.0f", volumeValueFraction * 100.0];
    }

    // Safety rule: these preferences are intentionally never implemented by mutating,
    // hiding, removing or reparenting Apple's material/effect views.
    BOOL glow = MGBoolPreference(@"CCModuleControlGlowEnabled", NO);
    CGFloat glowIntensity = MGFloatPreference(@"CCModuleControlGlowIntensity", 0.0);
    CGFloat glowWidth = MGFloatPreference(@"CCModuleControlGlowWidth", 0.0);

    NSString *sig = [NSString stringWithFormat:@"%@|%@|%d|%d|%.3f|%.0fx%.0f|%@", slot, strategy, enabled, exists, opacity, CGRectGetWidth(root.bounds), CGRectGetHeight(root.bounds), path];
    MGDiagnosticOnce(controller, sig,
                     [NSString stringWithFormat:@"apply source=%@ controller=%@ candidates=%@ slot=%@ path=%@ exists=%d enabled=%d imageLoaded=%d removeBlurPref=%d materialMutation=0 opacity=%.2f expanded=0 strategy=%@ root=%@ frame=%@ parent=%@ nativeBackground=%@ nativeFrame=%@ nativeRadius=%.2f imageFrame=%@ subviews=%lu imageView=%@ imageFirstSuppressed=%lu suppressedClasses=%@ volumeValueFraction=%.3f repairedForegroundGlyphs=%lu volumeIconColorEnabled=%d volumeIconApplied=%d volumeIconColor=%@ volumeIconClass=%@ volumeIconFrame=%@ volumePercentageApplied=%d volumePercentageClass=%@ volumePercentageFrame=%@ volumePercentageText=%@ glowPref=%d glowIntensity=%.2f glowWidth=%.2f",
                      source, NSStringFromClass([controller class]), candidates, slot, path, exists, enabled, imageView.image != nil, removeBlur, opacity, strategy, NSStringFromClass(root.class), NSStringFromCGRect(root.frame), NSStringFromClass(parent.class), anchor ? NSStringFromClass(anchor.class) : @"<none>", anchor ? NSStringFromCGRect(anchor.frame) : @"<none>", cornerSource.layer.cornerRadius, NSStringFromCGRect(imageView.frame), (unsigned long)parent.subviews.count, imageView, (unsigned long)imageFirstSuppressed, imageFirstSuppressedClasses, volumeValueFraction, (unsigned long)repairedForegroundGlyphs, volumeIconColorEnabled, volumeIconApplied, volumeIconColorHex, volumeIconClass, NSStringFromCGRect(volumeIconFrame), volumePercentageApplied, volumePercentageClass, NSStringFromCGRect(volumePercentageFrame), volumePercentageText, glow, glowIntensity, glowWidth]);
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

        MSHookMessageEx(UILabel.class, @selector(setText:), (IMP)MGLabelSetText, (IMP *)&MGOrigLabelSetText);
        MSHookMessageEx(UILabel.class, @selector(setAttributedText:), (IMP)MGLabelSetAttributedText, (IMP *)&MGOrigLabelSetAttributedText);
        MSHookMessageEx(UILabel.class, @selector(setTextColor:), (IMP)MGLabelSetTextColor, (IMP *)&MGOrigLabelSetTextColor);

        CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterAddObserver(darwin, NULL, MGPrefsChanged, CFSTR("com.nextsolution.unlockvibrate/preferences.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(darwin, NULL, MGPrefsChanged, CFSTR("preferences.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(darwin, NULL, MGPrefsChanged, CFSTR("com.nextsolution.nextlog/control.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

        [NSFileManager.defaultManager createDirectoryAtPath:MGBackgroundDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        MGLog(@"ModuleGlassRuntime 1.0.15 Volume Value + Foreground Fix loaded SpringBoard=%@ prefsEnabled=%d", NSBundle.mainBundle.bundleIdentifier, MGBoolPreference(@"CCModuleBackgroundsEnabled", YES));
        MGLog(@"Volume value-sized runtime with repaired covered compact foreground glyphs process=%@ pid=%d dlopen=%p moduleClass=%@ contentClass=%@", NSProcessInfo.processInfo.processName, getpid(), handle, moduleClass, contentClass);
        MGLog(@"diagnostic-control active=%d prefsDomain=%@ backgroundDirectory=%@ log=%@", MGVerboseDiagnosticsEnabled(), (__bridge NSString *)MGPrefsDomain, MGBackgroundDirectory, MGLogPath);
    }
}
