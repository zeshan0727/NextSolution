from pathlib import Path
p=Path('source/ModuleGlass/Tweak.m')
s=p.read_text()

def rep(old,new,name):
    global s
    c=s.count(old)
    if c!=1: raise SystemExit(f'{name}: expected 1 got {c}')
    s=s.replace(old,new,1)

rep('static char MGBrightnessOriginalLayerOpacityKey;\n','static char MGBrightnessOriginalLayerOpacityKey;\nstatic char MGBlurOriginalAlphaKey;\nstatic char MGVolumeFillMaskKey;\nstatic char MGVolumeFillImageKey;\n','keys')
rep('static void (*MGOrigContentLayout)(id, SEL);\n','static void (*MGOrigContentLayout)(id, SEL);\nstatic void (*MGOrigSliderSetValue)(id, SEL, CGFloat);\n','slider hook pointer')

marker='\n#pragma mark - Apply\n'
if s.count(marker)!=1: raise SystemExit('apply marker mismatch')
helpers=r'''

#pragma mark - Glyph-safe blur removal / slider reveal

static BOOL MGSubtreeContainsForegroundControl(UIView *view, UIImageView *customImage) {
    if (!view) return NO;
    if (view == customImage || view.tag == MGImageTag) return NO;
    if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UILabel.class] ||
        [view isKindOfClass:UIImageView.class] || [view isKindOfClass:UIButton.class]) return YES;
    for (UIView *child in view.subviews) if (MGSubtreeContainsForegroundControl(child, customImage)) return YES;
    return NO;
}

static BOOL MGIsModuleSizedBlurVisual(UIView *view, UIView *root, UIImageView *customImage) {
    if (!view || !root || view == root || view == customImage || view.tag == MGImageTag || view.hidden) return NO;
    if ([customImage isDescendantOfView:view]) return NO;
    if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UILabel.class] ||
        [view isKindOfClass:UIImageView.class] || [view isKindOfClass:UIButton.class]) return NO;
    NSString *name = NSStringFromClass(view.class).lowercaseString ?: @"";
    BOOL visualClass = [name containsString:@"material"] || [name containsString:@"visualeffect"] ||
                       [name containsString:@"backdrop"] || [name containsString:@"blur"] ||
                       [name containsString:@"background"];
    if (!visualClass) return NO;
    CGRect rect = [view convertRect:view.bounds toView:root];
    CGFloat rootW = CGRectGetWidth(root.bounds), rootH = CGRectGetHeight(root.bounds);
    CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
    if (rootW <= 1.0 || rootH <= 1.0 || w <= 1.0 || h <= 1.0) return NO;
    CGFloat areaRatio = (w * h) / MAX(1.0, rootW * rootH);
    CGFloat widthRatio = w / rootW, heightRatio = h / rootH;
    CGFloat centerDistance = hypot(CGRectGetMidX(rect) - CGRectGetMidX(root.bounds), CGRectGetMidY(rect) - CGRectGetMidY(root.bounds));
    if (areaRatio < 0.70 || areaRatio > 1.40 || widthRatio < 0.72 || heightRatio < 0.72) return NO;
    if (centerDistance > MAX(rootW, rootH) * 0.20) return NO;
    return !MGSubtreeContainsForegroundControl(view, customImage);
}

static NSUInteger MGSetModuleBlurHiddenRecursive(UIView *node, UIView *root, UIImageView *customImage,
                                                   BOOL hidden, NSMutableArray<NSString *> *classes, NSInteger depth) {
    if (!node || !root || depth > 24) return 0;
    NSUInteger count = 0;
    for (UIView *child in node.subviews.copy) {
        if (child == customImage || child.tag == MGImageTag) continue;
        if (MGIsModuleSizedBlurVisual(child, root, customImage)) {
            NSNumber *saved = objc_getAssociatedObject(child, &MGBlurOriginalAlphaKey);
            if (hidden) {
                if (!saved) objc_setAssociatedObject(child, &MGBlurOriginalAlphaKey, @(child.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                child.alpha = 0.0;
                if (classes) [classes addObject:NSStringFromClass(child.class) ?: @"UIView"];
            } else if (saved) {
                child.alpha = saved.doubleValue;
                objc_setAssociatedObject(child, &MGBlurOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            count++;
            continue;
        }
        count += MGSetModuleBlurHiddenRecursive(child, root, customImage, hidden, classes, depth + 1);
    }
    return count;
}

static void MGRestoreModuleBlurVisuals(UIView *root) {
    if (!root) return;
    NSNumber *saved = objc_getAssociatedObject(root, &MGBlurOriginalAlphaKey);
    if (saved) {
        root.alpha = saved.doubleValue;
        objc_setAssociatedObject(root, &MGBlurOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *child in root.subviews.copy) MGRestoreModuleBlurVisuals(child);
}

static CGFloat MGSliderNormalizedValue(UIView *slider) {
    if (!slider) return NAN;
    NSNumber *value = nil;
    for (NSString *key in @[@"value", @"_value", @"normalizedValue", @"_normalizedValue"]) {
        @try { id c=[slider valueForKey:key]; if ([c respondsToSelector:@selector(doubleValue)]) { value=c; break; } }
        @catch (__unused NSException *e) {}
    }
    if (!value) return NAN;
    CGFloat v=value.doubleValue, minV=0.0, maxV=1.0;
    @try { id c=[slider valueForKey:@"minimumValue"]; if ([c respondsToSelector:@selector(doubleValue)]) minV=[c doubleValue]; } @catch (__unused NSException *e) {}
    @try { id c=[slider valueForKey:@"maximumValue"]; if ([c respondsToSelector:@selector(doubleValue)]) maxV=[c doubleValue]; } @catch (__unused NSException *e) {}
    if (!isfinite(v)) return NAN;
    if (!isfinite(minV) || !isfinite(maxV) || fabs(maxV-minV)<0.0001) { minV=0.0; maxV=1.0; }
    return MIN(1.0, MAX(0.0, (v-minV)/(maxV-minV)));
}

static void MGClearVolumeFillMask(UIImageView *imageView) {
    if (!imageView) return;
    CALayer *mask=objc_getAssociatedObject(imageView, &MGVolumeFillMaskKey);
    if (mask && imageView.layer.mask == mask) imageView.layer.mask=nil;
    objc_setAssociatedObject(imageView, &MGVolumeFillMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static CGFloat MGApplyVolumeFillMask(UIImageView *imageView, UIView *slider) {
    if (!imageView || !slider) return NAN;
    CGFloat value=MGSliderNormalizedValue(slider);
    if (!isfinite(value)) { MGClearVolumeFillMask(imageView); return NAN; }
    CGFloat h=CGRectGetHeight(imageView.bounds), w=CGRectGetWidth(imageView.bounds);
    if (w<=1.0 || h<=1.0) return value;
    imageView.layer.cornerRadius=MIN(w,h)*0.5;
    if (@available(iOS 13.0, *)) imageView.layer.cornerCurve=kCACornerCurveContinuous;
    imageView.layer.masksToBounds=YES;
    CGFloat revealH=h*value;
    CALayer *mask=[CALayer layer];
    mask.frame=CGRectMake(0.0, h-revealH, w, revealH);
    mask.backgroundColor=UIColor.blackColor.CGColor;
    imageView.layer.mask=mask;
    objc_setAssociatedObject(imageView, &MGVolumeFillMaskKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slider, &MGVolumeFillImageKey, imageView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return value;
}

static void MGSliderSetValue(id self, SEL _cmd, CGFloat value) {
    if (MGOrigSliderSetValue) MGOrigSliderSetValue(self, _cmd, value);
    if (![self isKindOfClass:UIView.class]) return;
    UIImageView *imageView=objc_getAssociatedObject(self, &MGVolumeFillImageKey);
    if ([imageView isKindOfClass:UIImageView.class] && imageView.superview) MGApplyVolumeFillMask(imageView, (UIView *)self);
}
'''
s=s.replace(marker,helpers+marker,1)

rep('    MGRestoreBrightnessLayers(root.layer);\n    BOOL expanded = MGIsExpanded(root);','    MGRestoreBrightnessLayers(root.layer);\n    MGRestoreModuleBlurVisuals(root);\n    BOOL expanded = MGIsExpanded(root);','restore blur')
rep('''    if (expanded) {\n        MGRemoveTaggedImages(root, nil);''','''    if (expanded) {\n        if ([slot isEqualToString:@"volume"]) {\n            UIView *slider = MGFindSliderView(root);\n            if (slider) objc_setAssociatedObject(slider, &MGVolumeFillImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);\n        }\n        MGRemoveTaggedImages(root, nil);''','expanded clear')
rep('''    if (!enabled || !exists) {\n        MGRemoveTaggedImages(root, nil);''','''    if (!enabled || !exists) {\n        if ([slot isEqualToString:@"volume"]) {\n            UIView *slider = MGFindSliderView(root);\n            if (slider) objc_setAssociatedObject(slider, &MGVolumeFillImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);\n        }\n        MGRemoveTaggedImages(root, nil);''','inactive clear')
rep('''    MGCopyCornerGeometry(imageView, cornerSource, root);\n    MGApplyModuleShapeFallback(imageView, slot);\n\n    NSUInteger imageFirstSuppressed = 0;''','''    MGCopyCornerGeometry(imageView, cornerSource, root);\n    MGApplyModuleShapeFallback(imageView, slot);\n    if (![slot isEqualToString:@"volume"]) MGClearVolumeFillMask(imageView);\n\n    NSUInteger imageFirstSuppressed = 0;''','mask clear')

old='''    NSUInteger imageFirstSuppressed = 0;\n    NSArray<NSString *> *imageFirstSuppressedClasses = @[];\n    if (imageView.image) {\n        BOOL sliderSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];\n        if (sliderSlot) {\n            UIView *imageScope = MGFindSliderView(root) ?: root;\n            NSMutableArray<NSString *> *classes=[NSMutableArray array];\n\n            // Volume now follows the exact same fill-aware renderer as Brightness.\n            // Only slider background/fill visuals are suppressed. Glyphs, labels,\n            // UIImageViews and controls stay native and above the custom image.\n            imageFirstSuppressed = MGApplyBrightnessImageMode(imageScope, imageView, classes);\n            imageFirstSuppressed += MGApplyBrightnessLayerMode(imageScope.layer, imageScope.layer, imageView.layer, classes);\n            strategy = [NSString stringWithFormat:@"%@-brightness-pattern-fill-aware", slot];\n            imageFirstSuppressedClasses = classes.copy;\n        } else {\n            // Normal modules are background-only: never recursively hide their UI.\n            strategy = [NSString stringWithFormat:@"%@-glyph-safe-background-only", slot];\n        }\n    }\n\n    // Safety rule: these preferences are intentionally never implemented by mutating,\n    // hiding, removing or reparenting Apple's material/effect views.\n'''
new='''    NSUInteger imageFirstSuppressed = 0;\n    NSArray<NSString *> *imageFirstSuppressedClasses = @[];\n    CGFloat volumeFillValue = NAN;\n    NSUInteger blurSuppressed = 0;\n    NSArray<NSString *> *blurSuppressedClasses = @[];\n    if (imageView.image) {\n        BOOL sliderSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];\n        if (sliderSlot) {\n            UIView *imageScope = MGFindSliderView(root) ?: root;\n            NSMutableArray<NSString *> *classes=[NSMutableArray array];\n            imageFirstSuppressed = MGApplyBrightnessImageMode(imageScope, imageView, classes);\n            imageFirstSuppressed += MGApplyBrightnessLayerMode(imageScope.layer, imageScope.layer, imageView.layer, classes);\n            if ([slot isEqualToString:@"volume"]) volumeFillValue = MGApplyVolumeFillMask(imageView, imageScope);\n            strategy = [NSString stringWithFormat:@"%@-brightness-pattern-fill-aware", slot];\n            imageFirstSuppressedClasses = classes.copy;\n        } else {\n            strategy = [NSString stringWithFormat:@"%@-glyph-safe-background-only", slot];\n        }\n        if (removeBlur) {\n            NSMutableArray<NSString *> *classes=[NSMutableArray array];\n            blurSuppressed = MGSetModuleBlurHiddenRecursive(root, root, imageView, YES, classes, 0);\n            blurSuppressedClasses = classes.copy;\n            strategy = [strategy stringByAppendingString:@"-crisp"];\n        }\n    }\n\n    // Blur removal only touches module-sized non-interactive material surfaces.\n'''
rep(old,new,'apply behavior')

rep('removeBlurPref=%d materialMutation=0 opacity=%.2f expanded=0 strategy=%@','removeBlurPref=%d blurSuppressed=%lu blurClasses=%@ opacity=%.2f expanded=0 strategy=%@','diag blur fields')
rep('source, NSStringFromClass([controller class]), candidates, slot, path, exists, enabled, imageView.image != nil, removeBlur, opacity, strategy,','source, NSStringFromClass([controller class]), candidates, slot, path, exists, enabled, imageView.image != nil, removeBlur, (unsigned long)blurSuppressed, blurSuppressedClasses, opacity, strategy,','diag blur args')
rep('volumePercentageApplied=%d volumePercentageClass=%@ volumePercentageFrame=%@ volumePercentageText=%@ glowPref=%d','volumePercentageApplied=%d volumePercentageClass=%@ volumePercentageFrame=%@ volumePercentageText=%@ volumeFill=%.3f glowPref=%d','diag volume fill field')
rep('volumePercentageApplied, volumePercentageClass, NSStringFromCGRect(volumePercentageFrame), volumePercentageText, glow, glowIntensity, glowWidth]);','volumePercentageApplied, volumePercentageClass, NSStringFromCGRect(volumePercentageFrame), volumePercentageText, volumeFillValue, glow, glowIntensity, glowWidth]);','diag volume fill arg')

rep('''        Class moduleClass = NSClassFromString(@"CCUIModuleContainerViewController");\n        Class contentClass = NSClassFromString(@"CCUIContentModuleContainerViewController");\n\n        MGHookController(moduleClass,''','''        Class moduleClass = NSClassFromString(@"CCUIModuleContainerViewController");\n        Class contentClass = NSClassFromString(@"CCUIContentModuleContainerViewController");\n        Class sliderClass = NSClassFromString(@"CCUIContinuousSliderView");\n\n        MGHookController(moduleClass,''','slider class')
rep('''        MGHookController(contentClass, (IMP)MGContentViewDidLoad, (IMP)MGContentLayout, (IMP *)&MGOrigContentViewDidLoad, (IMP *)&MGOrigContentLayout);\n\n        MSHookMessageEx(UILabel.class,''','''        MGHookController(contentClass, (IMP)MGContentViewDidLoad, (IMP)MGContentLayout, (IMP *)&MGOrigContentViewDidLoad, (IMP *)&MGOrigContentLayout);\n        if (sliderClass && class_getInstanceMethod(sliderClass, @selector(setValue:))) {\n            MSHookMessageEx(sliderClass, @selector(setValue:), (IMP)MGSliderSetValue, (IMP *)&MGOrigSliderSetValue);\n        }\n\n        MSHookMessageEx(UILabel.class,''','slider hook')
s=s.replace('ModuleGlassRuntime 1.1.6 Glyph Safe Stretch Renderer loaded','ModuleGlassRuntime 1.1.7 Crisp Blur + Volume Fill Renderer loaded')
s=s.replace('moduleClass=%@ contentClass=%@", NSProcessInfo.processInfo.processName, getpid(), handle, moduleClass, contentClass);','moduleClass=%@ contentClass=%@ sliderClass=%@", NSProcessInfo.processInfo.processName, getpid(), handle, moduleClass, contentClass, sliderClass);',1)

for token in ['MGSetModuleBlurHiddenRecursive','MGApplyVolumeFillMask','MGSliderSetValue','1.1.7 Crisp Blur + Volume Fill Renderer']:
    assert token in s
p.write_text(s)
print('patched Module Glass renderer for 1.1.7')
