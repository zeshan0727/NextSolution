from pathlib import Path
import re

p = Path('source/ModuleGlass/Tweak.m')
t = p.read_text()

old = '''    // Standard compact modules: image belongs inside Apple's clipping/mask host.
    UIView *native = MGFindNativeBackground(root);
    if (native) {
        UIView *host = MGFindCompactClipHost(native, root);
        if (outParent) *outParent = host;
        if (outAnchor) *outAnchor = nil;
        if (outFrame) *outFrame = host.bounds;
        if (outCornerSource) *outCornerSource = host;
        if (outStrategy) *outStrategy = @"compact-native-host";
        return YES;
    }'''
new = '''    // Standard compact modules use the exact successful Volume placement:
    // image is a sibling immediately above Apple's native background.
    UIView *native = MGFindNativeBackground(root);
    if (native && native.superview) {
        UIView *geometryHost = MGFindCompactClipHost(native, root);
        if (outParent) *outParent = native.superview;
        if (outAnchor) *outAnchor = native;
        if (outFrame) *outFrame = native.frame;
        if (outCornerSource) *outCornerSource = geometryHost ?: native;
        if (outStrategy) *outStrategy = @"volume-pattern-native-sibling";
        return YES;
    }'''
if old not in t:
    raise SystemExit('standard host block not found')
t = t.replace(old, new, 1)

old = '''    if (layer.mask) {
        CALayer *maskCopy = [layer.mask copy];
        maskCopy.frame = imageView.bounds;
        imageView.layer.mask = maskCopy;
    } else {
        imageView.layer.mask = nil;
    }'''
new = '''    imageView.layer.mask = nil;
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
    }'''
if old not in t:
    raise SystemExit('mask block not found')
t = t.replace(old, new, 1)

if 'static char MGBrightnessOriginalLayerOpacityKey;' not in t:
    t = t.replace('static char MGVolumeOriginalPercentageAttributedKey;\n', 'static char MGVolumeOriginalPercentageAttributedKey;\nstatic char MGBrightnessOriginalLayerOpacityKey;\n', 1)

anchor = 'static UIColor *MGVolumeColorFromHex(NSString *input) {'
helpers = '''static void MGRestoreBrightnessLayers(CALayer *layer) {
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

static UIColor *MGVolumeColorFromHex(NSString *input) {'''
if 'MGApplyBrightnessLayerMode' not in t:
    if anchor not in t:
        raise SystemExit('layer helper anchor not found')
    t = t.replace(anchor, helpers, 1)

if 'MGRestoreBrightnessLayers(root.layer);' not in t:
    t = t.replace('    MGRestoreVolumeVisuals(root);\n', '    MGRestoreVolumeVisuals(root);\n    MGRestoreBrightnessLayers(root.layer);\n', 1)

pattern = re.compile(r'''if \(\[slot isEqualToString:@"brightness"\]\) \{\s*imageFirstSuppressed\s*=\s*MGApplyBrightnessImageMode\(imageScope, imageView, classes\);\s*strategy\s*=\s*@"brightness-fill-aware";\s*\} else \{''', re.S)
replacement = '''if ([slot isEqualToString:@"brightness"]) {
                imageFirstSuppressed = MGApplyBrightnessImageMode(imageScope, imageView, classes);
                imageFirstSuppressed += MGApplyBrightnessLayerMode(imageScope.layer, imageScope.layer, imageView.layer, classes);
                strategy = @"brightness-volume-pattern-fill-aware";
            } else {'''
t, n = pattern.subn(replacement, t, count=1)
if n != 1:
    raise SystemExit(f'brightness call replacement count={n}')

t = t.replace('ModuleGlassRuntime 1.0.12 Native Host Fix loaded', 'ModuleGlassRuntime 1.0.13 Volume Pattern All Modules loaded')
p.write_text(t)

c = Path('source/ModuleGlass/control')
ct = c.read_text()
ct = re.sub(r'^Version: .*$', 'Version: 1.0.13', ct, flags=re.M)
ct = re.sub(r'^Description: .*$', 'Description: Volume-pattern Module Glass runtime: all compact modules place images like the validated Volume renderer, with Apple mask geometry and Brightness UIView/CALayer fill suppression.', ct, flags=re.M)
c.write_text(ct)

assert 'volume-pattern-native-sibling' in t
assert 'brightness-volume-pattern-fill-aware' in t
assert 'MGApplyBrightnessLayerMode' in t
assert 'ModuleGlassRuntime 1.0.13 Volume Pattern All Modules loaded' in t
print('patched Module Glass 1.0.17 / runtime 1.0.13')
