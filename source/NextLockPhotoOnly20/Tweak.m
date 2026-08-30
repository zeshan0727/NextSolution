#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

extern void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *result);

static CFStringRef const NLPrefs = CFSTR("com.nextsolution.lockglyphtime");
static CFStringRef const NLChanged = CFSTR("com.nextsolution.lockglyphtime/ReloadPrefs");
static NSMapTable<UIView *, NSMutableArray<UIImageView *> *> *NLViews;
static void (*NLOrigLayout)(UIView *, SEL);
static void (*NLOrigMove)(UIView *, SEL);

__attribute__((used)) static const char *NLMarker = "NextLock PhotoOnly Test20.2 four-frame renderer no-license";

static CFTypeRef NLCopy(NSString *key) {
    return CFPreferencesCopyAppValue((__bridge CFStringRef)key, NLPrefs);
}

static BOOL NLBool(NSString *key, BOOL fallback) {
    CFTypeRef value=NLCopy(key); if (!value) return fallback;
    BOOL result=fallback;
    if (CFGetTypeID(value)==CFBooleanGetTypeID()) result=CFBooleanGetValue(value);
    else if (CFGetTypeID(value)==CFNumberGetTypeID()) result=[(__bridge NSNumber *)value boolValue];
    CFRelease(value); return result;
}

static CGFloat NLNumber(NSString *key, CGFloat fallback) {
    CFTypeRef value=NLCopy(key); if (!value) return fallback;
    CGFloat result=fallback;
    if (CFGetTypeID(value)==CFNumberGetTypeID()) result=[(__bridge NSNumber *)value doubleValue];
    CFRelease(value); return result;
}

static NSInteger NLInteger(NSString *key, NSInteger fallback) {
    return (NSInteger)llround(NLNumber(key, fallback));
}

static NSString *NLKey(NSInteger frame, NSString *suffix) {
    if (frame==1 && [suffix isEqualToString:@"Width"]) return @"photoFrameWidth";
    if (frame==1 && [suffix isEqualToString:@"Height"]) return @"photoFrameHeight";
    return [NSString stringWithFormat:@"photoFrame%ld%@",(long)frame,suffix];
}

static NSString *NLPhotoPath(NSInteger frame) {
    return [NSString stringWithFormat:@"/var/mobile/Library/NextLockPhotos/frame%ld.png",(long)frame];
}

static BOOL NLImageHasAlpha(UIImage *image) {
    CGImageAlphaInfo a=CGImageGetAlphaInfo(image.CGImage);
    return a==kCGImageAlphaFirst || a==kCGImageAlphaLast || a==kCGImageAlphaPremultipliedFirst || a==kCGImageAlphaPremultipliedLast;
}

static NSMutableArray<UIImageView *> *NLFrameViews(UIView *host) {
    NSMutableArray *views=[NLViews objectForKey:host];
    if (views) return views;
    views=[NSMutableArray arrayWithCapacity:4];
    UIView *parent=host.superview ?: host;
    for (NSInteger i=1;i<=4;i++) {
        UIImageView *v=[[UIImageView alloc] initWithFrame:CGRectZero];
        v.userInteractionEnabled=NO; v.clipsToBounds=NO; v.hidden=YES;
        v.accessibilityIdentifier=[NSString stringWithFormat:@"NextLockPhotoFrame%ld",(long)i];
        [parent addSubview:v]; [views addObject:v];
    }
    [NLViews setObject:views forKey:host];
    return views;
}

static void NLRender(UIView *host) {
    if (!host.window) return;
    NSMutableArray<UIImageView *> *views=NLFrameViews(host);
    BOOL master=NLBool(@"enabled",YES);
    CGRect anchor=[host.superview convertRect:host.frame fromView:host.superview];
    for (NSInteger i=1;i<=4;i++) {
        UIImageView *v=views[i-1];
        BOOL enabled=master && NLBool([NSString stringWithFormat:@"photoFrame%ldEnabled",(long)i],NO);
        UIImage *image=[UIImage imageWithContentsOfFile:NLPhotoPath(i)];
        if (!enabled || !image) { v.hidden=YES; continue; }

        CGFloat width=MAX(20,MIN(600,NLNumber(NLKey(i,@"Width"),90)));
        CGFloat height=MAX(20,MIN(600,NLNumber(NLKey(i,@"Height"),90)));
        CGFloat x=NLNumber(NLKey(i,@"OffsetX"),0);
        CGFloat y=NLNumber(NLKey(i,@"OffsetY"),0);
        NSInteger target=NLInteger(NLKey(i,@"AnchorTarget"),0);
        NSInteger placement=NLInteger(NLKey(i,@"Position"),1);
        NSInteger mode=NLInteger(NLKey(i,@"ContentMode"),0);

        CGPoint point=CGPointMake(CGRectGetMidX(anchor), target==0 ? CGRectGetMinY(anchor)+CGRectGetHeight(anchor)*0.35 : CGRectGetMaxY(anchor)-CGRectGetHeight(anchor)*0.15);
        if (placement==0) point.x-=width*0.5+CGRectGetWidth(anchor)*0.28;
        else if (placement==1) point.x+=width*0.5+CGRectGetWidth(anchor)*0.28;
        else if (placement==2) point.y-=height*0.5+28;
        else point.y+=height*0.5+28;
        point.x+=x; point.y+=y;

        v.image=image; v.bounds=CGRectMake(0,0,width,height); v.center=point;
        BOOL alpha=NLImageHasAlpha(image);
        if (mode==1) v.contentMode=UIViewContentModeScaleToFill;
        else if (mode==2) v.contentMode=UIViewContentModeScaleAspectFit;
        else if (mode==3) v.contentMode=UIViewContentModeScaleAspectFill;
        else v.contentMode=alpha ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleAspectFill;
        v.clipsToBounds=(mode==3 || (!alpha && mode==0));
        v.layer.cornerRadius=v.clipsToBounds ? 14.0 : 0.0;
        v.hidden=NO;
    }
}

static void NLLayout(UIView *self, SEL cmd) { if (NLOrigLayout) NLOrigLayout(self,cmd); NLRender(self); }
static void NLMove(UIView *self, SEL cmd) {
    if (NLOrigMove) NLOrigMove(self,cmd);
    if (self.window) NLRender(self); else { for (UIView *v in [NLViews objectForKey:self]) [v removeFromSuperview]; [NLViews removeObjectForKey:self]; }
}
static void NLReload(CFNotificationCenterRef c,void *o,CFStringRef n,const void *obj,CFDictionaryRef info) {
    CFPreferencesAppSynchronize(NLPrefs);
    dispatch_async(dispatch_get_main_queue(),^{ for (UIView *host in NLViews) NLRender(host); });
}

__attribute__((constructor)) static void NLInit(void) {
    @autoreleasepool {
        NLViews=[NSMapTable weakToStrongObjectsMapTable];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,NLReload,NLChanged,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
        dispatch_async(dispatch_get_main_queue(),^{
            Class cls=NSClassFromString(@"SBFLockScreenDateView");
            if (cls) {
                MSHookMessageEx(cls,@selector(layoutSubviews),(IMP)NLLayout,(IMP *)&NLOrigLayout);
                MSHookMessageEx(cls,@selector(didMoveToWindow),(IMP)NLMove,(IMP *)&NLOrigMove);
            }
        });
    }
}
