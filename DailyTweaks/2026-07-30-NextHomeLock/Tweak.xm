#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (void)lockUIFromSource:(NSInteger)source withOptions:(id)options;
@end

@interface SBIconController : UIViewController
@end

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

static BOOL NHLTouchIsOnSafeHomeBackground(UIView *view) {
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
            @"Platter"
        ];
    });

    BOOL foundHomeSurface = NO;
    for (UIView *current = view; current != nil; current = current.superview) {
        if ([current isKindOfClass:UIControl.class]) {
            return NO;
        }

        NSString *className = NSStringFromClass(current.class);
        if (NHLClassNameContainsAny(className, blockedTokens)) {
            return NO;
        }

        if ([className containsString:@"SBIconListView"] ||
            [className containsString:@"SBRootFolderView"] ||
            [className containsString:@"SBIconScrollView"]) {
            foundHomeSurface = YES;
        }
    }

    return foundHomeSurface;
}

@interface NHLGestureHandler : NSObject <UIGestureRecognizerDelegate>
@end

@implementation NHLGestureHandler

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return NHLTouchIsOnSafeHomeBackground(touch.view);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateRecognized) {
        return;
    }

    SBLockScreenManager *manager = [%c(SBLockScreenManager) sharedInstance];
    if ([manager respondsToSelector:@selector(lockUIFromSource:withOptions:)]) {
        [manager lockUIFromSource:1 withOptions:nil];
    }
}

@end

%hook SBIconController

- (void)viewDidLoad {
    %orig;

    UIView *rootView = self.view;
    if (!rootView || objc_getAssociatedObject(rootView, NHLGestureKey)) {
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

%end
