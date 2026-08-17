from pathlib import Path

p=Path('source/ModuleGlass/Tweak.m')
s=p.read_text()

def one(old,new,name):
    global s
    if s.count(old)!=1: raise SystemExit(f'{name}: expected 1, found {s.count(old)}')
    s=s.replace(old,new,1)

one('static char MGConnectivityOriginalLayerBackgroundColorKey;\n\nstatic void (*MGOrigLabelSetText)(UILabel *, SEL, NSString *);',
    'static char MGConnectivityOriginalLayerBackgroundColorKey;\nstatic char MGExpansionSuspendedKey;\n\nstatic void (*MGOrigLabelSetText)(UILabel *, SEL, NSString *);','state-key')

one('static void (*MGOrigContentViewDidLoad)(id, SEL);\nstatic void (*MGOrigContentLayout)(id, SEL);\nstatic void (*MGOrigSliderSetValue)(id, SEL, CGFloat);',
'''static void (*MGOrigContentViewDidLoad)(id, SEL);
static void (*MGOrigContentLayout)(id, SEL);
static void (*MGOrigSliderSetValue)(id, SEL, CGFloat);
static void (*MGOrigModuleWillLayout)(id, SEL);
static void (*MGOrigContentWillLayout)(id, SEL);
static void (*MGOrigModuleWillTransition)(id, SEL, CGSize, id);
static void (*MGOrigContentWillTransition)(id, SEL, CGSize, id);
static void (*MGOrigModuleWillDisappear)(id, SEL, BOOL);
static void (*MGOrigContentWillDisappear)(id, SEL, BOOL);
static void (*MGOrigModuleDidAppear)(id, SEL, BOOL);
static void (*MGOrigContentDidAppear)(id, SEL, BOOL);''','orig-imps')

one('''static BOOL MGIsExpanded(UIView *root) {
    if (!root) return YES;
    CGFloat w = CGRectGetWidth(root.bounds), h = CGRectGetHeight(root.bounds);
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat sw = MIN(screen.width, screen.height);
    CGFloat sh = MAX(screen.width, screen.height);
    CGFloat rw = MIN(w, h), rh = MAX(w, h);
    if (w <= 1 || h <= 1) return YES;
    return (rw >= sw * 0.72 && rh >= sh * 0.38) || rw >= sw * 0.90 || rh >= sh * 0.68;
}''',
'''static BOOL MGSizeLooksExpanded(CGSize size) {
    CGFloat w=fabs(size.width), h=fabs(size.height);
    CGSize screen=UIScreen.mainScreen.bounds.size;
    CGFloat sw=MIN(screen.width,screen.height), sh=MAX(screen.width,screen.height);
    CGFloat rw=MIN(w,h), rh=MAX(w,h);
    if (w<=1 || h<=1) return YES;
    return (rw>=sw*0.72 && rh>=sh*0.38) || rw>=sw*0.90 || rh>=sh*0.68;
}

static BOOL MGIsExpanded(UIView *root) {
    return !root || MGSizeLooksExpanded(root.bounds.size);
}''','expanded-size')

anchor='static void MGApplyController(id controller, NSString *source) {\n'
helpers=r'''static void MGClearSliderAssociationsRecursive(UIView *root) {
    if (!root) return;
    UIImageView *fillImage=objc_getAssociatedObject(root,&MGVolumeFillImageKey);
    if ([fillImage isKindOfClass:UIImageView.class]) MGClearSliderFillMask(fillImage);
    objc_setAssociatedObject(root,&MGVolumeFillImageKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (UIView *child in root.subviews.copy) MGClearSliderAssociationsRecursive(child);
}

static void MGCleanupControllerVisuals(id controller, NSString *source) {
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

static BOOL MGSafeControllerBool(id controller, NSString *key) {
    @try { id value=[controller valueForKey:key]; return [value respondsToSelector:@selector(boolValue)] && [value boolValue]; }
    @catch (__unused NSException *e) { return NO; }
}

static BOOL MGControllerSignalsExpanded(id controller, UIView *root) {
    if (!controller || MGIsExpanded(root)) return YES;
    if ([controller isKindOfClass:UIViewController.class] && ((UIViewController *)controller).presentedViewController) return YES;
    for (NSString *key in @[@"expanded",@"_expanded",@"isExpanded",@"_isExpanded",@"isExpandedContentMode",@"_isExpandedContentMode"])
        if (MGSafeControllerBool(controller,key)) return YES;
    return NO;
}

static BOOL MGExpansionSuspended(id controller) {
    return [objc_getAssociatedObject(controller,&MGExpansionSuspendedKey) boolValue];
}

static void MGSetExpansionSuspended(id controller, BOOL suspended, NSString *source) {
    if (!controller) return;
    objc_setAssociatedObject(controller,&MGExpansionSuspendedKey,@(suspended),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (suspended) MGCleanupControllerVisuals(controller,source);
    objc_setAssociatedObject(controller,&MGLastDiagnosticKey,nil,OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static void MGResumeControllerIfCompact(id controller, NSString *source) {
    if (!controller || ![controller respondsToSelector:@selector(view)]) return;
    UIView *root=nil;
    @try { root=[controller view]; } @catch (__unused NSException *e) { return; }
    if (!root || MGControllerSignalsExpanded(controller,root)) return;
    MGSetExpansionSuspended(controller,NO,source);
    @synchronized (MGControllers) { [MGControllers addObject:controller]; }
    MGApplyController(controller,source);
}

'''
if s.count(anchor)!=1: raise SystemExit('apply anchor')
s=s.replace(anchor,helpers+anchor,1)

one('''    UIView *root = [controller view];
    if (!root) return;

    NSArray<NSString *> *candidates = nil;''',
'''    UIView *root = [controller view];
    if (!root) return;

    if (MGExpansionSuspended(controller) || MGControllerSignalsExpanded(controller,root)) {
        MGCleanupControllerVisuals(controller,MGExpansionSuspended(controller)?@"suspended-render-bypass":@"expanded-signal-bypass");
        return;
    }

    NSArray<NSString *> *candidates = nil;''','render-bypass')

hook_anchor='''static void MGHookController(Class cls, IMP loadHook, IMP layoutHook, IMP *oldLoad, IMP *oldLayout) {'''
lifecycle=r'''static BOOL MGHasTransitionCoordinator(id controller) {
    return [controller isKindOfClass:UIViewController.class] && ((UIViewController *)controller).transitionCoordinator!=nil;
}
static void MGModuleWillLayout(id self,SEL c){ if(MGHasTransitionCoordinator(self)) MGSetExpansionSuspended(self,YES,@"module-will-layout-transition"); if(MGOrigModuleWillLayout) MGOrigModuleWillLayout(self,c); }
static void MGContentWillLayout(id self,SEL c){ if(MGHasTransitionCoordinator(self)) MGSetExpansionSuspended(self,YES,@"content-will-layout-transition"); if(MGOrigContentWillLayout) MGOrigContentWillLayout(self,c); }

static void MGScheduleCompactResume(id controller,id coordinator,CGSize targetSize,NSString *source) {
    if (MGSizeLooksExpanded(targetSize)) return;
    __weak id weakController=controller;
    if (coordinator && [coordinator respondsToSelector:@selector(animateAlongsideTransition:completion:)]) {
        [coordinator animateAlongsideTransition:nil completion:^(__unused id context){ id strongController=weakController; if(strongController) MGResumeControllerIfCompact(strongController,source); }];
    } else dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.45*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ id strongController=weakController; if(strongController) MGResumeControllerIfCompact(strongController,source); });
}
static void MGModuleWillTransition(id self,SEL c,CGSize size,id coordinator){ MGSetExpansionSuspended(self,YES,@"module-transition-preclean"); if(MGOrigModuleWillTransition) MGOrigModuleWillTransition(self,c,size,coordinator); MGScheduleCompactResume(self,coordinator,size,@"module-transition-complete"); }
static void MGContentWillTransition(id self,SEL c,CGSize size,id coordinator){ MGSetExpansionSuspended(self,YES,@"content-transition-preclean"); if(MGOrigContentWillTransition) MGOrigContentWillTransition(self,c,size,coordinator); MGScheduleCompactResume(self,coordinator,size,@"content-transition-complete"); }
static void MGModuleWillDisappear(id self,SEL c,BOOL a){ MGSetExpansionSuspended(self,YES,@"module-disappear-preclean"); if(MGOrigModuleWillDisappear) MGOrigModuleWillDisappear(self,c,a); }
static void MGContentWillDisappear(id self,SEL c,BOOL a){ MGSetExpansionSuspended(self,YES,@"content-disappear-preclean"); if(MGOrigContentWillDisappear) MGOrigContentWillDisappear(self,c,a); }
static void MGModuleDidAppear(id self,SEL c,BOOL a){ if(MGOrigModuleDidAppear) MGOrigModuleDidAppear(self,c,a); MGResumeControllerIfCompact(self,@"module-appear-compact"); }
static void MGContentDidAppear(id self,SEL c,BOOL a){ if(MGOrigContentDidAppear) MGOrigContentDidAppear(self,c,a); MGResumeControllerIfCompact(self,@"content-appear-compact"); }

static IMP MGInstallLocalHook(Class cls,SEL sel,IMP hook) {
    if(!cls||!sel||!hook) return NULL;
    Method m=class_getInstanceMethod(cls,sel); if(!m) return NULL;
    IMP original=method_getImplementation(m); const char *types=method_getTypeEncoding(m);
    if(class_addMethod(cls,sel,hook,types)) return original;
    IMP old=NULL; MSHookMessageEx(cls,sel,hook,&old); return old?:original;
}
static void MGHookExpansionLifecycle(Class cls,IMP wl,IMP *owl,IMP wt,IMP *owt,IMP wd,IMP *owd,IMP da,IMP *oda) {
    if(!cls) return;
    *owl=MGInstallLocalHook(cls,@selector(viewWillLayoutSubviews),wl);
    *owt=MGInstallLocalHook(cls,@selector(viewWillTransitionToSize:withTransitionCoordinator:),wt);
    *owd=MGInstallLocalHook(cls,@selector(viewWillDisappear:),wd);
    *oda=MGInstallLocalHook(cls,@selector(viewDidAppear:),da);
}

'''
if s.count(hook_anchor)!=1: raise SystemExit('hook anchor')
s=s.replace(hook_anchor,lifecycle+hook_anchor,1)

one('''        MGHookController(moduleClass, (IMP)MGModuleViewDidLoad, (IMP)MGModuleLayout, (IMP *)&MGOrigModuleViewDidLoad, (IMP *)&MGOrigModuleLayout);
        MGHookController(contentClass, (IMP)MGContentViewDidLoad, (IMP)MGContentLayout, (IMP *)&MGOrigContentViewDidLoad, (IMP *)&MGOrigContentLayout);
        if (sliderClass && class_getInstanceMethod(sliderClass, @selector(setValue:))) {''',
'''        MGHookController(moduleClass, (IMP)MGModuleViewDidLoad, (IMP)MGModuleLayout, (IMP *)&MGOrigModuleViewDidLoad, (IMP *)&MGOrigModuleLayout);
        MGHookController(contentClass, (IMP)MGContentViewDidLoad, (IMP)MGContentLayout, (IMP *)&MGOrigContentViewDidLoad, (IMP *)&MGOrigContentLayout);
        MGHookExpansionLifecycle(moduleClass,(IMP)MGModuleWillLayout,(IMP *)&MGOrigModuleWillLayout,(IMP)MGModuleWillTransition,(IMP *)&MGOrigModuleWillTransition,(IMP)MGModuleWillDisappear,(IMP *)&MGOrigModuleWillDisappear,(IMP)MGModuleDidAppear,(IMP *)&MGOrigModuleDidAppear);
        MGHookExpansionLifecycle(contentClass,(IMP)MGContentWillLayout,(IMP *)&MGOrigContentWillLayout,(IMP)MGContentWillTransition,(IMP *)&MGOrigContentWillTransition,(IMP)MGContentWillDisappear,(IMP *)&MGOrigContentWillDisappear,(IMP)MGContentDidAppear,(IMP *)&MGOrigContentDidAppear);
        if (sliderClass && class_getInstanceMethod(sliderClass, @selector(setValue:))) {''','ctor')

one('ModuleGlassRuntime 1.1.10 Transparent Slider Shell Renderer loaded','ModuleGlassRuntime 1.1.11 Expansion-Safe Transition Renderer loaded','marker')
p.write_text(s)
