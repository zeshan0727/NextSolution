from pathlib import Path
import re

p = Path('source/ModuleGlass/Tweak.m')
t = p.read_text()

# Add a dedicated tag for repaired foreground glyph overlays.
t = t.replace(
    'static NSInteger const MGVolumePercentageOverlayTag = 0x4D475650;\n',
    'static NSInteger const MGVolumePercentageOverlayTag = 0x4D475650;\nstatic NSInteger const MGForegroundRepairOverlayTag = 0x4D474652;\n',
    1,
)

# Insert helpers immediately before the Apply section.
anchor = '\n#pragma mark - Apply\n'
helpers = r'''
static void MGRemoveForegroundRepairOverlays(UIView *root) {
    if (!root) return;
    for (UIView *child in [root.subviews copy]) {
        if (child.tag == MGForegroundRepairOverlayTag) {
            [child removeFromSuperview];
            continue;
        }
        MGRemoveForegroundRepairOverlays(child);
    }
}

static CGFloat MGClamp01(CGFloat value) {
    if (!isfinite(value)) return -1.0;
    return MIN(1.0, MAX(0.0, value));
}

static CGFloat MGVolumeValueFraction(UIView *slider) {
    if (!slider) return -1.0;

    // The live percentage label is the most reliable source on iOS 16 because it is
    // the same value Apple is presenting to the user.
    UILabel *percentage = MGFindVolumePercentageLabel(slider);
    NSString *text = percentage.text ?: percentage.attributedText.string ?: @"";
    NSScanner *scanner = [NSScanner scannerWithString:text];
    double percent = 0.0;
    if ([scanner scanDouble:&percent] && [text containsString:@"%"] && percent >= 0.0 && percent <= 100.0) {
        return MGClamp01((CGFloat)(percent / 100.0));
    }

    // Fallback to common slider value keys. Values in 0...1 are used directly;
    // 0...100 is treated as a percentage.
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
    return -1.0;
}

static CGRect MGVolumeValueSizedFrame(CGRect fullFrame, UIView *slider, CGFloat *outFraction) {
    CGFloat fraction = MGVolumeValueFraction(slider);
    if (outFraction) *outFraction = fraction;
    if (fraction < 0.0) return fullFrame;

    CGFloat fullHeight = CGRectGetHeight(fullFrame);
    CGFloat width = CGRectGetWidth(fullFrame);
    if (fullHeight <= 1.0 || width <= 1.0) return fullFrame;

    // Match the visual behavior the user approved on Brightness: the visible pill
    // shrinks upward/downward with the value but never becomes thinner than one
    // circular cap, which is how Apple's continuous slider fill behaves at low values.
    CGFloat minCap = MIN(width, fullHeight);
    CGFloat visibleHeight = MAX(minCap, fullHeight * fraction);
    visibleHeight = MIN(fullHeight, visibleHeight);

    CGRect frame = fullFrame;
    frame.origin.y = CGRectGetMaxY(fullFrame) - visibleHeight;
    frame.size.height = visibleHeight;
    return frame;
}

static UIView *MGTopChildUnderParent(UIView *view, UIView *parent) {
    if (!view || !parent) return nil;
    UIView *cursor = view;
    UIView *previous = view;
    while (cursor && cursor != parent) {
        previous = cursor;
        cursor = cursor.superview;
    }
    return cursor == parent ? previous : nil;
}

static BOOL MGImageViewLooksLikeSmallGlyph(UIImageView *iv, UIView *parent) {
    if (!iv || !iv.image || iv.hidden || iv.tag == MGImageTag ||
        iv.tag == MGVolumeIconOverlayTag || iv.tag == MGForegroundRepairOverlayTag) return NO;
    CGRect rect = [iv convertRect:iv.bounds toView:parent];
    CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
    if (w < 6.0 || h < 6.0 || w > 68.0 || h > 68.0) return NO;
    return YES;
}

static NSUInteger MGRepairCoveredForegroundImagesRecursive(UIView *node, UIView *parent, UIImageView *backgroundImage) {
    if (!node || !parent || !backgroundImage) return 0;
    NSUInteger count = 0;

    if ([node isKindOfClass:UIImageView.class]) {
        UIImageView *source = (UIImageView *)node;
        if (MGImageViewLooksLikeSmallGlyph(source, parent)) {
            UIView *top = MGTopChildUnderParent(source, parent);
            NSInteger imageIndex = [parent.subviews indexOfObject:backgroundImage];
            NSInteger topIndex = top ? [parent.subviews indexOfObject:top] : NSNotFound;
            BOOL covered = top && imageIndex != NSNotFound && topIndex != NSNotFound && topIndex < imageIndex;
            if (covered) {
                CGRect frame = [source convertRect:source.bounds toView:parent];
                UIImageView *overlay = [[UIImageView alloc] initWithFrame:frame];
                overlay.tag = MGForegroundRepairOverlayTag;
                overlay.userInteractionEnabled = NO;
                overlay.backgroundColor = UIColor.clearColor;
                overlay.image = source.image;
                overlay.tintColor = source.tintColor;
                overlay.contentMode = source.contentMode;
                overlay.clipsToBounds = source.clipsToBounds;
                overlay.alpha = source.alpha;
                overlay.layer.cornerRadius = source.layer.cornerRadius;
                overlay.layer.masksToBounds = source.layer.masksToBounds;
                [parent addSubview:overlay];
                count++;
            }
        }
    }

    for (UIView *child in node.subviews) {
        if (child.tag == MGImageTag || child.tag == MGForegroundRepairOverlayTag) continue;
        count += MGRepairCoveredForegroundImagesRecursive(child, parent, backgroundImage);
    }
    return count;
}

static NSUInteger MGRepairCoveredForegroundImages(UIView *root, UIView *parent, UIImageView *backgroundImage, NSString *slot) {
    if (!root || !parent || !backgroundImage) return 0;
    // Slider foreground is already handled by its native controls and the dedicated
    // Volume icon/percentage logic. This repair is only for standard compact modules.
    if ([slot isEqualToString:@"volume"] || [slot isEqualToString:@"brightness"]) return 0;
    return MGRepairCoveredForegroundImagesRecursive(root, parent, backgroundImage);
}
'''
if anchor not in t:
    raise SystemExit('apply anchor missing')
t = t.replace(anchor, '\n' + helpers + anchor, 1)

# Remove stale repair overlays at the beginning of each apply.
t = t.replace(
    '    NSString *slot = MGSlotForController(controller, &candidates);\n    MGRestoreVolumeColorPresentation(root);',
    '    NSString *slot = MGSlotForController(controller, &candidates);\n    MGRemoveForegroundRepairOverlays(root);\n    MGRestoreVolumeColorPresentation(root);',
    1,
)

# Replace the image frame assignment block so Volume follows the live value.
old = '''    imageView.frame = imageFrame;
    imageView.alpha = opacity;
    imageView.hidden = imageView.image == nil;
    imageView.userInteractionEnabled = NO;
    MGCopyCornerGeometry(imageView, cornerSource, root);
    MGApplyModuleShapeFallback(imageView, slot);
'''
new = '''    CGFloat volumeValueFraction = -1.0;
    if ([slot isEqualToString:@"volume"]) {
        UIView *volumeSlider = MGFindSliderView(root);
        imageFrame = MGVolumeValueSizedFrame(imageFrame, volumeSlider, &volumeValueFraction);
    }
    imageView.frame = imageFrame;
    imageView.alpha = opacity;
    imageView.hidden = imageView.image == nil;
    imageView.userInteractionEnabled = NO;
    MGCopyCornerGeometry(imageView, cornerSource, root);
    MGApplyModuleShapeFallback(imageView, slot);
    if ([slot isEqualToString:@"volume"] && volumeValueFraction >= 0.0) {
        CGFloat cap = MIN(CGRectGetWidth(imageView.bounds), CGRectGetHeight(imageView.bounds));
        imageView.layer.cornerRadius = cap * 0.5;
        if (@available(iOS 13.0, *)) imageView.layer.cornerCurve = kCACornerCurveContinuous;
        imageView.layer.mask = nil;
        imageView.clipsToBounds = YES;
        imageView.layer.masksToBounds = YES;
    }
'''
if old not in t:
    raise SystemExit('image frame block missing')
t = t.replace(old, new, 1)

# Add foreground glyph repair after the image-first suppression pass.
needle = '''            imageFirstSuppressedClasses = classes.copy;
        } else {
            strategy=[NSString stringWithFormat:@"%@-no-host", slot];
        }
    }

    // Safety rule:'''
replacement = '''            imageFirstSuppressedClasses = classes.copy;
        } else {
            strategy=[NSString stringWithFormat:@"%@-no-host", slot];
        }
    }

    NSUInteger repairedForegroundGlyphs = MGRepairCoveredForegroundImages(root, parent, imageView, slot);
    if ([slot isEqualToString:@"volume"] && volumeValueFraction >= 0.0) {
        strategy = [NSString stringWithFormat:@"volume-value-sized-%.0f", volumeValueFraction * 100.0];
    }

    // Safety rule:'''
if needle not in t:
    raise SystemExit('suppression tail anchor missing')
t = t.replace(needle, replacement, 1)

# Extend diagnostics without rewriting the huge diagnostic format string structurally.
t = t.replace(
    'imageView=%@ imageFirstSuppressed=%lu suppressedClasses=%@ volumeIconColorEnabled=',
    'imageView=%@ imageFirstSuppressed=%lu suppressedClasses=%@ volumeValueFraction=%.3f repairedForegroundGlyphs=%lu volumeIconColorEnabled=',
    1,
)
t = t.replace(
    'imageView, (unsigned long)imageFirstSuppressed, imageFirstSuppressedClasses, volumeIconColorEnabled,',
    'imageView, (unsigned long)imageFirstSuppressed, imageFirstSuppressedClasses, volumeValueFraction, (unsigned long)repairedForegroundGlyphs, volumeIconColorEnabled,',
    1,
)

t = t.replace('ModuleGlassRuntime 1.0.14 Rounded Volume Pattern loaded', 'ModuleGlassRuntime 1.0.15 Volume Value + Foreground Fix loaded')
t = t.replace('Rounded Volume-pattern runtime with live native Volume icon and percentage color', 'Volume value-sized runtime with repaired covered compact foreground glyphs')
p.write_text(t)

c = Path('source/ModuleGlass/control')
ct = c.read_text()
ct = re.sub(r'^Version: .*$', 'Version: 1.0.15', ct, flags=re.M)
ct = re.sub(
    r'^Description: .*$',
    'Description: Rounded Module Glass runtime with value-sized Volume artwork matching Brightness behavior and protected compact-module foreground switch/glyph visibility.',
    ct,
    flags=re.M,
)
c.write_text(ct)
print('patched Module Glass runtime 1.0.15')
