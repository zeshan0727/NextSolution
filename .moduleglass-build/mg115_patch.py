from pathlib import Path

p=Path('buildsrc/Runtime/Tweak.m')
s=p.read_text()

def rep(old,new):
    global s
    assert old in s, old[:160]
    s=s.replace(old,new,1)

rep('''    BOOL sliderSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];
    if (sliderSlot) {
        UIView *scope = MGFindSliderView(root) ?: root;
        UIView *shell = MGSliderShellInScope(scope);
        if (outParent) *outParent = scope;
        if (outAnchor) *outAnchor = shell;
        if (outFrame) *outFrame = scope.bounds;
        if (outCornerSource) *outCornerSource = scope;
        if (outStrategy) *outStrategy = [NSString stringWithFormat:@"%@-full-slider-shell", slot];
        return YES;
    }
''','''    BOOL sliderSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];
    if (sliderSlot) {
        // Expansion-isolation mode: never place Module Glass views inside Apple's
        // CCUIContinuousSliderView hierarchy. Host the image beside the module's
        // native outer background and only read the slider value for our own mask.
        UIView *scope = MGFindSliderView(root) ?: root;
        UIView *native = MGFindModuleSizedBackground(root);
        if (native && native.superview) {
            UIView *parent = native.superview;
            if (outParent) *outParent = parent;
            if (outAnchor) *outAnchor = native;
            if (outFrame) *outFrame = [scope convertRect:scope.bounds toView:parent];
            if (outCornerSource) *outCornerSource = scope;
            if (outStrategy) *outStrategy = [NSString stringWithFormat:@"%@-external-slider-host", slot];
            return YES;
        }
        if (outParent) *outParent = root;
        if (outAnchor) *outAnchor = nil;
        if (outFrame) *outFrame = [scope convertRect:scope.bounds toView:root];
        if (outCornerSource) *outCornerSource = scope;
        if (outStrategy) *outStrategy = [NSString stringWithFormat:@"%@-external-slider-root-fallback", slot];
        return YES;
    }
''')

rep('''        if (sliderSlot) {
            UIView *imageScope = MGFindSliderView(root) ?: root;
            NSMutableArray<NSString *> *classes=[NSMutableArray array];
            imageFirstSuppressed = MGApplyBrightnessImageMode(imageScope, imageView, classes);
            imageFirstSuppressed += MGApplyBrightnessLayerMode(imageScope.layer, imageScope.layer, imageView.layer, classes);
            volumeFillValue = MGApplySliderFillMask(imageView, imageScope);
            strategy = [NSString stringWithFormat:@"%@-unified-full-pill-live-fill", slot];
            imageFirstSuppressedClasses = classes.copy;
        } else {
''','''        if (sliderSlot) {
            UIView *imageScope = MGFindSliderView(root) ?: root;
            // Do not mutate any Apple-owned slider view/layer in this build.
            // Our external image receives the live mask; Apple's hierarchy remains native.
            volumeFillValue = MGApplySliderFillMask(imageView, imageScope);
            strategy = [NSString stringWithFormat:@"%@-external-host-live-fill-no-apple-mutation", slot];
        } else {
''')

rep('''        if ([slot isEqualToString:@"connectivity"]) {
            NSMutableArray<NSString *> *connectivityClasses=[NSMutableArray array];
            NSUInteger connectivityCleared = MGClearConnectivityActiveBackgroundsRecursive(root, root, imageView, connectivityClasses, 0);
            if (connectivityCleared > 0) strategy = [strategy stringByAppendingString:@"-connectivity-glyph-only"];
        }
''','''        if ([slot isEqualToString:@"connectivity"]) {
            // Expansion-isolation mode: never modify Apple's connectivity toggle
            // backgroundColor/layer.backgroundColor. This intentionally leaves native
            // active-state circles visible for the test so expansion can be isolated.
            strategy = [strategy stringByAppendingString:@"-connectivity-native-toggle-state"];
        }
''')

# The old helper inserted Module Glass inside Apple's slider hierarchy. This build
# never calls it, so remove it entirely instead of weakening -Werror.
start=s.index('static UIView *MGSliderShellInScope(UIView *scope) {')
end=s.index('static void MGRemoveSliderShells(UIView *root)', start)
s=s[:start]+s[end:]

rep('ModuleGlassRuntime 1.1.14 Global Transition Quarantine Renderer loaded','ModuleGlassRuntime 1.1.15 External Host Isolation Renderer loaded')
p.write_text(s)

c=Path('buildsrc/Runtime/control')
t=c.read_text()
repls={
'Version: 1.1.14':'Version: 1.1.15',
'Description: RootHide Module Glass 1.1.14 with global Control Center transition quarantine; prevents parent/child render callbacks and Volume value-mask updates from mutating customized modules during expansion while preserving the 1.1.13 compact renderer.':'Description: RootHide Module Glass 1.1.15 expansion-isolation test. Volume/Brightness custom images are hosted outside Apple slider internals and Connectivity keeps native toggle colors so expandable Apple-owned views are not mutated.',
'Provides: com.nextsolution.nextaura.runtime.ccbackgrounds (= 1.1.14)':'Provides: com.nextsolution.nextaura.runtime.ccbackgrounds (= 1.1.15)',
'Conflicts: com.nextsolution.nextaura.runtime.ccbackgrounds (<= 1.1.13), com.nextsolution.unlockvibrate':'Conflicts: com.nextsolution.nextaura.runtime.ccbackgrounds (<= 1.1.14), com.nextsolution.unlockvibrate',
'Breaks: com.nextsolution.nextaura.runtime.ccbackgrounds (<= 1.1.13)':'Breaks: com.nextsolution.nextaura.runtime.ccbackgrounds (<= 1.1.14)',
'Replaces: com.nextsolution.nextaura.runtime.ccbackgrounds (<= 1.1.13)':'Replaces: com.nextsolution.nextaura.runtime.ccbackgrounds (<= 1.1.14)',
}
for a,b in repls.items():
    assert a in t,a
    t=t.replace(a,b,1)
c.write_text(t)
