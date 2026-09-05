from pathlib import Path
import sys

root=Path(sys.argv[1])
p=root/'Tweak.m'
s=p.read_text()
anchor='''static void MGCleanupControllerVisuals(id controller, NSString *source) {'''
insert='''static void MGSetTaggedImagesHiddenRecursive(UIView *root, BOOL hidden) {
    if (!root) return;
    for (UIView *view in root.subviews.copy) {
        if (view.tag == MGImageTag) {
            view.hidden = hidden;
            continue;
        }
        if (view.tag == MGVolumeIconOverlayTag) {
            view.hidden = hidden;
            continue;
        }
        MGSetTaggedImagesHiddenRecursive(view, hidden);
    }
}

static void MGSuspendControllerVisualsNonDestructive(id controller, NSString *source) {
    if (!controller || ![controller respondsToSelector:@selector(view)]) return;
    UIView *root=nil;
    @try { root=[controller view]; } @catch (__unused NSException *e) { return; }
    if (!root) return;

    // CRITICAL: never add/remove UIKit views while Apple's Control Center expansion
    // transition is being prepared or animated. Only restore native presentation
    // properties and hide our already-existing overlays in place.
    MGSetTaggedImagesHiddenRecursive(root, YES);
    MGRestoreVolumeColorPresentation(root);
    MGRestoreVolumeVisuals(root);
    MGRestoreBrightnessLayers(root.layer);
    MGRestoreModuleBlurVisuals(root);
    MGRestoreConnectivityActiveBackgrounds(root);

    if (MGVerboseDiagnosticsEnabled()) MGLog(@"transition-suspend-nondestructive source=%@ controller=%@ frame=%@",source?:@"<nil>",NSStringFromClass([controller class]),NSStringFromCGRect(root.frame));
}

'''
assert anchor in s
assert 'MGSetTaggedImagesHiddenRecursive' not in s
s=s.replace(anchor,insert+anchor,1)

old='''    // One-shot cleanup only. Never mutate Apple's hierarchy repeatedly while a transition is running.\n    MGCleanupControllerVisuals(controller,source);'''
new='''    // Never structurally mutate Apple's hierarchy at transition start. Removing a\n    // custom image/shell here can invalidate Control Center's expansion snapshot and\n    // leave the module/container stuck after lock/unlock. Hide in place instead.\n    MGSuspendControllerVisualsNonDestructive(controller,source);'''
assert old in s
s=s.replace(old,new,1)

old='''    // Suspend for both directions. On expand this removes our visuals before Apple's layout starts;\n    // on collapse it simply keeps the renderer passive until compact geometry is stable.'''
new='''    // Suspend for both directions without changing the UIKit hierarchy. On expand we\n    // hide custom presentation in place; on collapse we keep the renderer passive\n    // until compact geometry is stable.'''
assert old in s
s=s.replace(old,new,1)

old='MGLog(@"ModuleGlassRuntime 1.1.12 One-Shot Transition Recovery Renderer loaded SpringBoard=%@ prefsEnabled=%d", NSBundle.mainBundle.bundleIdentifier, MGBoolPreference(@"CCModuleBackgroundsEnabled", YES));'
new='MGLog(@"ModuleGlassRuntime 1.1.13 Non-Destructive Transition Renderer loaded SpringBoard=%@ prefsEnabled=%d", NSBundle.mainBundle.bundleIdentifier, MGBoolPreference(@"CCModuleBackgroundsEnabled", YES));'
assert old in s
s=s.replace(old,new,1)

cleanup='''static void MGCleanupControllerVisuals(id controller, NSString *source) {
    if (!controller || ![controller respondsToSelector:@selector(view)]) return;
    UIView *root=nil;
    @try { root=[controller view]; } @catch (__unused NSException *e) { return; }
    if (!root) return;
    MGRestoreVolumeColorPresentation(root);
    MGRestoreVolumeVisuals(root);
    MGRestoreBrightnessLayers(root.layer);
    MGRestoreModuleBlurVisuals(root);
    MGRestoreConnectivityActiveBackgrounds(root);
    MGClearSliderAssociationsRecursive(root);
    MGRemoveSliderShells(root);
    MGRemoveTaggedImages(root,nil);
    if (MGVerboseDiagnosticsEnabled()) MGLog(@"expansion-cleanup source=%@ controller=%@ frame=%@",source?:@"<nil>",NSStringFromClass([controller class]),NSStringFromCGRect(root.frame));
}

'''
assert cleanup in s
s=s.replace(cleanup,'',1)

clear='''static void MGClearSliderAssociationsRecursive(UIView *root) {
    if (!root) return;
    UIImageView *fillImage=objc_getAssociatedObject(root,&MGVolumeFillImageKey);
    if ([fillImage isKindOfClass:UIImageView.class]) MGClearSliderFillMask(fillImage);
    objc_setAssociatedObject(root,&MGVolumeFillImageKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (UIView *child in root.subviews.copy) MGClearSliderAssociationsRecursive(child);
}

'''
assert clear in s
s=s.replace(clear,'',1)
s=s.replace('// Cleanup happens once, then the renderer becomes completely passive.','// Suspend non-destructively once, then the renderer becomes completely passive.',1)
p.write_text(s)

c=root/'control'
t=c.read_text()
repls={
    'Version: 1.1.12':'Version: 1.1.13',
    'Description: RootHide Module Glass 1.1.12 with one-shot expansion suspension and stable compact-state recovery; keeps the validated transparent unified slider renderer.':'Description: RootHide Module Glass 1.1.13 with non-destructive expansion suspension; preserves compact renderer features while avoiding UIKit hierarchy mutation during Apple Control Center transitions.',
    'Provides: com.nextsolution.nextaura.runtime.ccbackgrounds (= 1.1.12)':'Provides: com.nextsolution.nextaura.runtime.ccbackgrounds (= 1.1.13)',
    'Conflicts: com.nextsolution.nextaura.runtime.ccbackgrounds (<= 1.1.11), com.nextsolution.unlockvibrate':'Conflicts: com.nextsolution.nextaura.runtime.ccbackgrounds (<= 1.1.12), com.nextsolution.unlockvibrate',
    'Breaks: com.nextsolution.nextaura.runtime.ccbackgrounds (<= 1.1.11)':'Breaks: com.nextsolution.nextaura.runtime.ccbackgrounds (<= 1.1.12)',
    'Replaces: com.nextsolution.nextaura.runtime.ccbackgrounds (<= 1.1.11)':'Replaces: com.nextsolution.nextaura.runtime.ccbackgrounds (<= 1.1.12)',
}
for a,b in repls.items():
    assert a in t,a
    t=t.replace(a,b,1)
c.write_text(t)
