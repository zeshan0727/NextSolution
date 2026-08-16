from pathlib import Path
import re

p = Path('source/ModuleGlass/Tweak.m')
t = p.read_text()

# 1) Add a robust Apple-shape resolver plus safe iOS 16 fallback.
anchor = '''static CGFloat MGViewArea(UIView *view) {
'''
insert = r'''static NSInteger MGShapeCandidateScore(UIView *candidate, UIView *root, CGRect targetRect) {
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
'''
if anchor not in t:
    raise SystemExit('shape resolver anchor missing')
t = t.replace(anchor, insert, 1)

# 2) Standard modules stay in the successful Volume sibling placement, but source shape
#    from an Apple view with the same visible frame when available.
old = '''        UIView *geometryHost = MGFindCompactClipHost(native, root);
        if (outParent) *outParent = native.superview;
        if (outAnchor) *outAnchor = native;
        if (outFrame) *outFrame = native.frame;
        if (outCornerSource) *outCornerSource = geometryHost ?: native;
        if (outStrategy) *outStrategy = @"volume-pattern-native-sibling";
'''
new = '''        UIView *matchingShape = MGFindMatchingAppleShape(native, root);
        UIView *geometryHost = matchingShape ?: MGFindCompactClipHost(native, root);
        if (outParent) *outParent = native.superview;
        if (outAnchor) *outAnchor = native;
        if (outFrame) *outFrame = native.frame;
        if (outCornerSource) *outCornerSource = geometryHost ?: native;
        if (outStrategy) *outStrategy = matchingShape ? @"volume-pattern-native-sibling-apple-shape" : @"volume-pattern-native-sibling-fallback-shape";
'''
if old not in t:
    raise SystemExit('standard placement anchor missing')
t = t.replace(old, new, 1)

# 3) Brightness uses the same sibling placement, but look for the matching Apple pill shape.
old = '''            if (outParent) *outParent = native.superview;
            if (outAnchor) *outAnchor = native;
            if (outFrame) *outFrame = native.frame;
            if (outCornerSource) *outCornerSource = native;
            if (outStrategy) *outStrategy = @"brightness-slider-native";
'''
new = '''            UIView *matchingShape = MGFindMatchingAppleShape(native, root);
            if (outParent) *outParent = native.superview;
            if (outAnchor) *outAnchor = native;
            if (outFrame) *outFrame = native.frame;
            if (outCornerSource) *outCornerSource = matchingShape ?: native;
            if (outStrategy) *outStrategy = @"brightness-volume-pattern-native-sibling";
'''
if old not in t:
    raise SystemExit('brightness placement anchor missing')
t = t.replace(old, new, 1)

# 4) Apply the fallback only after copying any real Apple mask/radius.
old = '''    MGCopyCornerGeometry(imageView, cornerSource, root);

    NSUInteger imageFirstSuppressed = 0;
'''
new = '''    MGCopyCornerGeometry(imageView, cornerSource, root);
    MGApplyModuleShapeFallback(imageView, slot);

    NSUInteger imageFirstSuppressed = 0;
'''
if old not in t:
    raise SystemExit('shape fallback call anchor missing')
t = t.replace(old, new, 1)

# 5) Volume continues using its slider subtree. Brightness suppresses from the entire module
#    root so its white fill cannot escape through a sibling/outer layer hierarchy.
old = '''        BOOL sliderModule=[slot isEqualToString:@"volume"] || [slot isEqualToString:@"brightness"];
        UIView *imageScope=sliderModule ? MGFindSliderView(root) : root;
        if (!imageScope) imageScope=root;
'''
new = '''        UIView *imageScope = [slot isEqualToString:@"volume"] ? MGFindSliderView(root) : root;
        if (!imageScope) imageScope=root;
'''
if old not in t:
    raise SystemExit('image scope anchor missing')
t = t.replace(old, new, 1)

# 6) Brightness layer suppression must also start at the module root.
old = '''                imageFirstSuppressed += MGApplyBrightnessLayerMode(imageScope.layer, imageScope.layer, imageView.layer, classes);
                strategy = @"brightness-volume-pattern-fill-aware";
'''
new = '''                imageFirstSuppressed += MGApplyBrightnessLayerMode(root.layer, root.layer, imageView.layer, classes);
                strategy = @"brightness-volume-pattern-root-fill-aware";
'''
if old not in t:
    raise SystemExit('brightness layer scope anchor missing')
t = t.replace(old, new, 1)

# Version / diagnostics.
t = t.replace('ModuleGlassRuntime 1.0.13 Volume Pattern All Modules loaded', 'ModuleGlassRuntime 1.0.14 Rounded Volume Pattern loaded')
t = t.replace('All-module image-first runtime with live native Volume icon and percentage color', 'Rounded Volume-pattern runtime with live native Volume icon and percentage color')
p.write_text(t)

c = Path('source/ModuleGlass/control')
ct = c.read_text()
ct = re.sub(r'^Version: .*$', 'Version: 1.0.14', ct, flags=re.M)
ct = re.sub(r'^Description: .*$', 'Description: Rounded Volume-pattern Module Glass runtime: standard modules use Apple matching masks or safe iOS 16 compact radii, Brightness suppresses fill from the full module hierarchy, and the validated Volume renderer remains unchanged.', ct, flags=re.M)
c.write_text(ct)

print('patched Module Glass 1.0.18 / runtime 1.0.14 rounded Volume pattern')
