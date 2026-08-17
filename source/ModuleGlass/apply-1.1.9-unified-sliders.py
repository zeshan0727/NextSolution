from pathlib import Path
p=Path('source/ModuleGlass/Tweak.m')
s=p.read_text()

def rep(old,new,name):
    global s
    c=s.count(old)
    if c!=1:
        raise SystemExit(f'{name}: expected 1 got {c}')
    s=s.replace(old,new,1)

rep('static NSInteger const MGVolumePercentageOverlayTag = 0x4D475650;\n',
    'static NSInteger const MGVolumePercentageOverlayTag = 0x4D475650;\nstatic NSInteger const MGSliderShellTag = 0x4D475353;\n', 'shell tag')

anchor='''static UIImageView *MGImageViewInParent(UIView *parent) {\n    for (UIView *view in parent.subviews) if (view.tag == MGImageTag && [view isKindOfClass:UIImageView.class]) return (UIImageView *)view;\n    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectZero];\n    imageView.tag = MGImageTag;\n    imageView.userInteractionEnabled = NO;\n    imageView.contentMode = UIViewContentModeScaleToFill;\n    imageView.clipsToBounds = YES;\n    imageView.layer.masksToBounds = YES;\n    return imageView;\n}\n'''
add=anchor+r'''

static UIView *MGSliderShellInScope(UIView *scope) {
    if (!scope) return nil;
    UIView *shell=nil;
    for (UIView *view in scope.subviews) {
        if (view.tag == MGSliderShellTag) { shell=view; break; }
    }
    if (!shell) {
        shell=[[UIView alloc] initWithFrame:scope.bounds];
        shell.tag=MGSliderShellTag;
        shell.userInteractionEnabled=NO;
        shell.backgroundColor=[UIColor colorWithWhite:0.0 alpha:0.26];
        shell.layer.name=@"ModuleGlassSliderShell";
        [scope insertSubview:shell atIndex:0];
    }
    shell.frame=scope.bounds;
    CGFloat w=CGRectGetWidth(shell.bounds), h=CGRectGetHeight(shell.bounds);
    shell.layer.cornerRadius=MIN(w,h)*0.5;
    if (@available(iOS 13.0, *)) shell.layer.cornerCurve=kCACornerCurveContinuous;
    shell.layer.masksToBounds=YES;
    shell.hidden=NO;
    return shell;
}

static void MGRemoveSliderShells(UIView *root) {
    if (!root) return;
    for (UIView *view in root.subviews.copy) {
        if (view.tag == MGSliderShellTag) {
            [view removeFromSuperview];
            continue;
        }
        MGRemoveSliderShells(view);
    }
}
'''
rep(anchor,add,'slider shell helpers')

old='''    // Brightness and Volume are both continuous sliders and intentionally use\n    // the exact same placement and shape path.\n    BOOL sliderSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];\n    if (sliderSlot) {\n        UIView *scope = MGFindSliderView(root) ?: root;\n        UIView *native = MGFindNativeBackground(scope);\n        if (native.superview) {\n            UIView *matchingShape = MGFindMatchingAppleShape(native, root);\n            if (outParent) *outParent = native.superview;\n            if (outAnchor) *outAnchor = native;\n            if (outFrame) *outFrame = native.frame;\n            if (outCornerSource) *outCornerSource = matchingShape ?: native;\n            if (outStrategy) *outStrategy = [NSString stringWithFormat:@"%@-slider-native-sibling", slot];\n            return YES;\n        }\n        if (outParent) *outParent = scope;\n        if (outAnchor) *outAnchor = nil;\n        if (outFrame) *outFrame = scope.bounds;\n        if (outCornerSource) *outCornerSource = scope;\n        if (outStrategy) *outStrategy = [NSString stringWithFormat:@"%@-slider-index0", slot];\n        return YES;\n    }\n'''
new='''    // Slider images must never use Apple's value-dependent fill/background frame.\n    // Brightness and Volume now use the full continuous-slider bounds permanently;\n    // only our inner image mask changes with the live value.\n    BOOL sliderSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];\n    if (sliderSlot) {\n        UIView *scope = MGFindSliderView(root) ?: root;\n        UIView *shell = MGSliderShellInScope(scope);\n        if (outParent) *outParent = scope;\n        if (outAnchor) *outAnchor = shell;\n        if (outFrame) *outFrame = scope.bounds;\n        if (outCornerSource) *outCornerSource = scope;\n        if (outStrategy) *outStrategy = [NSString stringWithFormat:@"%@-full-slider-shell", slot];\n        return YES;\n    }\n'''
rep(old,new,'slider full host')

rep('''static BOOL MGBrightnessObscuringVisual(UIView *view, UIView *slider, UIImageView *imageView) {\n    if (!view || !slider || view == imageView || view.tag == MGImageTag) return NO;''',
    '''static BOOL MGBrightnessObscuringVisual(UIView *view, UIView *slider, UIImageView *imageView) {\n    if (!view || !slider || view == imageView || view.tag == MGImageTag || view.tag == MGSliderShellTag) return NO;''', 'preserve shell view')

rep('''static BOOL MGBrightnessObscuringLayer(CALayer *layer, CALayer *sliderLayer, CALayer *imageLayer) {\n    if (!layer || !sliderLayer || layer == imageLayer || MGLayerContainsLayer(layer, imageLayer)) return NO;''',
    '''static BOOL MGBrightnessObscuringLayer(CALayer *layer, CALayer *sliderLayer, CALayer *imageLayer) {\n    if (!layer || !sliderLayer || layer == imageLayer || MGLayerContainsLayer(layer, imageLayer)) return NO;\n    if ([layer.name isEqualToString:@"ModuleGlassSliderShell"]) return NO;''', 'preserve shell layer')

start=s.index('static void MGClearVolumeFillMask(UIImageView *imageView) {')
end=s.index('\nstatic void MGSliderSetValue', start)
newmask=r'''static void MGClearSliderFillMask(UIImageView *imageView) {
    if (!imageView) return;
    CALayer *mask=objc_getAssociatedObject(imageView, &MGVolumeFillMaskKey);
    if (mask && imageView.layer.mask == mask) imageView.layer.mask=nil;
    objc_setAssociatedObject(imageView, &MGVolumeFillMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static CGFloat MGApplySliderFillMask(UIImageView *imageView, UIView *slider) {
    if (!imageView || !slider) return NAN;
    CGFloat value=MGSliderNormalizedValue(slider);
    if (!isfinite(value)) { MGClearSliderFillMask(imageView); return NAN; }
    CGFloat h=CGRectGetHeight(imageView.bounds), w=CGRectGetWidth(imageView.bounds);
    if (w<=1.0 || h<=1.0) return value;

    CGFloat revealH=h*value;
    CGRect fillRect=CGRectMake(0.0, h-revealH, w, revealH);
    CGFloat fillRadius=MIN(w, revealH)*0.5;
    CAShapeLayer *mask=[CAShapeLayer layer];
    mask.frame=imageView.bounds;
    if (revealH <= 0.5) {
        mask.path=[UIBezierPath bezierPath].CGPath;
    } else {
        mask.path=[UIBezierPath bezierPathWithRoundedRect:fillRect cornerRadius:fillRadius].CGPath;
    }
    mask.fillColor=UIColor.blackColor.CGColor;
    imageView.layer.mask=mask;
    objc_setAssociatedObject(imageView, &MGVolumeFillMaskKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slider, &MGVolumeFillImageKey, imageView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return value;
}
'''
s=s[:start]+newmask+s[end:]
s=s.replace('MGApplyVolumeFillMask(imageView, (UIView *)self);','MGApplySliderFillMask(imageView, (UIView *)self);')
s=s.replace('MGClearVolumeFillMask(imageView);','MGClearSliderFillMask(imageView);')
s=s.replace('MGApplyVolumeFillMask(imageView, imageScope)','MGApplySliderFillMask(imageView, imageScope)')

rep('''    if (expanded) {\n        if ([slot isEqualToString:@"volume"]) {\n            UIView *slider = MGFindSliderView(root);\n            if (slider) objc_setAssociatedObject(slider, &MGVolumeFillImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);\n        }\n        MGRemoveTaggedImages(root, nil);''',
    '''    if (expanded) {\n        BOOL sliderSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];\n        if (sliderSlot) {\n            UIView *slider = MGFindSliderView(root);\n            if (slider) objc_setAssociatedObject(slider, &MGVolumeFillImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);\n            MGRemoveSliderShells(root);\n        }\n        MGRemoveTaggedImages(root, nil);''','expanded slider cleanup')

rep('''    if (!enabled || !exists) {\n        if ([slot isEqualToString:@"volume"]) {\n            UIView *slider = MGFindSliderView(root);\n            if (slider) objc_setAssociatedObject(slider, &MGVolumeFillImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);\n        }\n        MGRemoveTaggedImages(root, nil);''',
    '''    if (!enabled || !exists) {\n        BOOL sliderSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];\n        if (sliderSlot) {\n            UIView *slider = MGFindSliderView(root);\n            if (slider) objc_setAssociatedObject(slider, &MGVolumeFillImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);\n            MGRemoveSliderShells(root);\n        }\n        MGRemoveTaggedImages(root, nil);''','inactive slider cleanup')

rep('''    MGCopyCornerGeometry(imageView, cornerSource, root);\n    MGApplyModuleShapeFallback(imageView, slot);\n    if (![slot isEqualToString:@"volume"]) MGClearSliderFillMask(imageView);''',
    '''    MGCopyCornerGeometry(imageView, cornerSource, root);\n    MGApplyModuleShapeFallback(imageView, slot);\n    BOOL sliderImageSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];\n    if (!sliderImageSlot) MGClearSliderFillMask(imageView);''','non-slider mask clear')

rep('''            imageFirstSuppressed = MGApplyBrightnessImageMode(imageScope, imageView, classes);\n            imageFirstSuppressed += MGApplyBrightnessLayerMode(imageScope.layer, imageScope.layer, imageView.layer, classes);\n            if ([slot isEqualToString:@"volume"]) volumeFillValue = MGApplySliderFillMask(imageView, imageScope);\n            strategy = [NSString stringWithFormat:@"%@-brightness-pattern-fill-aware", slot];''',
    '''            imageFirstSuppressed = MGApplyBrightnessImageMode(imageScope, imageView, classes);\n            imageFirstSuppressed += MGApplyBrightnessLayerMode(imageScope.layer, imageScope.layer, imageView.layer, classes);\n            volumeFillValue = MGApplySliderFillMask(imageView, imageScope);\n            strategy = [NSString stringWithFormat:@"%@-unified-full-pill-live-fill", slot];''','shared fill apply')

s=s.replace('ModuleGlassRuntime 1.1.8 Rounded Volume + Connectivity Glyph Renderer loaded','ModuleGlassRuntime 1.1.9 Unified Slider Shell Renderer loaded')

for token in ['MGSliderShellTag','MGSliderShellInScope','MGApplySliderFillMask','unified-full-pill-live-fill','1.1.9 Unified Slider Shell Renderer']:
    assert token in s, token
assert 'MGApplyVolumeFillMask' not in s
assert 'slider-native-sibling' not in s

p.write_text(s)
print('patched Module Glass renderer for 1.1.9 unified sliders')
