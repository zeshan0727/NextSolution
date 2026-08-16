from pathlib import Path
import re

src = Path('source/ModuleGlass/Tweak.m')
if not src.exists():
    raise SystemExit('expected source/ModuleGlass/Tweak.m baseline')
t = src.read_text()

# 1. Remove the 1.0.19 cloned-foreground repair mechanism completely.
t = t.replace('static NSInteger const MGForegroundRepairOverlayTag = 0x4D474652;\n', '')
t = t.replace('    MGRemoveForegroundRepairOverlays(root);\n', '')

pattern = re.compile(
    r'\nstatic void MGRemoveForegroundRepairOverlays\(UIView \*root\) \{.*?\n#pragma mark - Apply\n',
    re.S,
)
if not pattern.search(t):
    raise SystemExit('1.0.19 helper block not found')

stable_helpers = r'''
// Stable renderer selection.  Objective-C++ is used here deliberately so renderer
// families are explicit and cannot accidentally share destructive behavior.
enum class MGRendererKind : unsigned char {
    StandardTile,
    VolumeSlider,
    BrightnessSlider,
};

static MGRendererKind MGRendererKindForSlot(NSString *slot) {
    if ([slot isEqualToString:@"volume"]) return MGRendererKind::VolumeSlider;
    if ([slot isEqualToString:@"brightness"]) return MGRendererKind::BrightnessSlider;
    return MGRendererKind::StandardTile;
}

static CGFloat MGClamp01(CGFloat value) {
    if (!isfinite(value)) return -1.0;
    return MIN(1.0, MAX(0.0, value));
}

static CGFloat MGStableSliderValueFraction(UIView *slider) {
    if (!slider) return -1.0;

    // Prefer Apple's live value when exposed by the continuous slider.
    for (NSString *key in @[@"value", @"_value", @"normalizedValue", @"valueFraction", @"percentage"]) {
        @try {
            id obj = [slider valueForKey:key];
            if ([obj respondsToSelector:@selector(doubleValue)]) {
                double v = [obj doubleValue];
                if (isfinite(v)) {
                    if (v >= 0.0 && v <= 1.0) return MGClamp01((CGFloat)v);
                    if (v >= 0.0 && v <= 100.0) return MGClamp01((CGFloat)(v / 100.0));
                }
            }
        } @catch (__unused NSException *e) {}
    }

    // Volume always exposes the percentage text on this iOS generation; use it as a
    // safe fallback without ever changing the label's frame or value.
    UILabel *percentage = MGFindVolumePercentageLabel(slider);
    NSString *text = percentage.text ?: percentage.attributedText.string ?: @"";
    NSScanner *scanner = [NSScanner scannerWithString:text];
    double percent = 0.0;
    if ([scanner scanDouble:&percent] && [text containsString:@"%"] && percent >= 0.0 && percent <= 100.0) {
        return MGClamp01((CGFloat)(percent / 100.0));
    }
    return -1.0;
}

static void MGApplyStableVolumeValueMask(UIImageView *imageView, UIView *slider, CGFloat *outFraction) {
    if (!imageView) return;
    CGFloat fraction = MGStableSliderValueFraction(slider);
    if (outFraction) *outFraction = fraction;
    if (fraction < 0.0) return; // preserve Apple's copied mask if value is unavailable

    CGRect bounds = imageView.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat fullHeight = CGRectGetHeight(bounds);
    if (width <= 1.0 || fullHeight <= 1.0) return;

    // IMPORTANT: never resize the UIImageView.  The module remains Apple's full
    // 77x158 pill.  Only the visible artwork is masked from the bottom, which gives
    // the same shrinking-fill visual without moving the speaker or percentage.
    CGFloat minCap = MIN(width, fullHeight);
    CGFloat visibleHeight = MAX(minCap, fullHeight * fraction);
    visibleHeight = MIN(fullHeight, visibleHeight);
    CGRect visible = CGRectMake(0.0, fullHeight - visibleHeight, width, visibleHeight);
    CGFloat radius = MIN(width * 0.5, visibleHeight * 0.5);

    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:visible cornerRadius:radius];
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.frame = bounds;
    mask.path = path.CGPath;
    imageView.layer.mask = mask;
    imageView.clipsToBounds = YES;
    imageView.layer.masksToBounds = YES;
}

#pragma mark - Apply
'''
t = pattern.sub('\n' + stable_helpers, t, count=1)

# 2. Replace the destructive frame-resize block with a full-frame Core Animation mask.
frame_pattern = re.compile(
    r'''    CGFloat volumeValueFraction = -1\.0;\n'''
    r'''    if \(\[slot isEqualToString:@"volume"\]\) \{\n'''
    r'''        UIView \*volumeSlider = MGFindSliderView\(root\);\n'''
    r'''        imageFrame = MGVolumeValueSizedFrame\(imageFrame, volumeSlider, &volumeValueFraction\);\n'''
    r'''    \}\n'''
    r'''    imageView\.frame = imageFrame;\n'''
    r'''    imageView\.alpha = opacity;\n'''
    r'''    imageView\.hidden = imageView\.image == nil;\n'''
    r'''    imageView\.userInteractionEnabled = NO;\n'''
    r'''    MGCopyCornerGeometry\(imageView, cornerSource, root\);\n'''
    r'''    MGApplyModuleShapeFallback\(imageView, slot\);\n'''
    r'''    if \(\[slot isEqualToString:@"volume"\] && volumeValueFraction >= 0\.0\) \{.*?\n'''
    r'''    \}\n''',
    re.S,
)
replacement = '''    CGFloat volumeValueFraction = -1.0;\n    imageView.frame = imageFrame;\n    imageView.alpha = opacity;\n    imageView.hidden = imageView.image == nil;\n    imageView.userInteractionEnabled = NO;\n    MGCopyCornerGeometry(imageView, cornerSource, root);\n    MGApplyModuleShapeFallback(imageView, slot);\n    if ([slot isEqualToString:@"volume"]) {\n        UIView *volumeSlider = MGFindSliderView(root);\n        MGApplyStableVolumeValueMask(imageView, volumeSlider, &volumeValueFraction);\n    }\n'''
if not frame_pattern.search(t):
    raise SystemExit('1.0.19 Volume resize block not found')
t = frame_pattern.sub(replacement, t, count=1)

# 3. Standard modules must never use slider-style recursive alpha suppression.
old_suppression = '''    NSUInteger imageFirstSuppressed = 0;\n    NSArray<NSString *> *imageFirstSuppressedClasses = @[];\n    if (imageView.image) {\n        UIView *imageScope = [slot isEqualToString:@"volume"] ? MGFindSliderView(root) : root;\n        if (!imageScope) imageScope=root;\n        if (imageScope) {\n            NSMutableArray<NSString *> *classes=[NSMutableArray array];\n            if ([slot isEqualToString:@"brightness"]) {\n                imageFirstSuppressed = MGApplyBrightnessImageMode(imageScope, imageView, classes);\n                imageFirstSuppressed += MGApplyBrightnessLayerMode(root.layer, root.layer, imageView.layer, classes);\n                strategy = @"brightness-volume-pattern-root-fill-aware";\n            } else {\n                imageFirstSuppressed = MGApplyVolumeImageMode(imageScope, imageView, classes);\n                strategy = [NSString stringWithFormat:@"%@-image-first", slot];\n            }\n            imageFirstSuppressedClasses = classes.copy;\n        } else {\n            strategy=[NSString stringWithFormat:@"%@-no-host", slot];\n        }\n    }\n\n    NSUInteger repairedForegroundGlyphs = MGRepairCoveredForegroundImages(root, parent, imageView, slot);\n    if ([slot isEqualToString:@"volume"] && volumeValueFraction >= 0.0) {\n        strategy = [NSString stringWithFormat:@"volume-value-sized-%.0f", volumeValueFraction * 100.0];\n    }\n'''
new_suppression = '''    NSUInteger imageFirstSuppressed = 0;\n    NSArray<NSString *> *imageFirstSuppressedClasses = @[];\n    if (imageView.image) {\n        MGRendererKind renderer = MGRendererKindForSlot(slot);\n        NSMutableArray<NSString *> *classes=[NSMutableArray array];\n        if (renderer == MGRendererKind::BrightnessSlider) {\n            // Keep the already-approved Brightness renderer unchanged.\n            UIView *brightnessScope = MGFindSliderView(root) ?: root;\n            imageFirstSuppressed = MGApplyBrightnessImageMode(brightnessScope, imageView, classes);\n            imageFirstSuppressed += MGApplyBrightnessLayerMode(root.layer, root.layer, imageView.layer, classes);\n            strategy = @"stable-brightness-fill-aware";\n        } else if (renderer == MGRendererKind::VolumeSlider) {\n            UIView *volumeScope = MGFindSliderView(root) ?: root;\n            imageFirstSuppressed = MGApplyVolumeImageMode(volumeScope, imageView, classes);\n            strategy = volumeValueFraction >= 0.0\n                ? [NSString stringWithFormat:@"stable-volume-mask-%.0f", volumeValueFraction * 100.0]\n                : @"stable-volume-mask-value-unavailable";\n        } else {\n            // Critical stability rule: large/small tiles are passive backgrounds only.\n            // Never recurse through their Apple content tree and never change alpha on\n            // connectivity switches, glyphs, labels, buttons, or other foreground.\n            imageFirstSuppressed = 0;\n            strategy = @"stable-standard-passive-foreground-safe";\n        }\n        imageFirstSuppressedClasses = classes.copy;\n    }\n'''
if old_suppression not in t:
    raise SystemExit('1.0.19 suppression/repair block not found')
t = t.replace(old_suppression, new_suppression, 1)

# 4. Remove obsolete cloned-glyph diagnostic fields/arguments.
t = t.replace(
    ' suppressedClasses=%@ volumeValueFraction=%.3f repairedForegroundGlyphs=%lu volumeIconColorEnabled=',
    ' suppressedClasses=%@ volumeValueFraction=%.3f volumeIconColorEnabled=',
    1,
)
t = t.replace(
    'imageFirstSuppressedClasses, volumeValueFraction, (unsigned long)repairedForegroundGlyphs, volumeIconColorEnabled,',
    'imageFirstSuppressedClasses, volumeValueFraction, volumeIconColorEnabled,',
    1,
)

# 5. Stable release identity.
t = t.replace('ModuleGlassRuntime 1.0.15 Volume Value + Foreground Fix loaded', 'ModuleGlassRuntime 1.1.0 Stable Objective-C++ Renderer loaded')
t = t.replace('Volume value-sized runtime with repaired covered compact foreground glyphs', 'Stable Objective-C++ renderer: passive tiles, isolated sliders, full-frame Volume value mask')

# Migrate the compiled source to Objective-C++.
mm = Path('source/ModuleGlass/Tweak.mm')
mm.write_text(t)
src.unlink()

makefile = Path('source/ModuleGlass/Makefile')
mt = makefile.read_text()
mt = mt.replace('CCModuleBackgrounds_FILES = Tweak.m', 'CCModuleBackgrounds_FILES = Tweak.mm')
if 'CCModuleBackgrounds_CXXFLAGS' not in mt:
    mt = mt.replace('CCModuleBackgrounds_CFLAGS = -fobjc-arc -include $(THEOS_PROJECT_DIR)/Compat.h\n',
                    'CCModuleBackgrounds_CFLAGS = -fobjc-arc -include $(THEOS_PROJECT_DIR)/Compat.h\nCCModuleBackgrounds_CXXFLAGS = -std=c++17\n')
makefile.write_text(mt)

control = Path('source/ModuleGlass/control')
ct = control.read_text()
ct = re.sub(r'^Version: .*$', 'Version: 1.1.0', ct, flags=re.M)
ct = re.sub(r'^Description: .*$',
            'Description: Stable Objective-C++ Module Glass runtime with isolated slider renderers, full-frame Volume value masking, passive foreground-safe standard tiles, and preserved Brightness behavior.',
            ct, flags=re.M)
control.write_text(ct)

print('prepared Module Glass stable runtime 1.1.0')
