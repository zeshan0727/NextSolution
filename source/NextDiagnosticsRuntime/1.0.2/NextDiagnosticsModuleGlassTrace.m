#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <stdatomic.h>

static NSString *const NDControlPath=@"/var/mobile/Library/Preferences/com.nextsolution.nextdiagnostics.control.plist";
static NSString *const NDNotify=@"com.nextsolution.nextdiagnostics/control.changed";
static dispatch_queue_t NDLogQ;
static dispatch_queue_t NDWatchQ;
static BOOL NDActive=NO;
static NSString *NDSession=nil;
static NSString *NDLogPath=nil;
static BOOL NDSwizzled=NO;
static atomic_bool NDPingOutstanding;
static atomic_bool NDStallReported;
static atomic_ullong NDLastAckMillis;
static CFTimeInterval NDLastMove=0;

static unsigned long long NDMs(void){ return (unsigned long long)(CACurrentMediaTime()*1000.0); }
static NSString *NDSafe(NSString *s){ return s ?: @"-"; }
static NSString *NDClass(id o){ return o ? NSStringFromClass([o class]) : @"nil"; }
static BOOL NDCCName(NSString *s){
    if(!s) return NO;
    return [s containsString:@"CCUI"] || [s containsString:@"ControlCenter"] || [s containsString:@"Module"] || [s containsString:@"Platter"] || [s containsString:@"ContinuousSlider"];
}
static NSString *NDEscape(NSString *s){
    if(!s) return @"-";
    return [[[[s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"] stringByReplacingOccurrencesOfString:@"\t" withString:@"\\t"];
}
static void NDWrite(NSString *event, NSString *detail){
    if(!NDActive || !NDLogPath) return;
    unsigned long long ms=NDMs();
    NSString *line=[NSString stringWithFormat:@"[%llu] MGTRACE event=%@ %@\n",ms,NDSafe(event),NDSafe(detail)];
    NSString *path=[NDLogPath copy];
    dispatch_async(NDLogQ, ^{
        NSData *d=[line dataUsingEncoding:NSUTF8StringEncoding];
        if(![[NSFileManager defaultManager] fileExistsAtPath:path]) [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:@{NSFilePosixPermissions:@0644}];
        NSFileHandle *h=[NSFileHandle fileHandleForWritingAtPath:path];
        if(h){ @try { [h seekToEndOfFile]; [h writeData:d]; [h closeFile]; } @catch(__unused NSException *e){} }
    });
}
static NSString *NDRect(CGRect r){ return [NSString stringWithFormat:@"%.1f,%.1f,%.1f,%.1f",r.origin.x,r.origin.y,r.size.width,r.size.height]; }
static NSString *NDResponderPath(UIResponder *r){
    NSMutableArray *a=[NSMutableArray array];
    UIResponder *p=r;
    for(NSUInteger i=0;p && i<12;i++,p=p.nextResponder) [a addObject:NDClass(p)];
    return [a componentsJoinedByString:@">"];
}
static NSString *NDGestures(UIView *v){
    NSMutableArray *a=[NSMutableArray array];
    UIView *p=v;
    for(NSUInteger depth=0;p && depth<8;depth++,p=p.superview){
        for(UIGestureRecognizer *g in p.gestureRecognizers ?: @[]){
            [a addObject:[NSString stringWithFormat:@"%@:%ld:en%d@%@",NDClass(g),(long)g.state,g.enabled,NDClass(p)]];
            if(a.count>=24) return [a componentsJoinedByString:@","];
        }
    }
    return a.count?[a componentsJoinedByString:@","]:@"-";
}
static UIView *NDModuleAncestor(UIView *v){
    UIView *p=v;
    for(NSUInteger i=0;p && i<14;i++,p=p.superview) if(NDCCName(NDClass(p))) return p;
    return nil;
}
static void NDSnapshotNode(UIView *v, NSUInteger depth, NSUInteger *count, NSMutableString *out){
    if(!v || depth>5 || *count>=120) return;
    (*count)++;
    [out appendFormat:@"|d%lu %@ f=%@ b=%@ a=%.2f h=%d ui=%d sub=%lu",(unsigned long)depth,NDClass(v),NDRect(v.frame),NDRect(v.bounds),v.alpha,v.hidden,v.userInteractionEnabled,(unsigned long)v.subviews.count];
    for(UIView *s in v.subviews) NDSnapshotNode(s,depth+1,count,out);
}
static void NDSnapshot(UIView *t, NSString *reason){
    if(!NDActive || !t) return;
    UIView *root=NDModuleAncestor(t) ?: t.window.rootViewController.view ?: t.window;
    if(!root) return;
    NSUInteger count=0; NSMutableString *out=[NSMutableString string];
    NDSnapshotNode(root,0,&count,out);
    NDWrite(@"VIEW_SNAPSHOT",[NSString stringWithFormat:@"reason=%@ root=%@ nodes=%lu data=%@",reason,NDClass(root),(unsigned long)count,NDEscape(out)]);
}
static NSString *NDPhase(UITouchPhase p){ switch(p){case UITouchPhaseBegan:return @"began";case UITouchPhaseMoved:return @"moved";case UITouchPhaseStationary:return @"stationary";case UITouchPhaseEnded:return @"ended";case UITouchPhaseCancelled:return @"cancelled";} return @"unknown"; }
static BOOL NDRelevantTouch(UITouch *t){
    UIView *v=t.view;
    if(!v) return NO;
    UIView *p=v;
    for(NSUInteger i=0;p && i<14;i++,p=p.superview) if(NDCCName(NDClass(p))) return YES;
    return NDCCName(NDClass(v.window));
}

@interface UIApplication (NDMGTrace)
- (void)ndmg_sendEvent:(UIEvent *)event;
@end
@implementation UIApplication (NDMGTrace)
- (void)ndmg_sendEvent:(UIEvent *)event {
    BOOL relevant=NO; NSMutableArray *touchLines=[NSMutableArray array];
    if(NDActive && event.type==UIEventTypeTouches){
        for(UITouch *t in event.allTouches){
            if(!NDRelevantTouch(t)) continue;
            if(t.phase==UITouchPhaseMoved){ CFTimeInterval now=CACurrentMediaTime(); if(now-NDLastMove<0.08) continue; NDLastMove=now; }
            relevant=YES;
            UIView *v=t.view; CGPoint w=[t locationInView:v.window];
            [touchLines addObject:[NSString stringWithFormat:@"phase=%@ ts=%.6f taps=%lu x=%.1f y=%.1f view=%@ window=%@ responders=%@ gestures=%@",NDPhase(t.phase),t.timestamp,(unsigned long)t.tapCount,w.x,w.y,NDClass(v),NDClass(v.window),NDResponderPath(v),NDGestures(v)]];
            if(t.phase==UITouchPhaseBegan || t.phase==UITouchPhaseEnded || t.phase==UITouchPhaseCancelled) NDSnapshot(v,[NSString stringWithFormat:@"touch-%@",NDPhase(t.phase)]);
        }
        if(relevant) NDWrite(@"SEND_EVENT_ENTER",[touchLines componentsJoinedByString:@" || "]);
    }
    [self ndmg_sendEvent:event];
    if(relevant) NDWrite(@"SEND_EVENT_EXIT",@"returned=1");
}
@end

@interface UIControl (NDMGTrace)
- (void)ndmg_sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event;
@end
@implementation UIControl (NDMGTrace)
- (void)ndmg_sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    if(NDActive && (NDCCName(NDClass(self)) || NDCCName(NDClass(target)) || NDModuleAncestor(self)))
        NDWrite(@"CONTROL_ACTION_ENTER",[NSString stringWithFormat:@"control=%@ target=%@ action=%@ event=%ld",NDClass(self),NDClass(target),NSStringFromSelector(action),(long)event.type]);
    [self ndmg_sendAction:action to:target forEvent:event];
    if(NDActive && (NDCCName(NDClass(self)) || NDCCName(NDClass(target)) || NDModuleAncestor(self))) NDWrite(@"CONTROL_ACTION_EXIT",[NSString stringWithFormat:@"action=%@",NSStringFromSelector(action)]);
}
@end

@interface UIViewController (NDMGTrace)
- (void)ndmg_viewWillAppear:(BOOL)animated;
- (void)ndmg_viewDidAppear:(BOOL)animated;
- (void)ndmg_viewWillDisappear:(BOOL)animated;
- (void)ndmg_viewDidDisappear:(BOOL)animated;
- (void)ndmg_presentViewController:(UIViewController *)vc animated:(BOOL)animated completion:(void (^)(void))completion;
@end
@implementation UIViewController (NDMGTrace)
- (void)ndmg_viewWillAppear:(BOOL)a { if(NDActive&&NDCCName(NDClass(self))) NDWrite(@"VC_WILL_APPEAR",[NSString stringWithFormat:@"vc=%@ animated=%d",NDClass(self),a]); [self ndmg_viewWillAppear:a]; }
- (void)ndmg_viewDidAppear:(BOOL)a { [self ndmg_viewDidAppear:a]; if(NDActive&&NDCCName(NDClass(self))) NDWrite(@"VC_DID_APPEAR",[NSString stringWithFormat:@"vc=%@ animated=%d",NDClass(self),a]); }
- (void)ndmg_viewWillDisappear:(BOOL)a { if(NDActive&&NDCCName(NDClass(self))) NDWrite(@"VC_WILL_DISAPPEAR",[NSString stringWithFormat:@"vc=%@ animated=%d",NDClass(self),a]); [self ndmg_viewWillDisappear:a]; }
- (void)ndmg_viewDidDisappear:(BOOL)a { [self ndmg_viewDidDisappear:a]; if(NDActive&&NDCCName(NDClass(self))) NDWrite(@"VC_DID_DISAPPEAR",[NSString stringWithFormat:@"vc=%@ animated=%d",NDClass(self),a]); }
- (void)ndmg_presentViewController:(UIViewController *)vc animated:(BOOL)a completion:(void (^)(void))c {
    BOOL rel=NDActive&&(NDCCName(NDClass(self))||NDCCName(NDClass(vc)));
    if(rel) NDWrite(@"PRESENT_ENTER",[NSString stringWithFormat:@"from=%@ to=%@ animated=%d",NDClass(self),NDClass(vc),a]);
    [self ndmg_presentViewController:vc animated:a completion:^{ if(rel) NDWrite(@"PRESENT_COMPLETION",[NSString stringWithFormat:@"from=%@ to=%@",NDClass(self),NDClass(vc)]); if(c)c(); }];
    if(rel) NDWrite(@"PRESENT_RETURN",[NSString stringWithFormat:@"from=%@ to=%@",NDClass(self),NDClass(vc)]);
}
@end

static void NDSwap(Class c, SEL a, SEL b){ Method m1=class_getInstanceMethod(c,a),m2=class_getInstanceMethod(c,b); if(m1&&m2) method_exchangeImplementations(m1,m2); }
static void NDInstallSwizzles(void){
    if(NDSwizzled) return; NDSwizzled=YES;
    NDSwap(UIApplication.class,@selector(sendEvent:),@selector(ndmg_sendEvent:));
    NDSwap(UIControl.class,@selector(sendAction:to:forEvent:),@selector(ndmg_sendAction:to:forEvent:));
    NDSwap(UIViewController.class,@selector(viewWillAppear:),@selector(ndmg_viewWillAppear:));
    NDSwap(UIViewController.class,@selector(viewDidAppear:),@selector(ndmg_viewDidAppear:));
    NDSwap(UIViewController.class,@selector(viewWillDisappear:),@selector(ndmg_viewWillDisappear:));
    NDSwap(UIViewController.class,@selector(viewDidDisappear:),@selector(ndmg_viewDidDisappear:));
    NDSwap(UIViewController.class,@selector(presentViewController:animated:completion:),@selector(ndmg_presentViewController:animated:completion:));
    NDWrite(@"TRACE_HOOKS_READY",@"touch=1 controlAction=1 vcLifecycle=1 presentation=1 stallWatch=1 hierarchy=1");
}
static void NDStartWatchdog(void){
    static dispatch_once_t once; dispatch_once(&once, ^{
        atomic_store(&NDLastAckMillis,NDMs()); atomic_store(&NDPingOutstanding,false); atomic_store(&NDStallReported,false);
        dispatch_source_t t=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,NDWatchQ);
        dispatch_source_set_timer(t,dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),250*NSEC_PER_MSEC,30*NSEC_PER_MSEC);
        dispatch_source_set_event_handler(t, ^{
            if(!NDActive){ atomic_store(&NDPingOutstanding,false); atomic_store(&NDStallReported,false); return; }
            unsigned long long now=NDMs(), last=atomic_load(&NDLastAckMillis);
            if(atomic_load(&NDPingOutstanding)){
                unsigned long long lag=now-last;
                if(lag>=800 && !atomic_exchange(&NDStallReported,true)) NDWrite(@"MAIN_STALL",[NSString stringWithFormat:@"lag_ms=%llu",lag]);
                return;
            }
            atomic_store(&NDPingOutstanding,true);
            dispatch_async(dispatch_get_main_queue(), ^{
                unsigned long long ack=NDMs(), prev=atomic_exchange(&NDLastAckMillis,ack); BOOL stalled=atomic_exchange(&NDStallReported,false);
                atomic_store(&NDPingOutstanding,false);
                if(stalled) NDWrite(@"MAIN_RECOVERED",[NSString stringWithFormat:@"gap_ms=%llu",ack-prev]);
            });
        });
        dispatch_resume(t);
    });
}
static void NDLoadControl(void){
    NSDictionary *d=[NSDictionary dictionaryWithContentsOfFile:NDControlPath] ?: @{};
    BOOL enabled=[d[@"enabled"] boolValue]; NSString *slug=d[@"productSlug"]; NSString *sid=d[@"sessionID"];
    BOOL newActive=enabled && [slug isEqualToString:@"module-glass"] && sid.length>0;
    if(newActive){
        NDSession=[sid copy];
        NSString *dir=@"/var/mobile/Library/Logs/NextSolution"; [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:nil];
        NDLogPath=[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"NextDiagnostics-%@-bundle-SpringBoard.log",NDSession]];
        NDActive=YES; NDInstallSwizzles(); NDStartWatchdog();
        NDWrite(@"MODULE_GLASS_CAPTURE_ARMED",[NSString stringWithFormat:@"session=%@ proc=%@ pid=%d version=1.0.2 privacy=no-keyboard-no-text",NDSession,NSProcessInfo.processInfo.processName,getpid()]);
    } else if(NDActive){ NDWrite(@"MODULE_GLASS_CAPTURE_STOP",@"enabled=0"); NDActive=NO; NDSession=nil; NDLogPath=nil; }
}
static void NDNotifyCallback(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef ui){ dispatch_async(dispatch_get_main_queue(), ^{ NDLoadControl(); }); }
__attribute__((constructor)) static void NDInit(void){
    @autoreleasepool {
        if(![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;
        NDLogQ=dispatch_queue_create("com.nextsolution.nextdiagnostics.moduleglass.log",DISPATCH_QUEUE_SERIAL);
        NDWatchQ=dispatch_queue_create("com.nextsolution.nextdiagnostics.moduleglass.watchdog",DISPATCH_QUEUE_SERIAL);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,NDNotifyCallback,(__bridge CFStringRef)NDNotify,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
        dispatch_async(dispatch_get_main_queue(), ^{ NDLoadControl(); });
    }
}
