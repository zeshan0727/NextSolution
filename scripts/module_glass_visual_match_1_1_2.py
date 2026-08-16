from pathlib import Path
import re

src = Path('source/ModuleGlass/Tweak.mm')
control = Path('source/ModuleGlass/control')
s = src.read_text()

if 'ModuleGlassRuntime 1.1.2 Visual Match Renderer loaded' in s:
    print('Module Glass 1.1.2 already prepared')
    raise SystemExit(0)

required = [
    'MGPlaceImageWithoutDimming',
    'MGApplyStaticSliderGeometry',
    'MGPresentationPhaseForRoot',
    'static-volume-photo-foreground-safe',
    'static-brightness-photo-foreground-safe',
]
for marker in required:
    if marker not in s:
        raise SystemExit(f'missing 1.1.1 baseline marker: {marker}')

# New state keys used only for compact slider visual restoration.
needle = 'static char MGPresentationStateKey;\n'
replace = needle + 'static char MGSliderOriginalAlphaKey;\nstatic char MGBrightnessOriginalLayerOpacityKey;\n'
if 'MGSliderOriginalAlphaKey' not in s:
    s = s.replace(needle, replace, 1)

helpers = r'''
#pragma mark - Compact slider photo shell

static BOOL MGSliderForegroundView(UIView *view) {
    if (!view) return NO;
    if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UILabel.class] || [view isKindOfClass:UIButton.class]) return YES;
    NSString *name = NSStringFromClass(view.class).lowercaseString ?: @"";
    return [name containsString:@"label"] || [name containsString:@"glyph"] ||
           [name containsString:@"icon"] || [name containsString:@"button"] ||
           [name containsString:@"text"] || [name containsString:@"percentage"] ||
           [name containsString:@"speaker"] || [name containsString:@"sun"];
}

static BOOL MGSliderSubtreeHasForeground(UIView *view) {
    if (!view) return NO;
    if (MGSliderForegroundView(view)) return YES;
    for (UIView *child in view.subviews) {
        if (child.tag == MGImageTag) continue;
        if (MGSliderSubtreeHasForeground(child)) return YES;
    }
    return NO;
}

static void MGRestoreCompactSliderVisuals(UIView *root) {
    if (!root) return;
    NSNumber *savedAlpha = objc_getAssociatedObject(root, &MGSliderOriginalAlphaKey);
    if (savedAlpha) {
        root.alpha = savedAlpha.doubleValue;
        objc_setAssociatedObject(root, &MGSliderOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *child in root.subviews.copy) MGRestoreCompactSliderVisuals(child);
}

static BOOL MGVolumeCompactObscuringVisual(UIView *view, UIView *slider, UIImageView *imageView) {
    if (!view || !slider || view == imageView || view.tag == MGImageTag) return NO;
    if ([imageView isDescendantOfView:view]) return NO;
    if ([view isKindOfClass:UIControl.class] || MGSliderSubtreeHasForeground(view)) return NO;

    CGRect converted = [view convertRect:view.bounds toView:slider];
    CGFloat sliderArea = MAX(1.0, CGRectGetWidth(slider.bounds) * CGRectGetHeight(slider.bounds));
    CGFloat area = MAX(0.0, CGRectGetWidth(converted) * CGRectGetHeight(converted));
    CGFloat ratio = area / sliderArea;
    if (ratio < 0.10) return NO;

    NSString *name = NSStringFromClass(view.class).lowercaseString ?: @"";
    BOOL namedVisual = [name containsString:@"material"] || [name containsString:@"effect"] ||
                       [name containsString:@"blur"] || [name containsString:@"fill"] ||
                       [name containsString:@"progress"] || [name containsString:@"background"] ||
                       [name containsString:@"tint"] || [name containsString:@"valueindicator"] ||
                       [name containsString:@"backdrop"];
    BOOL plainLargeVisual = ([name isEqualToString:@"uiview"] || [name containsString:@"visualeffectsubview"]) && ratio >= 0.18;
    return namedVisual || plainLargeVisual;
}

static NSUInteger MGApplyVolumeCompactPhotoMode(UIView *slider, UIImageView *imageView, NSMutableArray<NSString *> *suppressedClasses) {
    if (!slider || !imageView) return 0;
    NSUInteger count = 0;
    for (UIView *child in slider.subviews.copy) {
        if (child.tag == MGImageTag) continue;
        if (MGVolumeCompactObscuringVisual(child, slider, imageView)) {
            if (!objc_getAssociatedObject(child, &MGSliderOriginalAlphaKey)) {
                objc_setAssociatedObject(child, &MGSliderOriginalAlphaKey, @(child.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            child.alpha = 0.0;
            [suppressedClasses addObject:NSStringFromClass(child.class) ?: @"UIView"];
            count++;
            continue;
        }
        count += MGApplyVolumeCompactPhotoMode(child, imageView, suppressedClasses);
    }
    return count;
}

static BOOL MGBrightnessCompactObscuringVisual(UIView *view, UIView *slider, UIImageView *imageView) {
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
                       [name containsString:@"tint"] || [name containsString:@"valueindicator"] ||
                       [name containsString:@"backdrop"];
    BOOL largeImageVisual = [view isKindOfClass:UIImageView.class] && ratio >= 0.16;
    BOOL plainLargeVisual = ([name isEqualToString:@"uiview"] || [name containsString:@"visualeffectsubview"]) && ratio >= 0.18 && !MGSliderSubtreeHasForeground(view);
    return namedVisual || largeImageVisual || plainLargeVisual;
}

static NSUInteger MGApplyBrightnessCompactPhotoMode(UIView *slider, UIImageView *imageView, NSMutableArray<NSString *> *suppressedClasses) {
    if (!slider || !imageView) return 0;
    NSUInteger count = 0;
    for (UIView *child in slider.subviews.copy) {
        if (child.tag == MGImageTag) continue;
        if (MGBrightnessCompactObscuringVisual(child, slider, imageView)) {
            if (!objc_getAssociatedObject(child, &MGSliderOriginalAlphaKey)) {
                objc_setAssociatedObject(child, &MGSliderOriginalAlphaKey, @(child.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            child.alpha = 0.0;
            [suppressedClasses addObject:NSStringFromClass(child.class) ?: @"UIView"];
            count++;
            continue;
        }
        count += MGApplyBrightnessCompactPhotoMode(child, imageView, suppressedClasses);
    }
    return count;
}

static void MGRestoreCompactBrightnessLayers(CALayer *layer) {
    if (!layer) return;
    NSNumber *saved = objc_getAssociatedObject(layer, &MGBrightnessOriginalLayerOpacityKey);
    if (saved) {
        layer.opacity = saved.floatValue;
        objc_setAssociatedObject(layer, &MGBrightnessOriginalLayerOpacityKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (CALayer *child in layer.sublayers.copy) MGRestoreCompactBrightnessLayers(child);
}

static BOOL MGLayerContainsLayerVisualMatch(CALayer *ancestor, CALayer *candidate) {
    CALayer *cursor = candidate;
    while (cursor) {
        if (cursor == ancestor) return YES;
        cursor = cursor.superlayer;
    }
    return NO;
}

static BOOL MGBrightnessCompactObscuringLayer(CALayer *layer, CALayer *sliderLayer, CALayer *imageLayer) {
    if (!layer || !sliderLayer || layer == imageLayer || MGLayerContainsLayerVisualMatch(layer, imageLayer)) return NO;
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

static NSUInteger MGApplyBrightnessCompactLayerMode(CALayer *layer, CALayer *sliderLayer, CALayer *imageLayer, NSMutableArray<NSString *> *classes) {
    if (!layer || !sliderLayer || !imageLayer) return 0;
    NSUInteger count = 0;
    for (CALayer *child in layer.sublayers.copy) {
        if (child == imageLayer) continue;
        if (MGBrightnessCompactObscuringLayer(child, sliderLayer, imageLayer)) {
            if (!objc_getAssociatedObject(child, &MGBrightnessOriginalLayerOpacityKey)) {
                objc_setAssociatedObject(child, &MGBrightnessOriginalLayerOpacityKey, @(child.opacity), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            child.opacity = 0.0f;
            [classes addObject:[NSString stringWithFormat:@"layer:%@", NSStringFromClass(child.class) ?: @"CALayer"]];
            count++;
            continue;
        }
        count += MGApplyBrightnessCompactLayerMode(child, sliderLayer, imageLayer, classes);
    }
    return count;
}

'''
anchor = 'static UIColor *MGVolumeColorFromHex(NSString *input) {'
if 'MGApplyVolumeCompactPhotoMode' not in s:
    s = s.replace(anchor, helpers + anchor, 1)

# Always show the selected photo at its real brightness. The background/tint material
# stays underneath; real foreground controls stay above.
start = s.index('static void MGPlaceImageWithoutDimming(')
end = s.index('static void MGApplyStaticSliderGeometry(', start)
placement = r'''static void MGPlaceImageWithoutDimming(UIView *parent, UIImageView *imageView, UIView *backgroundAnchor, BOOL removeBlur) {
    (void)removeBlur;
    if (!parent || !imageView) return;
    if (imageView.superview != parent) [imageView removeFromSuperview];

    UIView *foreground = MGFirstForegroundSibling(parent, backgroundAnchor);
    if (foreground && foreground.superview == parent) {
        [parent insertSubview:imageView belowSubview:foreground];
    } else if (backgroundAnchor && backgroundAnchor.superview == parent) {
        [parent insertSubview:imageView aboveSubview:backgroundAnchor];
    } else if (!imageView.superview) {
        [parent insertSubview:imageView atIndex:0];
    }
}

'''
s = s[:start] + placement + s[end:]

# Slider phase detection: only the real vertical compact pill may use the custom
# compact renderer. Any growth is a transition and must become inert immediately.
old_phase = re.search(r'static MGPresentationPhase MGPresentationPhaseForRoot\(UIView \*root\) \{.*?\n\}', s, re.S)
if not old_phase:
    raise SystemExit('presentation phase function not found')
new_phase = r'''static MGPresentationPhase MGPresentationPhaseForRoot(UIView *root, NSString *slot) {
    if (!root) return MGPresentationPhase::Expanded;
    if (MGIsExpanded(root)) return MGPresentationPhase::Expanded;
    CGFloat w = CGRectGetWidth(root.bounds), h = CGRectGetHeight(root.bounds);

    if ([slot isEqualToString:@"volume"] || [slot isEqualToString:@"brightness"]) {
        BOOL stableVerticalPill = w >= 55.0 && w <= 115.0 && h >= 115.0 && h <= 220.0;
        return stableVerticalPill ? MGPresentationPhase::Compact : MGPresentationPhase::Transition;
    }

    if (w > 1.0 && h > 1.0 && w <= 360.0 && h <= 360.0) return MGPresentationPhase::Compact;
    return MGPresentationPhase::Transition;
}'''
s = s[:old_phase.start()] + new_phase + s[old_phase.end():]
s = s.replace('MGPresentationPhase phase = MGPresentationPhaseForRoot(root);',
              'MGPresentationPhase phase = MGPresentationPhaseForRoot(root, slot);', 1)

# Restore Apple slider visuals before *any* transition/expanded work.
phase_guard = '    if (phase != MGPresentationPhase::Compact) {\n'
phase_restore = '''    if (phase != MGPresentationPhase::Compact) {
        if ([slot isEqualToString:@"volume"] || [slot isEqualToString:@"brightness"]) {
            MGRestoreCompactSliderVisuals(root);
            MGRestoreCompactBrightnessLayers(root.layer);
        }
'''
if phase_guard not in s:
    raise SystemExit('phase guard not found')
s = s.replace(phase_guard, phase_restore, 1)

# Before each compact slider pass, restore the native state and then selectively hide
# only its compact background/fill visuals again. This makes reopen/reclose deterministic.
compact_restore_needle = '    MGRestoreVolumeColorPresentation(root);\n    BOOL enabled = MGBoolPreference(@"CCModuleBackgroundsEnabled", YES);'
compact_restore_repl = '''    MGRestoreVolumeColorPresentation(root);
    if ([slot isEqualToString:@"volume"] || [slot isEqualToString:@"brightness"]) {
        MGRestoreCompactSliderVisuals(root);
        MGRestoreCompactBrightnessLayers(root.layer);
    }
    BOOL enabled = MGBoolPreference(@"CCModuleBackgroundsEnabled", YES);'''
if compact_restore_needle not in s:
    raise SystemExit('compact restore anchor not found')
s = s.replace(compact_restore_needle, compact_restore_repl, 1)

# The user's selected image must never sit under a dimming material.
s = s.replace('MGPlaceImageWithoutDimming(parent, imageView, anchor, removeBlur);',
              'MGPlaceImageWithoutDimming(parent, imageView, anchor, YES);', 1)

# Replace the 1.1.1 passive slider branch with full-photo slider shells. No value mask,
# no resizing, and no standard-module suppression.
renderer_start = s.index('    NSUInteger imageFirstSuppressed = 0;')
renderer_end = s.index('    // Safety rule:', renderer_start)
renderer = r'''    NSUInteger imageFirstSuppressed = 0;
    NSArray<NSString *> *imageFirstSuppressedClasses = @[];
    if (imageView.image) {
        MGRendererKind renderer = MGRendererKindForSlot(slot);
        NSMutableArray<NSString *> *classes = [NSMutableArray array];
        if (renderer == MGRendererKind::VolumeSlider) {
            UIView *volumeScope = MGFindSliderView(root) ?: root;
            imageFirstSuppressed = MGApplyVolumeCompactPhotoMode(volumeScope, imageView, classes);
            strategy = @"visualmatch-volume-full-photo";
        } else if (renderer == MGRendererKind::BrightnessSlider) {
            UIView *brightnessScope = MGFindSliderView(root) ?: root;
            imageFirstSuppressed = MGApplyBrightnessCompactPhotoMode(brightnessScope, imageView, classes);
            imageFirstSuppressed += MGApplyBrightnessCompactLayerMode(brightnessScope.layer, brightnessScope.layer, imageView.layer, classes);
            strategy = @"visualmatch-brightness-full-photo";
        } else {
            // Connectivity, Now Playing and 1x1 modules stay foreground-safe. We do
            // not recurse through their content tree or touch button/glyph alpha.
            strategy = @"visualmatch-standard-undimmed-foreground-safe";
        }
        imageFirstSuppressedClasses = classes.copy;
    }

'''
s = s[:renderer_start] + renderer + s[renderer_end:]

# Release identity and diagnostics.
s = s.replace('ModuleGlassRuntime 1.1.1 Clean Static Renderer loaded',
              'ModuleGlassRuntime 1.1.2 Visual Match Renderer loaded')
s = s.replace('static-volume-photo-foreground-safe', 'visualmatch-volume-full-photo')
s = s.replace('static-brightness-photo-foreground-safe', 'visualmatch-brightness-full-photo')
s = s.replace('standard-photo-undimmed-foreground-safe', 'visualmatch-standard-undimmed-foreground-safe')

src.write_text(s)

ct = control.read_text()
ct = re.sub(r'^Version: .*$', 'Version: 1.1.2', ct, flags=re.M)
ct = re.sub(r'^Description: .*$', 'Description: Visual-match Module Glass renderer with original-brightness photos, full-photo compact Volume/Brightness pills, foreground-safe connectivity, and immediate transition restoration.', ct, flags=re.M)
control.write_text(ct)

print('prepared Module Glass 1.1.2 visual match renderer')
