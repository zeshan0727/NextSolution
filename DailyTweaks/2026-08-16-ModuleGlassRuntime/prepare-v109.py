from pathlib import Path

p = Path(__file__).with_name('ModuleGlass.xm')
s = p.read_text()

# This script runs after prepare-v108.py. It makes Module Glass a purely visual
# compact-background overlay. We never hide or mutate Apple's material hierarchy.

s = s.replace('return rootArea >= (screenArea * 0.55);', 'return rootArea >= (screenArea * 0.30);')

old_copy = '''static void MGCopyNativeShapeToImageView(UIImageView *background, UIView *reference, UIView *root) {
    if (!background || !root) return;

    CGRect nativeFrame = reference ? [reference convertRect:reference.bounds toView:root] : root.bounds;
    if (CGRectIsEmpty(nativeFrame) || !isfinite(nativeFrame.origin.x) || !isfinite(nativeFrame.origin.y) ||
        !isfinite(nativeFrame.size.width) || !isfinite(nativeFrame.size.height)) {
        nativeFrame = root.bounds;
    }
    background.frame = nativeFrame;
    background.transform = CGAffineTransformIdentity;
    background.clipsToBounds = YES;
    background.layer.masksToBounds = YES;
    background.layer.mask = nil;

    UIView *shapeSource = reference ?: root;
    background.layer.cornerRadius = MGNativeCornerRadius(shapeSource, root);
    background.layer.maskedCorners = shapeSource.layer.maskedCorners;
    if (@available(iOS 13.0, *)) background.layer.cornerCurve = shapeSource.layer.cornerCurve;

    CALayer *sourceMask = shapeSource.layer.mask;
    if ([sourceMask isKindOfClass:CAShapeLayer.class]) {
        CAShapeLayer *sourceShape = (CAShapeLayer *)sourceMask;
        CAShapeLayer *copy = [CAShapeLayer layer];
        copy.frame = background.bounds;
        copy.path = sourceShape.path;
        copy.fillRule = sourceShape.fillRule;
        background.layer.mask = copy;
    }
}
'''

new_copy = '''static void MGCopyNativeShapeToImageView(UIImageView *background, UIView *reference, UIView *root) {
    if (!background || !root) return;

    UIView *parent = background.superview;
    UIView *shapeSource = reference ?: root;
    CGRect nativeFrame = parent ? [shapeSource convertRect:shapeSource.bounds toView:parent] : shapeSource.bounds;
    if (CGRectIsEmpty(nativeFrame) || !isfinite(nativeFrame.origin.x) || !isfinite(nativeFrame.origin.y) ||
        !isfinite(nativeFrame.size.width) || !isfinite(nativeFrame.size.height)) {
        nativeFrame = parent ? [root convertRect:root.bounds toView:parent] : root.bounds;
    }

    // Geometry is copied from Apple's existing surface. We never write to the
    // module/root frame, constraints, transform, corner radius or masks.
    background.frame = nativeFrame;
    background.transform = CGAffineTransformIdentity;
    background.clipsToBounds = YES;
    background.layer.masksToBounds = YES;
    background.layer.mask = nil;
    background.layer.cornerRadius = MGNativeCornerRadius(shapeSource, root);
    background.layer.maskedCorners = shapeSource.layer.maskedCorners;
    if (@available(iOS 13.0, *)) background.layer.cornerCurve = shapeSource.layer.cornerCurve;

    CALayer *sourceMask = shapeSource.layer.mask;
    if ([sourceMask isKindOfClass:CAShapeLayer.class]) {
        CAShapeLayer *sourceShape = (CAShapeLayer *)sourceMask;
        CAShapeLayer *copy = [CAShapeLayer layer];
        copy.frame = background.bounds;
        copy.path = sourceShape.path;
        copy.fillRule = sourceShape.fillRule;
        background.layer.mask = copy;
    }
}
'''
if old_copy not in s:
    raise SystemExit('v108 native-shape helper not found')
s = s.replace(old_copy, new_copy, 1)

old_restore = '''static void MGRestoreCompactBackgroundChanges(UIView *root) {
    if (!root) return;
    UIView *background = [root viewWithTag:MGImageTag];
    [background removeFromSuperview];
    MGSetMaterialHiddenRecursively(root, NO);
}
'''
new_restore = '''static void MGRestoreCompactBackgroundChanges(UIView *root) {
    if (!root) return;
    UIView *background = [root viewWithTag:MGImageTag];
    [background removeFromSuperview];
    // Repair any material state left by older Module Glass runtimes, but this
    // runtime never hides Apple's native material itself.
    MGSetMaterialHiddenRecursively(root, NO);
}
'''
if old_restore not in s:
    raise SystemExit('restore helper not found')
s = s.replace(old_restore, new_restore, 1)

old_apply = '''    BOOL shouldShow = enabled && image != nil;
    UIView *nativeBackground = MGNativeBackgroundReference(root);
    if (shouldShow) {
        if (!background || ![background isKindOfClass:UIImageView.class]) {
            background = [[UIImageView alloc] initWithFrame:CGRectZero];
            background.tag = MGImageTag;
            background.userInteractionEnabled = NO;
            background.contentMode = UIViewContentModeScaleAspectFill;
            background.clipsToBounds = YES;
            background.autoresizingMask = UIViewAutoresizingNone;

            UIView *anchor = MGRootChildContainingView(nativeBackground, root);
            if (anchor) [root insertSubview:background aboveSubview:anchor];
            else [root insertSubview:background atIndex:0];
        }

        // The image is visual content only. Its geometry comes from Apple's native
        // module background; it never changes the module/root frame or layout.
        MGCopyNativeShapeToImageView(background, nativeBackground, root);
        background.image = image;
        background.alpha = MIN(1.0, MAX(0.0, opacity));
        background.hidden = NO;
        MGSetMaterialHiddenRecursively(root, removeBlur);
    } else {
        MGRestoreCompactBackgroundChanges(root);
    }
'''

new_apply = '''    BOOL shouldShow = enabled && image != nil;
    UIView *nativeBackground = MGNativeBackgroundReference(root);
    if (shouldShow && nativeBackground && nativeBackground.superview) {
        UIView *host = nativeBackground.superview;
        if (!background || ![background isKindOfClass:UIImageView.class] || background.superview != host) {
            [background removeFromSuperview];
            background = [[UIImageView alloc] initWithFrame:CGRectZero];
            background.tag = MGImageTag;
            background.userInteractionEnabled = NO;
            background.contentMode = UIViewContentModeScaleAspectFill;
            background.clipsToBounds = YES;
            background.autoresizingMask = UIViewAutoresizingNone;

            // Passive sibling overlay: immediately above Apple's native background
            // and below the module's controls. No root-view mutation is performed.
            [host insertSubview:background aboveSubview:nativeBackground];
        }

        MGCopyNativeShapeToImageView(background, nativeBackground, root);
        background.image = image;
        background.alpha = MIN(1.0, MAX(0.0, opacity));
        background.hidden = NO;

        // Never hide or modify Apple's material. Opaque photos visually replace it;
        // lower opacity intentionally lets the stock material show through.
        MGSetMaterialHiddenRecursively(root, NO);
    } else {
        MGRestoreCompactBackgroundChanges(root);
    }
'''
if old_apply not in s:
    raise SystemExit('v108 apply block not found')
s = s.replace(old_apply, new_apply, 1)

# Keep reading the legacy preference for compatibility, but make it explicit in
# diagnostics that it no longer causes native material mutation.
s = s.replace('removeBlur=%d opacity=%.2f expanded=%d root=%@ frame=%@ nativeBackground=%@',
              'removeBlurPref=%d materialMutation=0 opacity=%.2f expanded=%d root=%@ frame=%@ nativeBackground=%@')

s = s.replace('ModuleGlassRuntime 1.0.4 loaded', 'ModuleGlassRuntime 1.0.5 loaded', 1)

p.write_text(s)
print('Prepared Module Glass runtime 1.0.5 / Module Glass 1.0.9 passive native-surface overlay.')
