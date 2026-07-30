#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static NSString *const NHLVersion = @"1.0.3";
static NSString *const NHLStatusPath = @"/var/mobile/Library/Preferences/com.nextsolution.nexthomelock.runtime.plist";
static CFStringRef const NHLTestLockNotification = CFSTR("com.nextsolution.nexthomelock.test-lock");

static const void *NHLGestureKey = &NHLGestureKey;
static const void *NHLHandlerKey = &NHLHandlerKey;
static dispatch_queue_t NHLStatusQueue;
static NSString *NHLLastTouchSignature;
static NSTimeInterval NHLLastTouchWriteTime = 0;

static void NHLWriteStatus(NSDictionary *updates) {
    if (!updates || !NHLStatusQueue) return;

    dispatch_async(NHLStatusQueue, ^{
        NSMutableDictionary *status = [NSMutableDictionary dictionaryWithContentsOfFile:NHLStatusPath];
        if (!status) status = [NSMutableDictionary dictionary];
        [status addEntriesFromDictionary:updates];
        status[@"updatedAt"] = @([[NSDate date] timeIntervalSince1970]);
        [status writeToFile:NHLStatusPath atomically:YES];
    });
}

static void NHLRecordTouch(UIView *view, BOOL accepted, NSString *reason) {
    NSString *className = view ? NSStringFromClass(view.class) : @"(nil)";
    NSString *signature = [NSString stringWithFormat:@"%@|%@|%@", className, accepted ? @"YES" : @"NO", reason ?: @""];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;

    @synchronized ([NSObject class]) {
        if ([NHLLastTouchSignature isEqualToString:signature] && (now - NHLLastTouchWriteTime) < 1.0) return;
        NHLLastTouchSignature = signature;
        NHLLastTouchWriteTime = now;
    }

    NHLWriteStatus(@{
        @"lastTouchClass": className,
        @"lastTouchAccepted": @(accepted),
        @"lastTouchReason": reason ?: @"Unknown",
        @"lastTouchAt": @(now)
    });
}

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
    if (!view || !rootView) {
        NHLRecordTouch(view, NO, @"Missing touch view or gesture host");
        return NO;
    }

    if (NHLRootFolderIsEditing(rootView)) {
        NHLRecordTouch(view, NO, @"Home Screen is editing");
        return NO;
    }

    static NSArray<NSString *> *blockedTokens;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blockedTokens = @[
            @"IconView",
            @"FolderIcon",
            @"FolderController",
            @"FolderContainer",
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

    for (UIView *current = view; current != nil; current = current.superview) {
        NSString *className = NSStringFromClass(current.class);

        // The valid Home Screen container itself contains the word "Folder".
        // Accept it before applying interactive-child rejection rules.
        if (current == rootView || [className isEqualToString:@"SBRootFolderView"]) {
            NHLRecordTouch(view, YES, @"Reached Home Screen background");
            return YES;
        }

        if ([current isKindOfClass:UIControl.class]) {
            NHLRecordTouch(view, NO, [NSString stringWithFormat:@"Interactive control: %@", className]);
            return NO;
        }

        if (NHLClassNameContainsAny(className, blockedTokens)) {
            NHLRecordTouch(view, NO, [NSString stringWithFormat:@"Blocked view: %@", className]);
            return NO;
        }
    }

    NHLRecordTouch(view, NO, @"Touch hierarchy did not reach gesture host");
    return NO;
}

static NSString *NHLLockDevice(void) {
    Class managerClass = objc_getClass("SBLockScreenManager");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    id manager = nil;

    if (managerClass && [managerClass respondsToSelector:sharedSelector]) {
        manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, sharedSelector);
    }

    SEL modernLockSelector = NSSelectorFromString(@"lockUIFromSource:withOptions:");
    if (manager && [manager respondsToSelector:modernLockSelector]) {
        ((void (*)(id, SEL, NSInteger, id))objc_msgSend)(manager, modernLockSelector, 1, nil);
        return @"SBLockScreenManager modern selector";
    }

    SEL legacyLockSelector = NSSelectorFromString(@"lockUIFromSource:");
    if (manager && [manager respondsToSelector:legacyLockSelector]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(manager, legacyLockSelector, 1);
        return @"SBLockScreenManager legacy selector";
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
        return @"SBSLockDevice fallback";
    }

    return @"No compatible lock route found";
}

static void NHLRequestLock(NSString *source) {
    NSTimeInterval requestedAt = [NSDate date].timeIntervalSince1970;
    NHLWriteStatus(@{
        @"lastLockSource": source ?: @"Unknown",
        @"lastLockRequestedAt": @(requestedAt),
        @"lastLockRoute": @"Resolving"
    });

    NSString *route = NHLLockDevice();
    NHLWriteStatus(@{
        @"lastLockSource": source ?: @"Unknown",
        @"lastLockRoute": route ?: @"Unknown",
        @"lastLockCompletedAt": @([NSDate date].timeIntervalSince1970)
    });
}

static void NHLHandleTestLockNotification(CFNotificationCenterRef center,
                                           void *observer,
                                           CFStringRef name,
                                           const void *object,
                                           CFDictionaryRef userInfo) {
    NHLWriteStatus(@{
        @"testCommandReceived": @YES,
        @"testCommandReceivedAt": @([NSDate date].timeIntervalSince1970)
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        NHLRequestLock(@"Settings: Test Lock Now");
    });
}

@interface NHLGestureHandler : NSObject <UIGestureRecognizerDelegate>
@end

@implementation NHLGestureHandler

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    BOOL hasWindow = gestureRecognizer.view.window != nil;
    BOOL editing = NHLRootFolderIsEditing(gestureRecognizer.view);
    BOOL allowed = hasWindow && !editing;
    NHLWriteStatus(@{
        @"lastGestureBeginAllowed": @(allowed),
        @"lastGestureBeginReason": !hasWindow ? @"Gesture host has no window" : (editing ? @"Home Screen is editing" : @"Allowed"),
        @"lastGestureBeginAt": @([NSDate date].timeIntervalSince1970)
    });
    return allowed;
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
        NHLWriteStatus(@{
            @"lastGestureRecognized": @YES,
            @"lastGestureRecognizedAt": @([NSDate date].timeIntervalSince1970)
        });
        NHLRequestLock(@"Home Screen double-tap");
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

    NHLWriteStatus(@{
        @"gestureInstalled": @YES,
        @"gestureHostClass": NSStringFromClass(rootView.class),
        @"gestureInstalledAt": @([NSDate date].timeIntervalSince1970),
        @"gestureCountOnHost": @(rootView.gestureRecognizers.count)
    });
}

%hook SBRootFolderView

- (void)didMoveToWindow {
    %orig;
    NHLWriteStatus(@{
        @"rootFolderHookSeen": @YES,
        @"rootFolderDidMoveAt": @([NSDate date].timeIntervalSince1970)
    });
    NHLInstallGestureOnRootFolderView((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    NHLInstallGestureOnRootFolderView((UIView *)self);
}

%end

%ctor {
    @autoreleasepool {
        NHLStatusQueue = dispatch_queue_create("com.nextsolution.nexthomelock.status", DISPATCH_QUEUE_SERIAL);
        NHLWriteStatus(@{
            @"tweakLoaded": @YES,
            @"loadedVersion": NHLVersion,
            @"loadedAt": @([NSDate date].timeIntervalSince1970),
            @"springBoardPID": @([NSProcessInfo processInfo].processIdentifier),
            @"processName": [NSProcessInfo processInfo].processName ?: @"Unknown",
            @"rootFolderClassPresent": @(objc_getClass("SBRootFolderView") != Nil),
            @"gestureInstalled": @NO,
            @"testCommandReceived": @NO
        });

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            NHLHandleTestLockNotification,
            NHLTestLockNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
}
