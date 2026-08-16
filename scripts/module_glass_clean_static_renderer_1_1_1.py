from pathlib import Path
import re

p = Path('source/ModuleGlass/Tweak.mm')
if not p.exists():
    raise SystemExit('expected source/ModuleGlass/Tweak.mm 1.1.0 baseline')
t = p.read_text()

# State key: keep the tweak inert through compact <-> expanded transitions.
needle = 'static char MGBrightnessOriginalLayerOpacityKey;\n'
if needle not in t:
    raise SystemExit('state-key anchor missing')
t = t.replace(needle, needle + 'static char MGPresentationStateKey;\n', 1)

# Replace the value-mask helper with clean static-background helpers.
start = t.find('static void MGApplyStableVolumeValueMask(')
end = t.find('\n#pragma mark - Apply\n', start)
if start < 0 or end < 0:
    raise SystemExit('stable mask helper block missing')

helpers = r'''static BOOL MGViewTreeContainsForeground(UIView *node, UIView *host) {
    if (!node || !host || node.tag == MGImageTag) return NO;

    if ([node isKindOfClass:UIControl.class] || [node isKindOfClass:UILabel.class] || [node isKindOfClass:UIButton.class]) return YES;

    NSString *name = NSStringFromClass(node.class).lowercaseString ?: @"";
    if ([name containsString:@"label"] || [name containsString:@"glyph"] ||
        [name containsString:@"icon"] || [name containsString:@"button"] ||
        [name containsString:@"percentage"] || [name containsString:@"symbol"] ||
        [name containsString:@"text"]) return YES;

    if ([node isKindOfClass:UIImageView.class] && ((UIImageView *)node).image) {
        CGRect rect = [node convertRect:node.bounds toView:host];
        CGFloat hostArea = MAX(1.0, CGRectGetWidth(host.bounds) * CGRectGetHeight(host.bounds));
        CGFloat area = MAX(0.0, CGRectGetWidth(rect) * CGRectGetHeight(rect));
        if (area / hostArea <= 0.16) return YES; // glyph/icon, not a full background image
    }

    for (UIView *child in node.subviews) {
        if (MGViewTreeContainsForeground(child, host)) return YES;
    }
    return NO;
}

static UIView *MGFirstForegroundSibling(UIView *parent, UIView *backgroundAnchor) {
    if (!parent) return nil;
    NSInteger startIndex = 0;
    if (backgroundAnchor && backgroundAnchor.superview == parent) {
        NSInteger i = [parent.subviews indexOfObject:backgroundAnchor];
        if (i != NSNotFound) startIndex = i + 1;
    }
    NSArray<UIView *> *siblings = parent.subviews.copy;
    for (NSInteger i = startIndex; i < (NSInteger)siblings.count; i++) {
        UIView *candidate = siblings[(NSUInteger)i];
        if (candidate.tag == MGImageTag || candidate == backgroundAnchor) continue;
        if (MGViewTreeContainsForeground(candidate, parent)) return candidate;
    }
    return nil;
}

static void MGPlaceImageWithoutDimming(UIView *parent, UIImageView *imageView, UIView *backgroundAnchor, BOOL removeBlur) {
    if (!parent || !imageView) return;
    if (imageView.superview != parent) [imageView removeFromSuperview];

    if (!removeBlur) {
        // Native glass requested: preserve Apple's material above the photo.
        if (backgroundAnchor && backgroundAnchor.superview == parent) [parent insertSubview:imageView aboveSubview:backgroundAnchor];
        else if (!imageView.superview) [parent insertSubview:imageView atIndex:0];
        return;
    }

    // Remove Blur without touching Apple's material views: place the photo above all
    // background/tint siblings, but immediately below the first real foreground branch.
    UIView *foreground = MGFirstForegroundSibling(parent, backgroundAnchor);
    if (foreground && foreground.superview == parent) {
        [parent insertSubview:imageView belowSubview:foreground];
    } else if (backgroundAnchor && backgroundAnchor.superview == parent) {
        [parent insertSubview:imageView aboveSubview:backgroundAnchor];
    } else if (!imageView.superview) {
        // Safety fallback: never cover an unknown hierarchy's controls.
        [parent insertSubview:imageView atIndex:0];
    }
}

static void MGApplyStaticSliderGeometry(UIImageView *imageView) {
    if (!imageView) return;
    CGFloat width = CGRectGetWidth(imageView.bounds);
    CGFloat height = CGRectGetHeight(imageView.bounds);
    if (width <= 1.0 || height <= 1.0) return;
    imageView.layer.mask = nil;
    imageView.layer.maskedCorners = kCALayerAllCorners;
    imageView.layer.cornerRadius = MIN(width, height) * 0.5;
    if (@available(iOS 13.0, *)) imageView.layer.cornerCurve = kCACornerCurveContinuous;
    imageView.clipsToBounds = YES;
    imageView.layer.masksToBounds = YES;
}

enum class MGPresentationPhase : unsigned char {
    Compact = 1,
    Transition = 2,
    Expanded = 3,
};

static MGPresentationPhase MGPresentationPhaseForRoot(UIView *root) {
    if (!root) return MGPresentationPhase::Expanded;
    if (MGIsExpanded(root)) return MGPresentationPhase::Expanded;
    CGFloat w = CGRectGetWidth(root.bounds), h = CGRectGetHeight(root.bounds);
    if (w > 1.0 && h > 1.0 && w <= 360.0 && h <= 360.0) return MGPresentationPhase::Compact;
    return MGPresentationPhase::Transition;
}

static NSString *MGPresentationPhaseName(MGPresentationPhase phase) {
    switch (phase) {
        case MGPresentationPhase::Compact: return @"compact";
        case MGPresentationPhase::Transition: return @"transition";
        case MGPresentationPhase::Expanded: return @"expanded";
    }
    return @"unknown";
}
'''
t = t[:start] + helpers + t[end:]

# Slider insertion must use the stable slider shell itself, never Apple's changing fill/background frame.
vol_old = '''    // Freeze the already-validated Volume path exactly as it was in 1.0.15.\n    if ([slot isEqualToString:@"volume"]) {\n        UIView *scope = MGFindSliderView(root) ?: root;\n        UIView *native = MGFindNativeBackground(scope);\n        if (native.superview) {\n            if (outParent) *outParent = native.superview;\n            if (outAnchor) *outAnchor = native;\n            if (outFrame) *outFrame = native.frame;\n            if (outCornerSource) *outCornerSource = native;\n            if (outStrategy) *outStrategy = @"slider-native";\n            return YES;\n        }\n        if (scope != root) {\n            if (outParent) *outParent = scope;\n            if (outAnchor) *outAnchor = nil;\n            if (outFrame) *outFrame = scope.bounds;\n            if (outCornerSource) *outCornerSource = scope;\n            if (outStrategy) *outStrategy = @"slider-index0";\n            return YES;\n        }\n    }\n'''
vol_new = '''    // Volume is a full, static photo background. Never bind artwork geometry to Apple's value/fill view.\n    if ([slot isEqualToString:@"volume"]) {\n        UIView *scope = MGFindSliderView(root) ?: root;\n        if (outParent) *outParent = scope;\n        if (outAnchor) *outAnchor = nil;\n        if (outFrame) *outFrame = scope.bounds;\n        if (outCornerSource) *outCornerSource = scope;\n        if (outStrategy) *outStrategy = @"static-volume-slider-shell";\n        return YES;\n    }\n'''
if vol_old not in t:
    raise SystemExit('volume insertion block missing')
t = t.replace(vol_old, vol_new, 1)

bright_old = '''    // Brightness remains a slider, but uses its own fill-aware visual pass below.\n    if ([slot isEqualToString:@"brightness"]) {\n        UIView *scope = MGFindSliderView(root) ?: root;\n        UIView *native = MGFindNativeBackground(scope);\n        if (native.superview) {\n            UIView *matchingShape = MGFindMatchingAppleShape(native, root);\n            if (outParent) *outParent = native.superview;\n            if (outAnchor) *outAnchor = native;\n            if (outFrame) *outFrame = native.frame;\n            if (outCornerSource) *outCornerSource = matchingShape ?: native;\n            if (outStrategy) *outStrategy = @"brightness-volume-pattern-native-sibling";\n            return YES;\n        }\n        if (scope != root) {\n            if (outParent) *outParent = scope;\n            if (outAnchor) *outAnchor = nil;\n            if (outFrame) *outFrame = scope.bounds;\n            if (outCornerSource) *outCornerSource = scope;\n            if (outStrategy) *outStrategy = @"brightness-slider-index0";\n            return YES;\n        }\n    }\n'''
bright_new = '''    // Brightness uses the same stable shell rule: full static photo, native control above it.\n    if ([slot isEqualToString:@"brightness"]) {\n        UIView *scope = MGFindSliderView(root) ?: root;\n        if (outParent) *outParent = scope;\n        if (outAnchor) *outAnchor = nil;\n        if (outFrame) *outFrame = scope.bounds;\n        if (outCornerSource) *outCornerSource = scope;\n        if (outStrategy) *outStrategy = @"static-brightness-slider-shell";\n        return YES;\n    }\n'''
if bright_old not in t:
    raise SystemExit('brightness insertion block missing')
t = t.replace(bright_old, bright_new, 1)

# Start apply with a transition-safe early bypass. No recursive restoration or rendering while expanded/transitioning.
old_start = '''    NSArray<NSString *> *candidates = nil;\n    NSString *slot = MGSlotForController(controller, &candidates);\n    MGRestoreVolumeColorPresentation(root);\n    MGRestoreVolumeVisuals(root);\n    MGRestoreBrightnessLayers(root.layer);\n    BOOL expanded = MGIsExpanded(root);\n    BOOL enabled = MGBoolPreference(@"CCModuleBackgroundsEnabled", YES);\n'''
new_start = '''    NSArray<NSString *> *candidates = nil;\n    NSString *slot = MGSlotForController(controller, &candidates);\n    MGPresentationPhase phase = MGPresentationPhaseForRoot(root);\n    NSNumber *previousPhaseNumber = objc_getAssociatedObject(controller, &MGPresentationStateKey);\n    MGPresentationPhase previousPhase = previousPhaseNumber ? (MGPresentationPhase)previousPhaseNumber.unsignedCharValue : MGPresentationPhase::Compact;\n\n    if (phase != MGPresentationPhase::Compact) {\n        if (!previousPhaseNumber || previousPhase != phase) {\n            MGRemoveTaggedImages(root, nil);\n            if ([slot isEqualToString:@"volume"]) MGRestoreVolumeColorPresentation(root);\n            objc_setAssociatedObject(controller, &MGPresentationStateKey, @((unsigned char)phase), OBJC_ASSOCIATION_RETAIN_NONATOMIC);\n            NSString *sig = [NSString stringWithFormat:@"phase-bypass|%@|%@|%.0fx%.0f", slot, MGPresentationPhaseName(phase), CGRectGetWidth(root.bounds), CGRectGetHeight(root.bounds)];\n            MGDiagnosticOnce(controller, sig, [NSString stringWithFormat:@"phase-bypass source=%@ controller=%@ slot=%@ phase=%@ frame=%@ candidates=%@", source, NSStringFromClass([controller class]), slot, MGPresentationPhaseName(phase), NSStringFromCGRect(root.frame), candidates]);\n        }\n        return;\n    }\n\n    objc_setAssociatedObject(controller, &MGPresentationStateKey, @((unsigned char)MGPresentationPhase::Compact), OBJC_ASSOCIATION_RETAIN_NONATOMIC);\n    MGRestoreVolumeColorPresentation(root);\n    BOOL enabled = MGBoolPreference(@"CCModuleBackgroundsEnabled", YES);\n'''
if old_start not in t:
    raise SystemExit('apply start block missing')
t = t.replace(old_start, new_start, 1)

# Remove the old expanded block because phase handling now occurs before any renderer activity.
expanded_block = re.compile(r'''\n    if \(expanded\) \{\n        MGRemoveTaggedImages\(root, nil\);\n        NSString \*sig = \[NSString stringWithFormat:@"expanded\|%@\|%.0fx%.0f", slot, CGRectGetWidth\(root.bounds\), CGRectGetHeight\(root.bounds\)\];\n        MGDiagnosticOnce\(controller, sig, \[NSString stringWithFormat:@"expanded-bypass source=%@ controller=%@ slot=%@ frame=%@ candidates=%@", source, NSStringFromClass\(\[controller class\]\), slot, NSStringFromCGRect\(root.frame\), candidates\]\);\n        return;\n    \}\n''')
if not expanded_block.search(t):
    raise SystemExit('old expanded block missing')
t = expanded_block.sub('\n', t, count=1)

# New z-order placement replaces the old fixed above-native insertion.
old_place = '''    if (imageView.superview != parent) [imageView removeFromSuperview];\n    if (!imageView.superview) {\n        if (anchor && anchor.superview == parent) [parent insertSubview:imageView aboveSubview:anchor];\n        else [parent insertSubview:imageView atIndex:0];\n    } else if (anchor && anchor.superview == parent) {\n        [parent insertSubview:imageView aboveSubview:anchor];\n    }\n'''
new_place = '''    MGPlaceImageWithoutDimming(parent, imageView, anchor, removeBlur);\n'''
if old_place not in t:
    raise SystemExit('image placement block missing')
t = t.replace(old_place, new_place, 1)

# Geometry is full and static for both sliders; no value mask and no dynamic fill frame.
old_geom = '''    CGFloat volumeValueFraction = -1.0;\n    imageView.frame = imageFrame;\n    imageView.alpha = opacity;\n    imageView.hidden = imageView.image == nil;\n    imageView.userInteractionEnabled = NO;\n    MGCopyCornerGeometry(imageView, cornerSource, root);\n    MGApplyModuleShapeFallback(imageView, slot);\n    if ([slot isEqualToString:@"volume"]) {\n        UIView *volumeSlider = MGFindSliderView(root);\n        MGApplyStableVolumeValueMask(imageView, volumeSlider, &volumeValueFraction);\n    }\n'''
new_geom = '''    CGFloat volumeValueFraction = -1.0;\n    imageView.frame = imageFrame;\n    imageView.alpha = opacity;\n    imageView.hidden = imageView.image == nil;\n    imageView.userInteractionEnabled = NO;\n    if ([slot isEqualToString:@"volume"] || [slot isEqualToString:@"brightness"]) {\n        MGApplyStaticSliderGeometry(imageView);\n    } else {\n        MGCopyCornerGeometry(imageView, cornerSource, root);\n        MGApplyModuleShapeFallback(imageView, slot);\n    }\n'''
if old_geom not in t:
    raise SystemExit('slider geometry block missing')
t = t.replace(old_geom, new_geom, 1)

# Eliminate all runtime suppression for every renderer. Apple controls remain live and untouched.
sup_pattern = re.compile(r'''    NSUInteger imageFirstSuppressed = 0;\n    NSArray<NSString \*> \*imageFirstSuppressedClasses = @\[\];\n    if \(imageView\.image\) \{\n        MGRendererKind renderer = MGRendererKindForSlot\(slot\);.*?\n    \}\n\n    // Safety rule:''', re.S)
if not sup_pattern.search(t):
    raise SystemExit('renderer suppression block missing')
new_sup = '''    NSUInteger imageFirstSuppressed = 0;\n    NSArray<NSString *> *imageFirstSuppressedClasses = @[];\n    if (imageView.image) {\n        MGRendererKind renderer = MGRendererKindForSlot(slot);\n        if (renderer == MGRendererKind::VolumeSlider) strategy = @"static-volume-photo-foreground-safe";\n        else if (renderer == MGRendererKind::BrightnessSlider) strategy = @"static-brightness-photo-foreground-safe";\n        else strategy = removeBlur ? @"standard-photo-undimmed-foreground-safe" : @"standard-native-glass-foreground-safe";\n    }\n\n    // Safety rule:'''
t = sup_pattern.sub(new_sup, t, count=1)

# Update diagnostic wording and release identity.
t = t.replace('expanded=0 strategy=%@', 'phase=compact strategy=%@')
t = t.replace('ModuleGlassRuntime 1.1.0 Stable Objective-C++ Renderer loaded', 'ModuleGlassRuntime 1.1.1 Clean Static Renderer loaded')
t = t.replace('Stable Objective-C++ renderer: passive tiles, isolated sliders, full-frame Volume value mask', 'Clean static renderer: undimmed photos, full slider shells, transition-safe expanded bypass')

p.write_text(t)

control = Path('source/ModuleGlass/control')
ct = control.read_text()
ct = re.sub(r'^Version: .*$', 'Version: 1.1.1', ct, flags=re.M)
ct = re.sub(r'^Description: .*$', 'Description: Clean static Module Glass renderer with undimmed photo placement, full-shell Volume and Brightness backgrounds, untouched Apple foreground controls, and transition-safe expanded modules.', ct, flags=re.M)
control.write_text(ct)

print('prepared Module Glass 1.1.1 clean static renderer')
