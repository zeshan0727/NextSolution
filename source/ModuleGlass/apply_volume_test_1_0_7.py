from pathlib import Path
import re

p = Path(__file__).with_name('Tweak.m')
t = p.read_text()

def replace_once(old: str, new: str, label: str):
    global t
    count = t.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, found {count}')
    t = t.replace(old, new, 1)

if 'volume-image-first-test' in t:
    raise SystemExit('Volume test patch already applied')

replace_once(
    'static char MGLastDiagnosticKey;\n',
    'static char MGLastDiagnosticKey;\nstatic char MGVolumeOriginalAlphaKey;\n',
    'volume alpha key')

old_slider = '''static UIView *MGFindSliderView(UIView *root) {
    if (!root) return nil;
    if (MGClassNameContains(root, @[@"continuousslider", @"slider"])) return root;
    for (UIView *view in root.subviews) {
        if (view.tag == MGImageTag) continue;
        UIView *found = MGFindSliderView(view);
        if (found) return found;
    }
    return nil;
}

static void MGRemoveTaggedImages'''

new_slider = '''static UIView *MGFindSliderView(UIView *root) {
    if (!root) return nil;
    if (MGClassNameContains(root, @[@"continuousslider", @"slider"])) return root;
    for (UIView *view in root.subviews) {
        if (view.tag == MGImageTag) continue;
        UIView *found = MGFindSliderView(view);
        if (found) return found;
    }
    return nil;
}

// Volume-only experiment. No other module calls these helpers.
static BOOL MGVolumeForegroundView(UIView *view) {
    if (!view) return NO;
    if ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class] || [view isKindOfClass:UIButton.class]) return YES;
    NSString *name = NSStringFromClass(view.class).lowercaseString;
    return [name containsString:@"label"] || [name containsString:@"glyph"] ||
           [name containsString:@"icon"] || [name containsString:@"button"] ||
           [name containsString:@"text"] || [name containsString:@"percentage"];
}

static BOOL MGVolumeSubtreeHasForeground(UIView *view) {
    if (!view) return NO;
    if (MGVolumeForegroundView(view)) return YES;
    for (UIView *child in view.subviews) {
        if (child.tag == MGImageTag) continue;
        if (MGVolumeSubtreeHasForeground(child)) return YES;
    }
    return NO;
}

static void MGRestoreVolumeVisuals(UIView *root) {
    if (!root) return;
    NSNumber *savedAlpha = objc_getAssociatedObject(root, &MGVolumeOriginalAlphaKey);
    if (savedAlpha) {
        root.alpha = savedAlpha.doubleValue;
        objc_setAssociatedObject(root, &MGVolumeOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *child in root.subviews) MGRestoreVolumeVisuals(child);
}

static BOOL MGVolumeObscuringVisual(UIView *view, UIView *slider, UIImageView *imageView) {
    if (!view || !slider || view == imageView || view.tag == MGImageTag) return NO;
    if ([imageView isDescendantOfView:view]) return NO;
    if ([view isKindOfClass:UIControl.class] || MGVolumeSubtreeHasForeground(view)) return NO;

    CGRect converted = [view convertRect:view.bounds toView:slider];
    CGFloat sliderArea = MAX(1.0, CGRectGetWidth(slider.bounds) * CGRectGetHeight(slider.bounds));
    CGFloat area = MAX(0.0, CGRectGetWidth(converted) * CGRectGetHeight(converted));
    CGFloat ratio = area / sliderArea;
    if (ratio < 0.10) return NO;

    NSString *name = NSStringFromClass(view.class).lowercaseString;
    BOOL namedVisual = [name containsString:@"material"] || [name containsString:@"effect"] ||
                       [name containsString:@"blur"] || [name containsString:@"fill"] ||
                       [name containsString:@"progress"] || [name containsString:@"background"] ||
                       [name containsString:@"tint"] || [name containsString:@"valueindicator"];
    BOOL plainLargeVisual = ([name isEqualToString:@"uiview"] || [name containsString:@"visualeffectsubview"]) && ratio >= 0.18;
    return namedVisual || plainLargeVisual;
}

static NSUInteger MGApplyVolumeImageMode(UIView *slider, UIImageView *imageView, NSMutableArray<NSString *> *suppressedClasses) {
    if (!slider || !imageView) return 0;
    NSUInteger count = 0;
    for (UIView *child in slider.subviews) {
        if (child.tag == MGImageTag) continue;
        if (MGVolumeObscuringVisual(child, slider, imageView)) {
            if (!objc_getAssociatedObject(child, &MGVolumeOriginalAlphaKey)) {
                objc_setAssociatedObject(child, &MGVolumeOriginalAlphaKey, @(child.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            child.alpha = 0.0;
            [suppressedClasses addObject:NSStringFromClass(child.class) ?: @"UIView"];
            count++;
            continue;
        }
        count += MGApplyVolumeImageMode(child, imageView, suppressedClasses);
    }
    return count;
}

static void MGRemoveTaggedImages'''
replace_once(old_slider, new_slider, 'volume helper block')

replace_once(
    '    NSString *slot = MGSlotForController(controller, &candidates);\n    BOOL expanded = MGIsExpanded(root);',
    '    NSString *slot = MGSlotForController(controller, &candidates);\n    MGRestoreVolumeVisuals(root);\n    BOOL expanded = MGIsExpanded(root);',
    'restore volume visuals')

replace_once(
    '    imageView.userInteractionEnabled = NO;\n    MGCopyCornerGeometry(imageView, cornerSource, root);\n\n    // Safety rule:',
    '''    imageView.userInteractionEnabled = NO;
    MGCopyCornerGeometry(imageView, cornerSource, root);

    NSUInteger volumeSuppressed = 0;
    NSArray<NSString *> *volumeSuppressedClasses = @[];
    if ([slot isEqualToString:@"volume"]) {
        UIView *volumeSlider = MGFindSliderView(root);
        if (volumeSlider) {
            NSMutableArray<NSString *> *classes = [NSMutableArray array];
            volumeSuppressed = MGApplyVolumeImageMode(volumeSlider, imageView, classes);
            volumeSuppressedClasses = classes.copy;
            strategy = @"volume-image-first-test";
        } else {
            strategy = @"volume-no-slider-found";
        }
    }

    // Safety rule:''',
    'volume apply block')

replace_once(
    'nativeRadius=%.2f imageFrame=%@ subviews=%lu imageView=%@ glowPref=%d glowIntensity=%.2f glowWidth=%.2f",\n                      source, NSStringFromClass([controller class]), candidates, slot, path, exists, enabled, imageView.image != nil, removeBlur, opacity, strategy, NSStringFromClass(root.class), NSStringFromCGRect(root.frame), NSStringFromClass(parent.class), anchor ? NSStringFromClass(anchor.class) : @"<none>", anchor ? NSStringFromCGRect(anchor.frame) : @"<none>", cornerSource.layer.cornerRadius, NSStringFromCGRect(imageView.frame), (unsigned long)parent.subviews.count, imageView, glow, glowIntensity, glowWidth]);',
    'nativeRadius=%.2f imageFrame=%@ subviews=%lu imageView=%@ volumeSuppressed=%lu suppressedClasses=%@ glowPref=%d glowIntensity=%.2f glowWidth=%.2f",\n                      source, NSStringFromClass([controller class]), candidates, slot, path, exists, enabled, imageView.image != nil, removeBlur, opacity, strategy, NSStringFromClass(root.class), NSStringFromCGRect(root.frame), NSStringFromClass(parent.class), anchor ? NSStringFromClass(anchor.class) : @"<none>", anchor ? NSStringFromCGRect(anchor.frame) : @"<none>", cornerSource.layer.cornerRadius, NSStringFromCGRect(imageView.frame), (unsigned long)parent.subviews.count, imageView, (unsigned long)volumeSuppressed, volumeSuppressedClasses, glow, glowIntensity, glowWidth]);',
    'volume diagnostics')

t = t.replace('ModuleGlassRuntime 1.0.6 loaded', 'ModuleGlassRuntime 1.0.7 Volume Test loaded')
t = t.replace('Passive slider-aware overlay runtime', 'Volume-isolated image-first test runtime')
p.write_text(t)

control = p.with_name('control')
ct = control.read_text()
ct = re.sub(r'^Version: .*$', 'Version: 1.0.7', ct, flags=re.M)
ct = re.sub(r'^Description: .*$', 'Description: Isolated Volume validation runtime for Module Glass. Other module rendering paths are unchanged.', ct, flags=re.M)
control.write_text(ct)
