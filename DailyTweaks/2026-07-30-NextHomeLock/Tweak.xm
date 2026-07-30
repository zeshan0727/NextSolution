#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static const void *NHLGestureKey = &NHLGestureKey;
static const void *NHLHandlerKey = &NHLHandlerKey;

static BOOL NHLClassNameContainsAny(NSString *className, NSArray<NSString *> *tokens) {
    for (NSString *token in tokens) {
        if ([className rangeOfString:token options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static BOOL NHLRootFolderIsEditing(UIView *rootView) {
    SEL editingSelector = NSSelectorFromString(@"isEditing");
    if ([rootView respondsToSelector:editingSelector]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(rootView, editingSelector);
    }
    return NO;
}

static BOOL NHLTouchIsOnSafeHomeBackground(UIView *view, UIView *rootView) {
    if (!view || !rootView || NHLRootFolderIsEditing(rootView)) {
        return NO;
    }

    static NSArray<NSString *> *blockedTokens;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blockedTokens = @[
            @"IconView",
            @"Folder",
            @"Dock",
            @"Widget",
            @"PageControl",
            @"Search",
            @"Library",
            @"Today",
            @"Button",
            @"ControlCenter",
            @"Switcher",
            @"Platter",
            @"Editing",
            @"ContextMenu"
        ];
    });

    BOOL reachedRootFolder = NO;
    for (UIView *current = view; current != nil; current = current.superview) {
        if ([current isKindOfClass:UIControl.class]) {
            return NO;
        }

        NSString *className = NSStringFromClass(current.class);
        if (NHLClassNameContainsAny(className, blockedTokens)) {
            return NO;
        }

        if (current == rootView || [className isEqualToString:@"SBRootFolderView"]) {
            reachedRootFolder = YES;
            break;
        }
    }

    return reachedRootFolder;
}

static void NHLLockDevice(void) {
    Class managerClass = objc_getClass("SBLockScreenManager");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    id manager = nil;

    if (managerClass && [managerClass respondsToSelector:sharedSelector]) {
        manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, sharedSelector);
    }

    SEL modernLockSelector = NSSelectorFromString(@"lockUIFromSource:withOptions:");
    if (manager && [manager respondsToSelector:modernLockSelector]) {
        ((void (*)(id, SEL, NSInteger, id))objc_msgSend)(manager, modernLockSelector, 1, nil);
        return;
    }

    SEL legacyLockSelector = NSSelectorFromString(@"lockUIFromSource:");
    if (manager && [manager respondsToSelector:legacyLockSelector]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(manager, legacyLockSelector, 1);
        return;
    }

    typedef void (*SBSLockDeviceFunction)(void);
    SBSLockDeviceFunction lockFunction = (SBSLockDeviceFunction)dlsym(RTLD_DEFAULT, "SBSLockDevice");
    if (!lockFunction) {
        void *framework = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
        if (framework) {
            lockFunction = (SBSLockDeviceFunction)dlsym(framework, "SBSLockDevice");
        }
    }

    if (lockFunction) {
        lockFunction();
    }
}

@interface NHLGestureHandler : NSObject <UIGestureRecognizerDelegate>
@end

@implementation NHLGestureHandler

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    return gestureRecognizer.view.window != nil && !NHLRootFolderIsEditing(gestureRecognizer.view);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return NHLTouchIsOnSafeHomeBackground(touch.view, gestureRecognizer.view);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateRecognized) {
        NHLLockDevice();
    }
}

@end

static void NHLInstallGestureOnRootFolderView(UIView *rootView) {
    if (!rootView || !rootView.window || objc_getAssociatedObject(rootView, NHLGestureKey)) {
        return;
    }

    NHLGestureHandler *handler = [NHLGestureHandler new];
    UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:handler
                                                                             action:@selector(handleDoubleTap:)];
    gesture.numberOfTapsRequired = 2;
    gesture.numberOfTouchesRequired = 1;
    gesture.cancelsTouchesInView = NO;
    gesture.delaysTouchesBegan = NO;
    gesture.delaysTouchesEnded = NO;
    gesture.delegate = handler;

    [rootView addGestureRecognizer:gesture];
    objc_setAssociatedObject(rootView, NHLGestureKey, gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(rootView, NHLHandlerKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook SBRootFolderView

- (void)didMoveToWindow {
    %orig;
    NHLInstallGestureOnRootFolderView((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    NHLInstallGestureOnRootFolderView((UIView *)self);
}

%end
