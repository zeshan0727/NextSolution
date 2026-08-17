from pathlib import Path
p=Path('source/ModuleGlass/Tweak.m')
s=p.read_text()

# 1) Add restore keys for connectivity background cleanup.
needle='static char MGVolumeFillImageKey;\n'
if needle not in s: raise SystemExit('1.1.7 keys marker missing')
s=s.replace(needle, needle + 'static char MGConnectivityOriginalBackgroundColorKey;\nstatic char MGConnectivityOriginalLayerBackgroundColorKey;\n', 1)

# 2) Replace the Volume reveal mask with a nested rounded-rect mask.
start=s.index('static CGFloat MGApplyVolumeFillMask(UIImageView *imageView, UIView *slider) {')
end=s.index('\nstatic void MGSliderSetValue', start)
new_volume=r'''static CGFloat MGApplyVolumeFillMask(UIImageView *imageView, UIView *slider) {
    if (!imageView || !slider) return NAN;
    CGFloat value=MGSliderNormalizedValue(slider);
    if (!isfinite(value)) { MGClearVolumeFillMask(imageView); return NAN; }
    CGFloat h=CGRectGetHeight(imageView.bounds), w=CGRectGetWidth(imageView.bounds);
    if (w<=1.0 || h<=1.0) return value;

    // Keep the same outer pill geometry as Brightness, then intersect it with
    // the live bottom-up reveal amount. This avoids the square/rectangular
    // Volume result caused by replacing the pill mask with a plain CALayer.
    CGFloat radius=MIN(w,h)*0.5;
    imageView.layer.cornerRadius=radius;
    if (@available(iOS 13.0, *)) imageView.layer.cornerCurve=kCACornerCurveContinuous;
    imageView.layer.masksToBounds=YES;

    CGFloat revealH=h*value;
    CAShapeLayer *pillMask=[CAShapeLayer layer];
    pillMask.frame=imageView.bounds;
    pillMask.path=[UIBezierPath bezierPathWithRoundedRect:imageView.bounds cornerRadius:radius].CGPath;
    pillMask.fillColor=UIColor.blackColor.CGColor;

    CALayer *revealMask=[CALayer layer];
    revealMask.frame=CGRectMake(0.0, h-revealH, w, revealH);
    revealMask.backgroundColor=UIColor.blackColor.CGColor;
    pillMask.mask=revealMask;

    imageView.layer.mask=pillMask;
    objc_setAssociatedObject(imageView, &MGVolumeFillMaskKey, pillMask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slider, &MGVolumeFillImageKey, imageView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return value;
}
'''
s=s[:start]+new_volume+s[end:]

# 3) Add narrowly-scoped connectivity active-background cleanup.
marker='\n#pragma mark - Apply\n'
if marker not in s: raise SystemExit('apply marker missing')
helpers=r'''

#pragma mark - Connectivity glyph-only active state

static BOOL MGConnectivityColorLooksBlue(UIColor *color, UITraitCollection *traits) {
    if (!color) return NO;
    if (@available(iOS 13.0, *)) color=[color resolvedColorWithTraitCollection:traits ?: UIScreen.mainScreen.traitCollection];
    CGFloat r=0,g=0,b=0,a=0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return NO;
    return a > 0.10 && b > 0.55 && b > r + 0.22 && b >= g;
}

static BOOL MGConnectivityToggleGeometry(UIView *view, UIView *root) {
    if (!view || !root || view==root) return NO;
    CGRect rect=[view convertRect:view.bounds toView:root];
    CGFloat w=CGRectGetWidth(rect), h=CGRectGetHeight(rect);
    if (w < 28.0 || h < 28.0 || w > 92.0 || h > 92.0) return NO;
    CGFloat aspect=w/MAX(1.0,h);
    if (aspect < 0.72 || aspect > 1.38) return NO;
    CGFloat rootArea=MAX(1.0, CGRectGetWidth(root.bounds)*CGRectGetHeight(root.bounds));
    CGFloat area=(w*h)/rootArea;
    return area > 0.01 && area < 0.28;
}

static NSUInteger MGClearConnectivityActiveBackgroundsRecursive(UIView *node, UIView *root, UIImageView *customImage,
                                                                  NSMutableArray<NSString *> *classes, NSInteger depth) {
    if (!node || !root || depth > 24) return 0;
    NSUInteger count=0;
    for (UIView *child in node.subviews.copy) {
        if (child==customImage || child.tag==MGImageTag) continue;
        if (MGConnectivityToggleGeometry(child, root)) {
            UIColor *viewColor=child.backgroundColor;
            UIColor *layerColor=child.layer.backgroundColor ? [UIColor colorWithCGColor:child.layer.backgroundColor] : nil;
            BOOL blueView=MGConnectivityColorLooksBlue(viewColor, root.traitCollection);
            BOOL blueLayer=MGConnectivityColorLooksBlue(layerColor, root.traitCollection);
            if (blueView || blueLayer) {
                if (blueView && !objc_getAssociatedObject(child, &MGConnectivityOriginalBackgroundColorKey)) {
                    objc_setAssociatedObject(child, &MGConnectivityOriginalBackgroundColorKey, viewColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    child.backgroundColor=UIColor.clearColor;
                }
                if (blueLayer && !objc_getAssociatedObject(child, &MGConnectivityOriginalLayerBackgroundColorKey)) {
                    objc_setAssociatedObject(child, &MGConnectivityOriginalLayerBackgroundColorKey, layerColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    child.layer.backgroundColor=UIColor.clearColor.CGColor;
                }
                if (classes) [classes addObject:NSStringFromClass(child.class) ?: @"UIView"];
                count++;
            }
        }
        count += MGClearConnectivityActiveBackgroundsRecursive(child, root, customImage, classes, depth+1);
    }
    return count;
}

static void MGRestoreConnectivityActiveBackgrounds(UIView *root) {
    if (!root) return;
    UIColor *savedView=objc_getAssociatedObject(root, &MGConnectivityOriginalBackgroundColorKey);
    if (savedView) {
        root.backgroundColor=savedView;
        objc_setAssociatedObject(root, &MGConnectivityOriginalBackgroundColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIColor *savedLayer=objc_getAssociatedObject(root, &MGConnectivityOriginalLayerBackgroundColorKey);
    if (savedLayer) {
        root.layer.backgroundColor=savedLayer.CGColor;
        objc_setAssociatedObject(root, &MGConnectivityOriginalLayerBackgroundColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *child in root.subviews.copy) MGRestoreConnectivityActiveBackgrounds(child);
}
'''
s=s.replace(marker,helpers+marker,1)

# Restore any prior connectivity state on every apply before deciding current state.
old='    MGRestoreModuleBlurVisuals(root);\n    BOOL expanded = MGIsExpanded(root);'
new='    MGRestoreModuleBlurVisuals(root);\n    MGRestoreConnectivityActiveBackgrounds(root);\n    BOOL expanded = MGIsExpanded(root);'
if old not in s: raise SystemExit('restore insertion marker missing')
s=s.replace(old,new,1)

# Add glyph-only connectivity cleanup after normal image rendering, without altering other slots.
old='''        if (removeBlur) {\n            NSMutableArray<NSString *> *classes=[NSMutableArray array];\n            blurSuppressed = MGSetModuleBlurHiddenRecursive(root, root, imageView, YES, classes, 0);\n            blurSuppressedClasses = classes.copy;\n            strategy = [strategy stringByAppendingString:@"-crisp"];\n        }\n    }\n\n    // Blur removal only touches module-sized non-interactive material surfaces.\n'''
new='''        if (removeBlur) {\n            NSMutableArray<NSString *> *classes=[NSMutableArray array];\n            blurSuppressed = MGSetModuleBlurHiddenRecursive(root, root, imageView, YES, classes, 0);\n            blurSuppressedClasses = classes.copy;\n            strategy = [strategy stringByAppendingString:@"-crisp"];\n        }\n        if ([slot isEqualToString:@"connectivity"]) {\n            NSMutableArray<NSString *> *connectivityClasses=[NSMutableArray array];\n            NSUInteger connectivityCleared = MGClearConnectivityActiveBackgroundsRecursive(root, root, imageView, connectivityClasses, 0);\n            if (connectivityCleared > 0) strategy = [strategy stringByAppendingString:@"-connectivity-glyph-only"];\n        }\n    }\n\n    // Blur removal only touches module-sized non-interactive material surfaces.\n'''
if old not in s: raise SystemExit('connectivity apply marker missing')
s=s.replace(old,new,1)

s=s.replace('ModuleGlassRuntime 1.1.7 Crisp Blur + Volume Fill Renderer loaded','ModuleGlassRuntime 1.1.8 Rounded Volume + Connectivity Glyph Renderer loaded')

for token in ['pillMask.mask=revealMask','MGClearConnectivityActiveBackgroundsRecursive','MGRestoreConnectivityActiveBackgrounds','1.1.8 Rounded Volume + Connectivity Glyph Renderer']:
    assert token in s
p.write_text(s)
print('patched Module Glass renderer for 1.1.8')
