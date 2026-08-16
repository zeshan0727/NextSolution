from pathlib import Path
import re

p = Path('source/ModuleGlass/Tweak.m')
t = p.read_text()

old = '''static void MGCopyCornerGeometry(UIImageView *imageView, UIView *source, UIView *fallback) {
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
}'''

new = '''static void MGCopyCornerGeometry(UIImageView *imageView, UIView *source, UIView *fallback) {
    UIView *geometrySource = source ?: fallback;
    CALayer *layer = geometrySource.layer ?: fallback.layer;
    CGFloat radius = layer.cornerRadius;
    if (radius <= 0.0) radius = fallback.layer.cornerRadius;
    imageView.layer.cornerRadius = MAX(0.0, radius);
    if (@available(iOS 13.0, *)) imageView.layer.cornerCurve = layer.cornerCurve ?: kCACornerCurveContinuous;
    imageView.layer.maskedCorners = layer.maskedCorners ?: kCALayerAllCorners;
    imageView.clipsToBounds = YES;
    imageView.layer.masksToBounds = YES;
    if (layer.mask) {
        CALayer *maskCopy = [layer.mask copy];
        maskCopy.frame = imageView.bounds;
        imageView.layer.mask = maskCopy;
    } else {
        imageView.layer.mask = nil;
    }
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
            if (outParent) *outParent = native.superview;
            if (outAnchor) *outAnchor = native;
            if (outFrame) *outFrame = native.frame;
            if (outCornerSource) *outCornerSource = native;
            if (outStrategy) *outStrategy = @"brightness-slider-native";
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

    // Standard compact modules: image belongs inside Apple's clipping/mask host.
    UIView *native = MGFindNativeBackground(root);
    if (native) {
        UIView *host = MGFindCompactClipHost(native, root);
        if (outParent) *outParent = host;
        if (outAnchor) *outAnchor = nil;
        if (outFrame) *outFrame = host.bounds;
        if (outCornerSource) *outCornerSource = host;
        if (outStrategy) *outStrategy = @"compact-native-host";
        return YES;
    }

    if (outParent) *outParent = root;
    if (outAnchor) *outAnchor = nil;
    if (outFrame) *outFrame = root.bounds;
    if (outCornerSource) *outCornerSource = root;
    if (outStrategy) *outStrategy = @"root-index0";
    return YES;
}'''

if old not in t:
    raise SystemExit('native insertion block anchor missing')
t = t.replace(old, new, 1)

anchor = 'static UIColor *MGVolumeColorFromHex(NSString *input) {'
brightness = '''static BOOL MGBrightnessObscuringVisual(UIView *view, UIView *slider, UIImageView *imageView) {
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

static UIColor *MGVolumeColorFromHex(NSString *input) {'''
if anchor not in t:
    raise SystemExit('brightness helper anchor missing')
t = t.replace(anchor, brightness, 1)

pattern = re.compile(
    r'imageFirstSuppressed\s*=\s*MGApplyVolumeImageMode\(imageScope,\s*imageView,\s*classes\);\s*'
    r'imageFirstSuppressedClasses\s*=\s*classes\.copy;\s*'
    r'strategy\s*=\s*\[NSString stringWithFormat:@"%@-image-first",\s*slot\];',
    re.S,
)
replacement = '''if ([slot isEqualToString:@"brightness"]) {
                imageFirstSuppressed = MGApplyBrightnessImageMode(imageScope, imageView, classes);
                strategy = @"brightness-fill-aware";
            } else {
                imageFirstSuppressed = MGApplyVolumeImageMode(imageScope, imageView, classes);
                strategy = [NSString stringWithFormat:@"%@-image-first", slot];
            }
            imageFirstSuppressedClasses = classes.copy;'''
t, n = pattern.subn(replacement, t, count=1)
if n != 1:
    raise SystemExit(f'image-first apply replacement count={n}')

t = t.replace('ModuleGlassRuntime 1.0.11 All Modules Image First loaded', 'ModuleGlassRuntime 1.0.12 Native Host Fix loaded')
p.write_text(t)

c = Path('source/ModuleGlass/control')
ct = c.read_text()
ct = re.sub(r'^Version: .*$', 'Version: 1.0.12', ct, flags=re.M)
ct = re.sub(
    r'^Description: .*$',
    'Description: Native-host Module Glass runtime that preserves the validated Volume renderer, adds Brightness fill-aware rendering, and clips standard module images through Apple compact hosts and masks.',
    ct,
    flags=re.M,
)
c.write_text(ct)

print('patched Module Glass native host runtime 1.0.12')
