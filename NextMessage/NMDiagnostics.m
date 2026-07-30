#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <sys/utsname.h>

static NSString * const NMDiagnosticPath = @"/var/mobile/Library/Preferences/com.nextsolution.nextmessage.diagnostic.txt";
static CFStringRef const NMCaptureNotification = CFSTR("com.nextsolution.nextmessage.capturediagnostic");
static CFStringRef const NMClearNotification = CFSTR("com.nextsolution.nextmessage.cleardiagnostic");
static dispatch_queue_t NMDiagnosticQueue;
static NSMutableSet<NSString *> *NMCapturedControllerClasses;
static BOOL NMRuntimeInventoryWritten = NO;

static NSString *NMDeviceMachine(void) {
    struct utsname systemInfo;
    if (uname(&systemInfo) != 0) return @"Unknown";
    return [NSString stringWithUTF8String:systemInfo.machine] ?: @"Unknown";
}

static NSString *NMIndent(NSUInteger level) {
    return [@"  " stringByPaddingToLength:level * 2 withString:@"  " startingAtIndex:0];
}

static UIWindow *NMActiveWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive &&
            scene.activationState != UISceneActivationStateForegroundInactive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static UIViewController *NMTopControllerFrom(UIViewController *controller) {
    if (!controller) return nil;
    if (controller.presentedViewController) return NMTopControllerFrom(controller.presentedViewController);
    if ([controller isKindOfClass:UINavigationController.class]) {
        return NMTopControllerFrom(((UINavigationController *)controller).visibleViewController);
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        return NMTopControllerFrom(((UITabBarController *)controller).selectedViewController);
    }
    return controller;
}

static NSString *NMSafeFrameDescription(CGRect frame) {
    if (CGRectIsNull(frame)) return @"null";
    if (CGRectIsInfinite(frame)) return @"infinite";
    return [NSString stringWithFormat:@"x=%.1f y=%.1f w=%.1f h=%.1f",
            frame.origin.x, frame.origin.y, frame.size.width, frame.size.height];
}

static void NMAppendControllerTree(NSMutableString *output, UIViewController *controller, NSUInteger depth, NSMutableSet *visited) {
    if (!controller || depth > 12 || [visited containsObject:controller]) return;
    [visited addObject:controller];

    NSString *className = NSStringFromClass(controller.class) ?: @"UnknownController";
    [output appendFormat:@"%@- %@ viewLoaded=%@ presented=%@ children=%lu\n",
     NMIndent(depth), className, controller.isViewLoaded ? @"YES" : @"NO",
     controller.presentedViewController ? NSStringFromClass(controller.presentedViewController.class) : @"none",
     (unsigned long)controller.childViewControllers.count];

    if ([controller isKindOfClass:UINavigationController.class]) {
        UINavigationController *navigation = (UINavigationController *)controller;
        [output appendFormat:@"%@  navigation stack: %@\n", NMIndent(depth),
         [navigation.viewControllers valueForKey:@"class"]];
    }

    for (UIViewController *child in controller.childViewControllers) {
        NMAppendControllerTree(output, child, depth + 1, visited);
    }
    if (controller.presentedViewController) {
        NMAppendControllerTree(output, controller.presentedViewController, depth + 1, visited);
    }
}

static void NMAppendViewTree(NSMutableString *output, UIView *view, NSUInteger depth, NSUInteger *count) {
    if (!view || depth > 16 || *count >= 1000) return;
    (*count)++;

    NSString *className = NSStringFromClass(view.class) ?: @"UnknownView";
    NSString *identifier = view.accessibilityIdentifier.length > 0 ? view.accessibilityIdentifier : @"-";
    if (identifier.length > 80) identifier = [identifier substringToIndex:80];

    [output appendFormat:@"%@- %@ frame={%@} hidden=%@ alpha=%.2f subviews=%lu identifier=%@\n",
     NMIndent(depth), className, NMSafeFrameDescription(view.frame),
     view.hidden ? @"YES" : @"NO", view.alpha,
     (unsigned long)view.subviews.count, identifier];

    for (UIView *subview in view.subviews) {
        NMAppendViewTree(output, subview, depth + 1, count);
        if (*count >= 1000) break;
    }
}

static BOOL NMClassNameIsRelevant(NSString *name) {
    if (name.length == 0) return NO;
    NSArray<NSString *> *prefixes = @[@"CK", @"IM", @"SMS", @"IDS", @"TU"];
    for (NSString *prefix in prefixes) if ([name hasPrefix:prefix]) return YES;

    NSArray<NSString *> *terms = @[
        @"Conversation", @"Transcript", @"Message", @"Balloon", @"Compose",
        @"Entry", @"Pinned", @"Search", @"Chat", @"Contact", @"Collection"
    ];
    for (NSString *term in terms) if ([name localizedCaseInsensitiveContainsString:term]) return YES;
    return NO;
}

static NSArray<NSString *> *NMRelevantRuntimeClasses(void) {
    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) return @[];

    Class *classes = (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
    classCount = objc_getClassList(classes, classCount);
    NSMutableArray<NSString *> *names = [NSMutableArray array];

    for (int index = 0; index < classCount; index++) {
        const char *rawName = class_getName(classes[index]);
        if (!rawName) continue;
        NSString *name = [NSString stringWithUTF8String:rawName];
        if (NMClassNameIsRelevant(name)) [names addObject:name];
    }
    free(classes);

    [names sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    if (names.count > 1600) return [names subarrayWithRange:NSMakeRange(0, 1600)];
    return names;
}

static void NMAppendMethodsForClass(NSMutableString *output, Class cls) {
    if (!cls) return;
    NSString *className = NSStringFromClass(cls) ?: @"Unknown";
    [output appendFormat:@"\n[%@ instance selectors]\n", className];

    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    NSMutableArray<NSString *> *selectors = [NSMutableArray array];
    for (unsigned int index = 0; index < methodCount; index++) {
        SEL selector = method_getName(methods[index]);
        if (selector) [selectors addObject:NSStringFromSelector(selector)];
    }
    free(methods);
    [selectors sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    NSUInteger limit = MIN(selectors.count, 240);
    for (NSUInteger index = 0; index < limit; index++) {
        [output appendFormat:@"  %@\n", selectors[index]];
    }
    if (selectors.count > limit) {
        [output appendFormat:@"  ... %lu more selectors omitted\n", (unsigned long)(selectors.count - limit)];
    }
}

static NSString *NMRuntimeInventory(void) {
    NSMutableString *output = [NSMutableString stringWithString:@"\n=== RELEVANT RUNTIME CLASSES ===\n"];
    NSArray<NSString *> *classes = NMRelevantRuntimeClasses();
    [output appendFormat:@"Relevant class count: %lu\n", (unsigned long)classes.count];
    for (NSString *name in classes) [output appendFormat:@"%@\n", name];
    return output;
}

static NSString *NMDiagnosticEntry(UIViewController *triggerController, BOOL manual) {
    UIWindow *window = NMActiveWindow();
    UIViewController *root = window.rootViewController;
    UIViewController *top = NMTopControllerFrom(root);
    UIViewController *subject = triggerController ?: top ?: root;

    NSMutableString *output = [NSMutableString string];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterLongStyle;

    [output appendString:@"\n\n============================================================\n"];
    [output appendFormat:@"NEXT MESSAGE DIAGNOSTIC v0.2.1 (%@)\n", manual ? @"MANUAL" : @"AUTOMATIC"];
    [output appendFormat:@"Captured: %@\n", [formatter stringFromDate:NSDate.date]];
    [output appendFormat:@"Device: %@\n", NMDeviceMachine()];
    [output appendFormat:@"iOS: %@\n", UIDevice.currentDevice.systemVersion];
    [output appendFormat:@"Process: %@ (%@)\n", NSProcessInfo.processInfo.processName, NSBundle.mainBundle.bundleIdentifier];
    [output appendFormat:@"Application state: %ld\n", (long)UIApplication.sharedApplication.applicationState];
    [output appendFormat:@"Window: %@ frame={%@}\n", NSStringFromClass(window.class), NMSafeFrameDescription(window.frame)];
    [output appendFormat:@"Trigger controller: %@\n", NSStringFromClass(subject.class) ?: @"none"];
    [output appendFormat:@"Top controller: %@\n", NSStringFromClass(top.class) ?: @"none"];
    [output appendString:@"Privacy: message text, contact names, phone numbers and participant data are not collected.\n"];

    [output appendString:@"\n=== CONTROLLER HIERARCHY ===\n"];
    NSMutableSet *visited = [NSMutableSet set];
    NMAppendControllerTree(output, root, 0, visited);

    [output appendString:@"\n=== ACTIVE VIEW HIERARCHY ===\n"];
    NSUInteger viewCount = 0;
    NMAppendViewTree(output, subject.view ?: window, 0, &viewCount);
    [output appendFormat:@"Captured view count: %lu\n", (unsigned long)viewCount];

    NSMutableOrderedSet<Class> *methodClasses = [NSMutableOrderedSet orderedSet];
    if (subject.class) [methodClasses addObject:subject.class];
    if (top.class) [methodClasses addObject:top.class];
    if (root.class) [methodClasses addObject:root.class];
    for (UIViewController *child in subject.childViewControllers) if (child.class) [methodClasses addObject:child.class];

    [output appendString:@"\n=== ACTIVE CONTROLLER SELECTORS ===\n"];
    for (Class cls in methodClasses) NMAppendMethodsForClass(output, cls);

    if (!NMRuntimeInventoryWritten) {
        [output appendString:NMRuntimeInventory()];
        NMRuntimeInventoryWritten = YES;
    }
    return output;
}

static void NMWriteDiagnosticEntry(NSString *entry, BOOL reset) {
    if (entry.length == 0) return;
    NSFileManager *manager = NSFileManager.defaultManager;
    NSString *directory = NMDiagnosticPath.stringByDeletingLastPathComponent;
    [manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];

    if (reset || ![manager fileExistsAtPath:NMDiagnosticPath]) {
        [entry writeToFile:NMDiagnosticPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }

    NSDictionary *attributes = [manager attributesOfItemAtPath:NMDiagnosticPath error:nil];
    if ([attributes fileSize] > 1024 * 1024) {
        [entry writeToFile:NMDiagnosticPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:NMDiagnosticPath];
    [handle seekToEndOfFile];
    [handle writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

static void NMCaptureDiagnostic(UIViewController *controller, BOOL manual) {
    if (!controller && !NMActiveWindow()) return;
    dispatch_async(NMDiagnosticQueue, ^{
        NSString *entry = NMDiagnosticEntry(controller, manual);
        NMWriteDiagnosticEntry(entry, NO);
    });
}

static BOOL NMShouldCaptureController(UIViewController *controller) {
    NSString *name = NSStringFromClass(controller.class);
    if (name.length == 0) return NO;
    if ([name hasPrefix:@"CK"] || [name hasPrefix:@"SMS"] || [name hasPrefix:@"IM"]) return YES;
    NSArray<NSString *> *terms = @[@"Conversation", @"Transcript", @"Message", @"Chat"];
    for (NSString *term in terms) if ([name localizedCaseInsensitiveContainsString:term]) return YES;
    return NO;
}

static void NMShowManualCaptureConfirmation(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        UIViewController *top = NMTopControllerFrom(NMActiveWindow().rootViewController);
        if (!top || top.presentedViewController) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Next Message Diagnostic"
                                                                       message:@"The privacy-safe runtime report was saved. Open Settings → Next Message → Copy Last Report and paste it into the chat."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}

static void NMCaptureNotificationCallback(__unused CFNotificationCenterRef center,
                                          __unused void *observer,
                                          __unused CFStringRef name,
                                          __unused const void *object,
                                          __unused CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = NMTopControllerFrom(NMActiveWindow().rootViewController);
        NMCaptureDiagnostic(top, YES);
        NMShowManualCaptureConfirmation();
    });
}

static void NMClearNotificationCallback(__unused CFNotificationCenterRef center,
                                        __unused void *observer,
                                        __unused CFStringRef name,
                                        __unused const void *object,
                                        __unused CFDictionaryRef userInfo) {
    dispatch_async(NMDiagnosticQueue, ^{
        [NSFileManager.defaultManager removeItemAtPath:NMDiagnosticPath error:nil];
        NMRuntimeInventoryWritten = NO;
        [NMCapturedControllerClasses removeAllObjects];
    });
}

@interface UIViewController (NMDiagnostics)
- (void)nm_diagnostic_viewDidAppear:(BOOL)animated;
@end

@implementation UIViewController (NMDiagnostics)

- (void)nm_diagnostic_viewDidAppear:(BOOL)animated {
    [self nm_diagnostic_viewDidAppear:animated];
    if (!NMShouldCaptureController(self)) return;

    NSString *className = NSStringFromClass(self.class);
    @synchronized (NMCapturedControllerClasses) {
        if ([NMCapturedControllerClasses containsObject:className]) return;
        [NMCapturedControllerClasses addObject:className];
    }

    __weak UIViewController *weakController = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *controller = weakController;
        if (controller.view.window) NMCaptureDiagnostic(controller, NO);
    });
}

@end

__attribute__((constructor)) static void NMInstallDiagnostics(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.MobileSMS"]) return;

        NMDiagnosticQueue = dispatch_queue_create("com.nextsolution.nextmessage.diagnostics", DISPATCH_QUEUE_SERIAL);
        NMCapturedControllerClasses = [NSMutableSet set];

        Method original = class_getInstanceMethod(UIViewController.class, @selector(viewDidAppear:));
        Method replacement = class_getInstanceMethod(UIViewController.class, @selector(nm_diagnostic_viewDidAppear:));
        if (original && replacement) method_exchangeImplementations(original, replacement);

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        NMCaptureNotificationCallback, NMCaptureNotification,
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        NMClearNotificationCallback, NMClearNotification,
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
