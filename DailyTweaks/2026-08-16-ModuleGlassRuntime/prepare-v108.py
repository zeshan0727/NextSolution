from pathlib import Path

p = Path(__file__).with_name('ModuleGlass.xm')
s = p.read_text()

old_helpers = '''static BOOL MGIsBackgroundMaterialView(UIView *view) {
    if (!view || view.tag == MGImageTag) return NO;
    NSString *name = NSStringFromClass(view.class);
    // Only touch module-specific material classes. Hiding every UIVisualEffectView
    // can break expanded-module presentation/dismissal and system interactions.
    NSArray<NSString *> *needles = @[@"MTMaterialView", @"CCUIModuleBackground", @"ContentModuleBackground"];
    for (NSString *needle in needles) if ([name containsString:needle]) return YES;
    return NO;
}
'''

new_helpers = '''static BOOL MGIsBackgroundMaterialView(UIView *view) {
    if (!view || view.tag == MGImageTag) return NO;
    NSString *name = NSStringFromClass(view.class);
    // Only touch module-specific material classes. Hiding every UIVisualEffectView
    // can break expanded-module presentation/dismissal and system interactions.
    NSArray<NSString *> *needles = @[@"MTMaterialView", @"CCUIModuleBackground", @"ContentModuleBackground"];
    for (NSString *needle in needles) if ([name containsString:needle]) return YES;
    return NO;
}

static void MGFindNativeBackgroundRecursive(UIView *view, UIView *root, UIView **best, CGFloat *bestArea) {
    if (!view || !root || !best || !bestArea) return;
    if (MGIsBackgroundMaterialView(view)) {
        CGRect frame = [view convertRect:view.bounds toView:root];
        CGFloat area = fabs(CGRectGetWidth(frame) * CGRectGetHeight(frame));
        if (area > *bestArea && CGRectGetWidth(frame) > 8.0 && CGRectGetHeight(frame) > 8.0) {
            *best = view;
            *bestArea = area;
        }
    }
    for (UIView *child in view.subviews) MGFindNativeBackgroundRecursive(child, root, best, bestArea);
}

static UIView *MGNativeBackgroundReference(UIView *root) {
    if (!root) return nil;
    UIView *best = nil;
    CGFloat bestArea = 0.0;
    MGFindNativeBackgroundRecursive(root, root, &best, &bestArea);
    return best;
}

static UIView *MGRootChildContainingView(UIView *view, UIView *root) {
    if (!view || !root || view == root) return nil;
    UIView *node = view;
    while (node.superview && node.superview != root) node = node.superview;
    return node.superview == root ? node : nil;
}

static CGFloat MGNativeCornerRadius(UIView *reference, UIView *root) {
    UIView *node = reference;
    while (node) {
        if (node.layer.cornerRadius > 0.5) return node.layer.cornerRadius;
        if (node == root) break;
        node = node.superview;
    }
    return root.layer.cornerRadius;
}

static void MGCopyNativeShapeToImageView(UIImageView *background, UIView *reference, UIView *root) {
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

if old_helpers not in s:
    raise SystemExit('Expected background helper block not found')
s = s.replace(old_helpers, new_helpers, 1)

old_apply = '''    BOOL shouldShow = enabled && image != nil;
    if (shouldShow) {
        if (!background || ![background isKindOfClass:UIImageView.class]) {
            background = [[UIImageView alloc] initWithFrame:root.bounds];
            background.tag = MGImageTag;
            background.userInteractionEnabled = NO;
            background.contentMode = UIViewContentModeScaleAspectFill;
            background.clipsToBounds = YES;
            background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [root insertSubview:background atIndex:0];
        }
        background.frame = root.bounds;
        background.layer.cornerRadius = root.layer.cornerRadius;
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

if old_apply not in s:
    raise SystemExit('Expected image application block not found')
s = s.replace(old_apply, new_apply, 1)

old_log = '''        MGLog(NO, @"apply source=%@ controller=%@ candidates=%@ slot=%@ path=%@ exists=%d enabled=%d imageLoaded=%d removeBlur=%d opacity=%.2f expanded=%d root=%@ frame=%@ subviews=%lu imageView=%@",
              source, NSStringFromClass([controller class]), candidates, slot, path, fileExists, enabled,
              image != nil, removeBlur, opacity, expanded, NSStringFromClass(root.class), NSStringFromCGRect(root.frame),
              (unsigned long)root.subviews.count, shouldShow ? @"visible" : @"absent");
'''

new_log = '''        MGLog(NO, @"apply source=%@ controller=%@ candidates=%@ slot=%@ path=%@ exists=%d enabled=%d imageLoaded=%d removeBlur=%d opacity=%.2f expanded=%d root=%@ frame=%@ nativeBackground=%@ nativeFrame=%@ nativeRadius=%.2f imageFrame=%@ subviews=%lu imageView=%@",
              source, NSStringFromClass([controller class]), candidates, slot, path, fileExists, enabled,
              image != nil, removeBlur, opacity, expanded, NSStringFromClass(root.class), NSStringFromCGRect(root.frame),
              nativeBackground ? NSStringFromClass(nativeBackground.class) : @"<none>",
              nativeBackground ? NSStringFromCGRect([nativeBackground convertRect:nativeBackground.bounds toView:root]) : @"<none>",
              nativeBackground ? MGNativeCornerRadius(nativeBackground, root) : root.layer.cornerRadius,
              background ? NSStringFromCGRect(background.frame) : @"<none>",
              (unsigned long)root.subviews.count, shouldShow ? @"visible" : @"absent");
'''

if old_log not in s:
    raise SystemExit('Expected diagnostic log block not found')
s = s.replace(old_log, new_log, 1)

s = s.replace('ModuleGlassRuntime 1.0.3 loaded', 'ModuleGlassRuntime 1.0.4 loaded', 1)

p.write_text(s)
print('Prepared Module Glass runtime 1.0.4 / Module Glass 1.0.8 native-shape rendering.')
