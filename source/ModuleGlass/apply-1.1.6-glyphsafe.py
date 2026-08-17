from pathlib import Path

p = Path('source/ModuleGlass/Tweak.m')
s = p.read_text()


def replace_once(old: str, new: str, name: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f'{name}: expected 1 match, got {count}')
    s = s.replace(old, new, 1)

replace_once(
    'imageView.contentMode = UIViewContentModeScaleAspectFill;',
    'imageView.contentMode = UIViewContentModeScaleToFill;',
    'stretch content mode',
)

replace_once(
'''static void MGApplyModuleShapeFallback(UIImageView *imageView, NSString *slot) {
    if (!imageView || [slot isEqualToString:@"volume"]) return; // validated Volume path stays untouched
    if (imageView.layer.mask || imageView.layer.cornerRadius > 1.0) return;

    CGFloat w = CGRectGetWidth(imageView.bounds);
    CGFloat h = CGRectGetHeight(imageView.bounds);
    CGFloat d = MIN(w, h);
    if (d <= 1.0) return;

    // Sliders are pills. Standard iOS 16 Control Center modules use roughly 22pt corners
    // at 77pt and ~30-32pt at larger compact sizes. This is only a fallback when Apple
    // exposes no usable mask/radius in the live hierarchy.
    CGFloat radius = [slot isEqualToString:@"brightness"] ? (d * 0.5) : MIN(32.0, d * 0.285);
    imageView.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) imageView.layer.cornerCurve = kCACornerCurveContinuous;
    imageView.clipsToBounds = YES;
    imageView.layer.masksToBounds = YES;
}''',
'''static void MGApplyModuleShapeFallback(UIImageView *imageView, NSString *slot) {
    if (!imageView) return;
    if (imageView.layer.mask || imageView.layer.cornerRadius > 1.0) return;

    CGFloat w = CGRectGetWidth(imageView.bounds);
    CGFloat h = CGRectGetHeight(imageView.bounds);
    CGFloat d = MIN(w, h);
    if (d <= 1.0) return;

    // Brightness and Volume are the same slider family and must share the same
    // pill geometry. Standard compact modules keep Apple's rounded-module shape.
    BOOL sliderSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];
    CGFloat radius = sliderSlot ? (d * 0.5) : MIN(32.0, d * 0.285);
    imageView.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) imageView.layer.cornerCurve = kCACornerCurveContinuous;
    imageView.clipsToBounds = YES;
    imageView.layer.masksToBounds = YES;
}''',
    'shared slider shape',
)

marker = '''static UIView *MGFindCompactClipHost(UIView *native, UIView *root) {
    if (!native || !root) return native ?: root;
    UIView *best = native;
    NSInteger bestScore = MGCompactHostScore(native, root, native);
    UIView *cursor = native.superview;
    NSInteger depth = 0;
    while (cursor && depth++ < 8) {
        NSInteger score = MGCompactHostScore(cursor, root, native);
        if (score > bestScore) { best = cursor; bestScore = score; }
        if (cursor == root) break;
        cursor = cursor.superview;
    }
    return best ?: native;
}
'''
if s.count(marker) != 1:
    raise SystemExit('module host marker mismatch')
addition = '''
// Select a background that actually belongs to the compact module shell.
// The old first-recursive-match rule could select an inner child button.
static NSInteger MGModuleBackgroundScore(UIView *candidate, UIView *root) {
    if (!candidate || !root || candidate == root || candidate.tag == MGImageTag || candidate.hidden) return NSIntegerMin;
    if (!MGClassNameContains(candidate, @[@"mtmaterialview", @"ccuimodulebackground",
                                          @"contentmodulebackground", @"modulebackground",
                                          @"material", @"background"])) return NSIntegerMin;

    CGRect rect = [candidate convertRect:candidate.bounds toView:root];
    CGFloat rootW = CGRectGetWidth(root.bounds), rootH = CGRectGetHeight(root.bounds);
    CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
    if (rootW <= 1.0 || rootH <= 1.0 || w <= 1.0 || h <= 1.0) return NSIntegerMin;

    CGFloat rootArea = MAX(1.0, rootW * rootH);
    CGFloat areaRatio = (w * h) / rootArea;
    if (areaRatio < 0.45 || areaRatio > 1.35) return NSIntegerMin;

    CGFloat widthRatio = w / rootW;
    CGFloat heightRatio = h / rootH;
    CGFloat centerDistance = hypot(CGRectGetMidX(rect) - CGRectGetMidX(root.bounds),
                                   CGRectGetMidY(rect) - CGRectGetMidY(root.bounds));
    CGFloat centerLimit = MAX(rootW, rootH) * 0.22;
    if (centerDistance > centerLimit) return NSIntegerMin;

    NSInteger score = 0;
    score += (NSInteger)(areaRatio * 7000.0);
    score -= (NSInteger)(fabs(widthRatio - 1.0) * 3000.0);
    score -= (NSInteger)(fabs(heightRatio - 1.0) * 3000.0);
    score -= (NSInteger)(centerDistance * 35.0);
    if (candidate.layer.mask) score += 900;
    if (candidate.layer.cornerRadius > 1.0) score += 700;
    NSString *name = NSStringFromClass(candidate.class).lowercaseString ?: @"";
    if ([name containsString:@"module"]) score += 900;
    if ([name containsString:@"background"] || [name containsString:@"material"]) score += 500;
    return score;
}

static void MGFindModuleBackgroundRecursive(UIView *node, UIView *root, UIView **best, NSInteger *bestScore, NSInteger depth) {
    if (!node || !root || depth > 24) return;
    NSInteger score = MGModuleBackgroundScore(node, root);
    if (score > *bestScore) {
        *best = node;
        *bestScore = score;
    }
    for (UIView *child in node.subviews) {
        if (child.tag == MGImageTag) continue;
        MGFindModuleBackgroundRecursive(child, root, best, bestScore, depth + 1);
    }
}

static UIView *MGFindModuleSizedBackground(UIView *root) {
    if (!root) return nil;
    UIView *best = nil;
    NSInteger bestScore = NSIntegerMin;
    MGFindModuleBackgroundRecursive(root, root, &best, &bestScore, 0);
    return best;
}
'''
s = s.replace(marker, marker + addition, 1)

start = s.index('static BOOL MGPrepareInsertion(')
end = s.index('\n#pragma mark - Apply', start)
s = s[:start] + '''static BOOL MGPrepareInsertion(UIView *root, NSString *slot, UIView **outParent, UIView **outAnchor, CGRect *outFrame, UIView **outCornerSource, NSString **outStrategy) {
    // Brightness and Volume are both continuous sliders and intentionally use
    // the exact same placement and shape path.
    BOOL sliderSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];
    if (sliderSlot) {
        UIView *scope = MGFindSliderView(root) ?: root;
        UIView *native = MGFindNativeBackground(scope);
        if (native.superview) {
            UIView *matchingShape = MGFindMatchingAppleShape(native, root);
            if (outParent) *outParent = native.superview;
            if (outAnchor) *outAnchor = native;
            if (outFrame) *outFrame = native.frame;
            if (outCornerSource) *outCornerSource = matchingShape ?: native;
            if (outStrategy) *outStrategy = [NSString stringWithFormat:@"%@-slider-native-sibling", slot];
            return YES;
        }
        if (outParent) *outParent = scope;
        if (outAnchor) *outAnchor = nil;
        if (outFrame) *outFrame = scope.bounds;
        if (outCornerSource) *outCornerSource = scope;
        if (outStrategy) *outStrategy = [NSString stringWithFormat:@"%@-slider-index0", slot];
        return YES;
    }

    // Standard modules use a module-sized shell. The image is directly above
    // Apple's shell background but below Apple's glyph/text/content.
    UIView *native = MGFindModuleSizedBackground(root);
    if (native && native.superview) {
        UIView *matchingShape = MGFindMatchingAppleShape(native, root);
        UIView *geometryHost = matchingShape ?: MGFindCompactClipHost(native, root);
        if (outParent) *outParent = native.superview;
        if (outAnchor) *outAnchor = native;
        if (outFrame) *outFrame = native.frame;
        if (outCornerSource) *outCornerSource = geometryHost ?: native;
        if (outStrategy) *outStrategy = matchingShape ? @"module-sized-native-sibling-apple-shape" : @"module-sized-native-sibling";
        return YES;
    }

    // Safe fallback: stretch to the compact controller bounds at the very back.
    if (outParent) *outParent = root;
    if (outAnchor) *outAnchor = nil;
    if (outFrame) *outFrame = root.bounds;
    if (outCornerSource) *outCornerSource = root;
    if (outStrategy) *outStrategy = @"module-bounds-index0";
    return YES;
}
''' + s[end:]

replace_once(
'''    NSUInteger imageFirstSuppressed = 0;
    NSArray<NSString *> *imageFirstSuppressedClasses = @[];
    if (imageView.image) {
        UIView *imageScope = [slot isEqualToString:@"volume"] ? MGFindSliderView(root) : root;
        if (!imageScope) imageScope=root;
        if (imageScope) {
            NSMutableArray<NSString *> *classes=[NSMutableArray array];
            if ([slot isEqualToString:@"brightness"]) {
                imageFirstSuppressed = MGApplyBrightnessImageMode(imageScope, imageView, classes);
                imageFirstSuppressed += MGApplyBrightnessLayerMode(root.layer, root.layer, imageView.layer, classes);
                strategy = @"brightness-volume-pattern-root-fill-aware";
            } else {
                imageFirstSuppressed = MGApplyVolumeImageMode(imageScope, imageView, classes);
                strategy = [NSString stringWithFormat:@"%@-image-first", slot];
            }
            imageFirstSuppressedClasses = classes.copy;
        } else {
            strategy=[NSString stringWithFormat:@"%@-no-host", slot];
        }
    }''',
'''    NSUInteger imageFirstSuppressed = 0;
    NSArray<NSString *> *imageFirstSuppressedClasses = @[];
    if (imageView.image) {
        BOOL sliderSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];
        if (sliderSlot) {
            UIView *imageScope = MGFindSliderView(root) ?: root;
            NSMutableArray<NSString *> *classes=[NSMutableArray array];

            // Volume now follows the exact same fill-aware renderer as Brightness.
            // Only slider background/fill visuals are suppressed. Glyphs, labels,
            // UIImageViews and controls stay native and above the custom image.
            imageFirstSuppressed = MGApplyBrightnessImageMode(imageScope, imageView, classes);
            imageFirstSuppressed += MGApplyBrightnessLayerMode(imageScope.layer, imageScope.layer, imageView.layer, classes);
            strategy = [NSString stringWithFormat:@"%@-brightness-pattern-fill-aware", slot];
            imageFirstSuppressedClasses = classes.copy;
        } else {
            // Normal modules are background-only: never recursively hide their UI.
            strategy = [NSString stringWithFormat:@"%@-glyph-safe-background-only", slot];
        }
    }''',
    'glyph safe apply branch',
)

s = s.replace(
    'ModuleGlassRuntime 1.0.14 Rounded Volume Pattern loaded',
    'ModuleGlassRuntime 1.1.6 Glyph Safe Stretch Renderer loaded',
)
s = s.replace(
    'Rounded Volume-pattern runtime with live native Volume icon and percentage color',
    'Glyph-safe stretch runtime with shared Brightness/Volume slider pattern',
)

# Hard gates for the three requested behaviors.
assert 'UIViewContentModeScaleToFill' in s
assert 'BOOL sliderSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"]' in s
assert 'MGApplyVolumeImageMode(imageScope' not in s
assert 'glyph-safe-background-only' in s
assert 'MGFindModuleSizedBackground' in s

p.write_text(s)
print('patched Module Glass renderer for 1.1.6')
