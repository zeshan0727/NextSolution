#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Contacts/Contacts.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>

static NSString * const PADiagnosticsVersion = @"0.5.1-diagnostic";
static NSString * const PAPreferencesDomain = @"com.zeshan.phoneaura";
static NSString * const PAStatusPath = @"/var/mobile/Library/Preferences/com.zeshan.phoneaura.diagnostics.plist";
static NSString * const PALogDirectory = @"/var/mobile/Library/Logs/PhoneAura";
static NSString * const PALogPath = @"/var/mobile/Library/Logs/PhoneAura/PhoneAuraDiagnostics.log";

static NSUncaughtExceptionHandler *PAPreviousExceptionHandler = NULL;
static dispatch_source_t PAHeartbeatTimer = nil;

static NSString *PATimestamp(void) {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    });
    return [formatter stringFromDate:[NSDate date]];
}

static void PAEnsureLogDirectory(void) {
    [[NSFileManager defaultManager] createDirectoryAtPath:PALogDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

static void PAAppendLine(NSString *line) {
    if (!line.length) return;
    @synchronized (NSFileManager.defaultManager) {
        PAEnsureLogDirectory();
        NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        if (![[NSFileManager defaultManager] fileExistsAtPath:PALogPath]) {
            [data writeToFile:PALogPath atomically:YES];
            return;
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:PALogPath];
        if (!handle) return;
        @try {
            [handle seekToEndOfFile];
            [handle writeData:data];
        } @catch (__unused NSException *exception) {
        }
        [handle closeFile];
    }
}

static void PALog(NSString *level, NSString *area, NSString *format, ...) NS_FORMAT_FUNCTION(3,4);
static void PALog(NSString *level, NSString *area, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[%@] [%@] [%@] %@",
                      PATimestamp(), level ?: @"INFO", area ?: @"GENERAL", message ?: @""];
    PAAppendLine(line);
}

static NSMutableDictionary *PAReadStatusMutable(void) {
    NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:PAStatusPath];
    return existing ? [existing mutableCopy] : [NSMutableDictionary dictionary];
}

static void PAUpdateStatus(NSDictionary *changes) {
    @synchronized (PAStatusPath) {
        NSMutableDictionary *status = PAReadStatusMutable();
        [status addEntriesFromDictionary:changes ?: @{}];
        status[@"diagnosticVersion"] = PADiagnosticsVersion;
        status[@"updatedEpoch"] = @([[NSDate date] timeIntervalSince1970]);
        [status writeToFile:PAStatusPath atomically:YES];
    }
}

static id PACopyPreference(NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)PAPreferencesDomain);
    return CFBridgingRelease(value);
}

static BOOL PABoolPreference(NSString *key, BOOL fallback) {
    id value = PACopyPreference(key);
    return value ? [value boolValue] : fallback;
}

static BOOL PAImageLoadedContaining(NSString *needle, NSString **matchedPath) {
    uint32_t count = _dyld_image_count();
    for (uint32_t index = 0; index < count; index++) {
        const char *name = _dyld_get_image_name(index);
        if (!name) continue;
        NSString *path = [NSString stringWithUTF8String:name];
        if ([path rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) {
            if (matchedPath) *matchedPath = path;
            return YES;
        }
    }
    return NO;
}

static NSString *PAEnvironment(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:@"/var/jb/Library/MobileSubstrate/DynamicLibraries/PhoneAura.dylib"]) return @"Rootless";
    if ([fm fileExistsAtPath:@"/Library/MobileSubstrate/DynamicLibraries/PhoneAura.dylib"]) return @"RootHide/Rootful";
    return @"Unknown";
}

static NSArray<UIWindow *> *PAWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    UIApplication *app = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows ?: @[]];
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (!windows.count && app.windows.count) [windows addObjectsFromArray:app.windows];
#pragma clang diagnostic pop
    return windows;
}

static UIViewController *PAVisibleController(UIViewController *controller) {
    if (!controller) return nil;
    if (controller.presentedViewController) return PAVisibleController(controller.presentedViewController);
    if ([controller isKindOfClass:UINavigationController.class]) {
        return PAVisibleController(((UINavigationController *)controller).visibleViewController);
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        return PAVisibleController(((UITabBarController *)controller).selectedViewController);
    }
    return controller;
}

static UITabBarController *PAFindTabController(UIViewController *controller) {
    if (!controller) return nil;
    if ([controller isKindOfClass:UITabBarController.class]) return (UITabBarController *)controller;
    for (UIViewController *child in controller.childViewControllers) {
        UITabBarController *found = PAFindTabController(child);
        if (found) return found;
    }
    if (controller.presentedViewController) return PAFindTabController(controller.presentedViewController);
    return nil;
}

static UIViewController *PARootController(void) {
    for (UIWindow *window in PAWindows()) {
        if (window.isHidden || window.alpha <= 0.01 || !window.rootViewController) continue;
        if (window.isKeyWindow) return window.rootViewController;
    }
    for (UIWindow *window in PAWindows()) {
        if (window.rootViewController) return window.rootViewController;
    }
    return nil;
}

static BOOL PAControllerTreeContainsClass(UIViewController *controller, NSArray<NSString *> *names) {
    if (!controller) return NO;
    NSString *current = NSStringFromClass(controller.class);
    if ([names containsObject:current]) return YES;
    for (UIViewController *child in controller.childViewControllers) {
        if (PAControllerTreeContainsClass(child, names)) return YES;
    }
    if (controller.presentedViewController && PAControllerTreeContainsClass(controller.presentedViewController, names)) return YES;
    return NO;
}

static NSDictionary *PAClassReport(NSArray<NSString *> *classNames) {
    NSMutableDictionary *report = [NSMutableDictionary dictionary];
    for (NSString *name in classNames) {
        Class cls = NSClassFromString(name);
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"loaded"] = @(cls != Nil);
        if (cls) {
            entry[@"viewDidLoad"] = @(class_getInstanceMethod(cls, @selector(viewDidLoad)) != NULL);
            entry[@"viewDidAppear"] = @(class_getInstanceMethod(cls, @selector(viewDidAppear:)) != NULL);
            entry[@"superclass"] = NSStringFromClass(class_getSuperclass(cls)) ?: @"";
        }
        report[name] = entry;
    }
    return report;
}

static NSDictionary *PAFeatureReport(NSString *name, NSString *preferenceKey, NSArray<NSString *> *classes) {
    UIViewController *root = PARootController();
    BOOL classLoaded = NO;
    NSMutableArray *loaded = [NSMutableArray array];
    for (NSString *className in classes) {
        if (NSClassFromString(className)) {
            classLoaded = YES;
            [loaded addObject:className];
        }
    }
    BOOL active = PAControllerTreeContainsClass(root, classes);
    NSMutableDictionary *report = [NSMutableDictionary dictionary];
    report[@"name"] = name;
    report[@"preference"] = preferenceKey.length ? @(PABoolPreference(preferenceKey, YES)) : [NSNull null];
    report[@"classLoaded"] = @(classLoaded);
    report[@"activeInControllerTree"] = @(active);
    report[@"loadedClasses"] = loaded;
    return report;
}

static NSDictionary *PAAllFeatureReports(void) {
    return @{
        @"favorites": PAFeatureReport(@"Favorites", @"fullFavorites", @[@"PAFavoritesDashboardV46", @"PAFavoritesDashboardView", @"PAFavoriteCardV46"]),
        @"recents": PAFeatureReport(@"Recents", @"fullRecents", @[@"PARecentsDashboardView", @"PARecentCellV47", @"PARecentDetailOverlayV47"]),
        @"contacts": PAFeatureReport(@"Contacts", @"fullContacts", @[@"PAContactsDashboardV46", @"PAContactsDashboardView", @"PAContactDirectoryV46", @"PAContactRowV46"]),
        @"keypad": PAFeatureReport(@"Keypad", @"fullKeypad", @[@"PAStudioKeypadView", @"PAKeypadEnhancementsV49", @"PAKeypadStableSuggestionsV411", @"PAKeypadHeaderBrandV414", @"PAKeypadContactMenuV410"])
    };
}

static void PALogControllerTree(UIViewController *controller, NSUInteger depth) {
    if (!controller || depth > 10) return;
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    NSString *title = controller.title ?: controller.tabBarItem.title ?: @"";
    PALog(@"DEBUG", @"UI", @"%@%@ title='%@' children=%lu presented=%@",
          indent, NSStringFromClass(controller.class), title,
          (unsigned long)controller.childViewControllers.count,
          controller.presentedViewController ? NSStringFromClass(controller.presentedViewController.class) : @"none");
    for (UIViewController *child in controller.childViewControllers) PALogControllerTree(child, depth + 1);
    if (controller.presentedViewController) PALogControllerTree(controller.presentedViewController, depth + 1);
}

static void PASnapshotUI(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *root = PARootController();
        UIViewController *visible = PAVisibleController(root);
        UITabBarController *tabs = PAFindTabController(root);
        PALog(@"INFO", @"UI", @"root=%@ visible=%@ tabController=%@ selectedIndex=%ld",
              root ? NSStringFromClass(root.class) : @"nil",
              visible ? NSStringFromClass(visible.class) : @"nil",
              tabs ? NSStringFromClass(tabs.class) : @"nil",
              tabs ? (long)tabs.selectedIndex : -1L);
        if (tabs) {
            [tabs.viewControllers enumerateObjectsUsingBlock:^(UIViewController *vc, NSUInteger idx, BOOL *stop) {
                NSString *title = vc.tabBarItem.title ?: vc.title ?: @"";
                PALog(@"INFO", @"TABS", @"index=%lu class=%@ title='%@' selected=%@",
                      (unsigned long)idx, NSStringFromClass(vc.class), title,
                      idx == tabs.selectedIndex ? @"YES" : @"NO");
            }];
        }
        PALogControllerTree(root, 0);
        PAUpdateStatus(@{
            @"topController": visible ? NSStringFromClass(visible.class) : @"nil",
            @"selectedTabIndex": tabs ? @(tabs.selectedIndex) : @(-1),
            @"selectedTabTitle": tabs.selectedViewController.tabBarItem.title ?: @"",
            @"featureStates": PAAllFeatureReports()
        });
    });
}

static void PAContactDiagnostics(void) {
    CNAuthorizationStatus auth = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
    NSString *authName = @"Unknown";
    switch (auth) {
        case CNAuthorizationStatusNotDetermined: authName = @"NotDetermined"; break;
        case CNAuthorizationStatusRestricted: authName = @"Restricted"; break;
        case CNAuthorizationStatusDenied: authName = @"Denied"; break;
        case CNAuthorizationStatusAuthorized: authName = @"Authorized"; break;
    }
    CNContactStore *store = [CNContactStore new];
    NSError *error = nil;
    NSArray<CNContainer *> *containers = [store containersMatchingPredicate:nil error:&error];
    PALog(error ? @"ERROR" : @"INFO", @"CONTACTS", @"authorization=%@ containers=%lu error=%@",
          authName, (unsigned long)containers.count, error.localizedDescription ?: @"none");
    for (CNContainer *container in containers) {
        NSError *groupError = nil;
        NSArray<CNGroup *> *groups = [store groupsMatchingPredicate:[CNGroup predicateForGroupsInContainerWithIdentifier:container.identifier]
                                                               error:&groupError];
        PALog(groupError ? @"WARNING" : @"INFO", @"CONTACTS", @"container='%@' id=%@ type=%ld groups=%lu error=%@",
              container.name ?: @"", container.identifier ?: @"", (long)container.type,
              (unsigned long)groups.count, groupError.localizedDescription ?: @"none");
    }
    PAUpdateStatus(@{@"contactsAuthorization": authName,
                     @"contactsContainers": @(containers.count),
                     @"contactsLastError": error.localizedDescription ?: @""});
}

static void PALogFeature(NSString *featureKey) {
    NSDictionary *features = PAAllFeatureReports();
    NSDictionary *report = features[featureKey];
    if (!report) {
        PALog(@"WARNING", @"FEATURE", @"Unknown feature command: %@", featureKey);
        return;
    }
    PALog(@"INFO", [featureKey uppercaseString], @"preference=%@ classLoaded=%@ active=%@ loadedClasses=%@",
          report[@"preference"], report[@"classLoaded"], report[@"activeInControllerTree"], report[@"loadedClasses"]);
    NSArray *classes = nil;
    if ([featureKey isEqualToString:@"favorites"]) classes = @[@"PAFavoritesDashboardV46", @"PAFavoritesDashboardView", @"PAFavoriteCardV46"];
    if ([featureKey isEqualToString:@"recents"]) classes = @[@"PARecentsDashboardView", @"PARecentCellV47", @"PARecentDetailOverlayV47"];
    if ([featureKey isEqualToString:@"contacts"]) classes = @[@"PAContactsDashboardV46", @"PAContactsDashboardView", @"PAContactDirectoryV46", @"PAContactRowV46"];
    if ([featureKey isEqualToString:@"keypad"]) classes = @[@"PAStudioKeypadView", @"PAKeypadEnhancementsV49", @"PAKeypadStableSuggestionsV411", @"PAKeypadHeaderBrandV414", @"PAKeypadContactMenuV410"];
    if (classes) PALog(@"DEBUG", [featureKey uppercaseString], @"classReport=%@", PAClassReport(classes));
    if ([featureKey isEqualToString:@"contacts"]) PAContactDiagnostics();
    PASnapshotUI();
}

static void PABaseRuntimeDiagnostics(void) {
    NSString *basePath = nil;
    BOOL baseLoaded = PAImageLoadedContaining(@"PhoneAura.dylib", &basePath);
    NSString *nativePath = nil;
    BOOL nativeLoaded = PAImageLoadedContaining(@"PhoneAuraNativeFeatures.dylib", &nativePath);
    NSString *diagPath = nil;
    BOOL diagLoaded = PAImageLoadedContaining(@"PhoneAuraDiagnostics.dylib", &diagPath);

    NSDictionary *prefs = @{
        @"enabled": @(PABoolPreference(@"enabled", YES)),
        @"fullFavorites": @(PABoolPreference(@"fullFavorites", YES)),
        @"fullRecents": @(PABoolPreference(@"fullRecents", YES)),
        @"fullContacts": @(PABoolPreference(@"fullContacts", YES)),
        @"fullKeypad": @(PABoolPreference(@"fullKeypad", YES)),
        @"haptics": @(PABoolPreference(@"haptics", YES)),
        @"animations": @(PABoolPreference(@"animations", YES))
    };

    PALog(baseLoaded ? @"SUCCESS" : @"ERROR", @"RUNTIME", @"PhoneAura.dylib loaded=%@ path=%@",
          baseLoaded ? @"YES" : @"NO", basePath ?: @"not found");
    PALog(nativeLoaded ? @"WARNING" : @"SUCCESS", @"RUNTIME", @"old PhoneAuraNativeFeatures loaded=%@ path=%@",
          nativeLoaded ? @"YES" : @"NO", nativePath ?: @"not loaded");
    PALog(diagLoaded ? @"SUCCESS" : @"ERROR", @"RUNTIME", @"PhoneAuraDiagnostics loaded=%@ path=%@",
          diagLoaded ? @"YES" : @"NO", diagPath ?: @"not found");
    PALog(@"INFO", @"PREFERENCES", @"%@", prefs);

    PAUpdateStatus(@{
        @"process": NSProcessInfo.processInfo.processName ?: @"",
        @"pid": @(NSProcessInfo.processInfo.processIdentifier),
        @"bundle": NSBundle.mainBundle.bundleIdentifier ?: @"",
        @"environment": PAEnvironment(),
        @"baseRuntimeLoaded": @(baseLoaded),
        @"baseRuntimePath": basePath ?: @"",
        @"oldNativeFeatureLoaded": @(nativeLoaded),
        @"oldNativeFeaturePath": nativePath ?: @"",
        @"diagnosticsLoaded": @(diagLoaded),
        @"diagnosticsPath": diagPath ?: @"",
        @"preferences": prefs,
        @"featureStates": PAAllFeatureReports()
    });
}

static void PAFullDiagnosis(NSString *reason) {
    PALog(@"INFO", @"DIAG", @"===== FULL DIAGNOSIS START reason=%@ =====", reason ?: @"manual");
    PABaseRuntimeDiagnostics();
    PAContactDiagnostics();
    PASnapshotUI();
    PALog(@"INFO", @"DIAG", @"===== FULL DIAGNOSIS REQUESTED =====");
    PAUpdateStatus(@{@"lastCommand": @"Full Diagnosis", @"lastResult": @"Completed request"});
}

static void PAClearLog(void) {
    [[NSFileManager defaultManager] removeItemAtPath:PALogPath error:nil];
    PALog(@"SUCCESS", @"CONSOLE", @"Diagnostic log cleared.");
    PAUpdateStatus(@{@"lastCommand": @"Clear Log", @"lastResult": @"Log cleared"});
}

static void PAHandleCommand(NSString *name) {
    if ([name hasSuffix:@".full"]) {
        PAFullDiagnosis(@"console");
    } else if ([name hasSuffix:@".snapshot"]) {
        PALog(@"INFO", @"CONSOLE", @"Snapshot command received.");
        PASnapshotUI();
        PAUpdateStatus(@{@"lastCommand": @"Snapshot UI", @"lastResult": @"Snapshot requested"});
    } else if ([name hasSuffix:@".favorites"]) {
        PAUpdateStatus(@{@"lastCommand": @"Test Favorites"});
        PALogFeature(@"favorites");
    } else if ([name hasSuffix:@".recents"]) {
        PAUpdateStatus(@{@"lastCommand": @"Test Recents"});
        PALogFeature(@"recents");
    } else if ([name hasSuffix:@".contacts"]) {
        PAUpdateStatus(@{@"lastCommand": @"Test Contacts"});
        PALogFeature(@"contacts");
    } else if ([name hasSuffix:@".keypad"]) {
        PAUpdateStatus(@{@"lastCommand": @"Test Keypad"});
        PALogFeature(@"keypad");
    } else if ([name hasSuffix:@".voicemail"]) {
        PALog(@"INFO", @"VOICEMAIL", @"PhoneAura does not replace Voicemail in the 0.4.16 runtime. Capturing current tab/controller state for comparison.");
        PASnapshotUI();
        PAUpdateStatus(@{@"lastCommand": @"Test Voicemail", @"lastResult": @"System tab snapshot captured"});
    } else if ([name hasSuffix:@".clear"]) {
        PAClearLog();
    }
}

static void PACommandCallback(CFNotificationCenterRef center,
                              void *observer,
                              CFStringRef name,
                              const void *object,
                              CFDictionaryRef userInfo) {
    NSString *notificationName = (__bridge NSString *)name;
    dispatch_async(dispatch_get_main_queue(), ^{
        PAHandleCommand(notificationName);
    });
}

static void PARegisterCommand(NSString *name) {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    PACommandCallback,
                                    (__bridge CFStringRef)name,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

static void PAExceptionHandler(NSException *exception) {
    PALog(@"ERROR", @"EXCEPTION", @"name=%@ reason=%@ callStack=%@",
          exception.name ?: @"", exception.reason ?: @"", exception.callStackSymbols ?: @[]);
    PAUpdateStatus(@{@"lastExceptionName": exception.name ?: @"",
                     @"lastExceptionReason": exception.reason ?: @"",
                     @"lastExceptionEpoch": @([[NSDate date] timeIntervalSince1970])});
    if (PAPreviousExceptionHandler && PAPreviousExceptionHandler != PAExceptionHandler) {
        PAPreviousExceptionHandler(exception);
    }
}

static void PAStartHeartbeat(void) {
    if (PAHeartbeatTimer) return;
    PAHeartbeatTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(PAHeartbeatTimer,
                              dispatch_time(DISPATCH_TIME_NOW, 0),
                              (uint64_t)(5.0 * NSEC_PER_SEC),
                              (uint64_t)(0.5 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(PAHeartbeatTimer, ^{
        UIViewController *visible = PAVisibleController(PARootController());
        PAUpdateStatus(@{
            @"heartbeatEpoch": @([[NSDate date] timeIntervalSince1970]),
            @"heartbeat": PATimestamp(),
            @"topController": visible ? NSStringFromClass(visible.class) : @"nil",
            @"pid": @(NSProcessInfo.processInfo.processIdentifier)
        });
    });
    dispatch_resume(PAHeartbeatTimer);
}

static void PAInitializeDiagnostics(void) {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
    PALog(@"INFO", @"BOOT", @"PhoneAura diagnostics constructor version=%@ process=%@ pid=%d bundle=%@ environment=%@",
          PADiagnosticsVersion, NSProcessInfo.processInfo.processName,
          NSProcessInfo.processInfo.processIdentifier, bundle, PAEnvironment());

    PAPreviousExceptionHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(&PAExceptionHandler);

    NSArray<NSString *> *commands = @[
        @"com.zeshan.phoneaura.diag.command.full",
        @"com.zeshan.phoneaura.diag.command.snapshot",
        @"com.zeshan.phoneaura.diag.command.favorites",
        @"com.zeshan.phoneaura.diag.command.recents",
        @"com.zeshan.phoneaura.diag.command.contacts",
        @"com.zeshan.phoneaura.diag.command.keypad",
        @"com.zeshan.phoneaura.diag.command.voicemail",
        @"com.zeshan.phoneaura.diag.command.clear"
    ];
    for (NSString *command in commands) PARegisterCommand(command);

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        PALog(@"INFO", @"LIFECYCLE", @"MobilePhone became active.");
        PABaseRuntimeDiagnostics();
        PASnapshotUI();
    }];
    [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        PALog(@"INFO", @"LIFECYCLE", @"MobilePhone entered background.");
    }];
    [center addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        PALog(@"WARNING", @"MEMORY", @"MobilePhone received a memory warning.");
    }];
    [center addObserverForName:CNContactStoreDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        PALog(@"INFO", @"CONTACTS", @"CNContactStoreDidChangeNotification received.");
    }];

    PAStartHeartbeat();
    PAUpdateStatus(@{
        @"diagnosticVersion": PADiagnosticsVersion,
        @"startedEpoch": @([[NSDate date] timeIntervalSince1970]),
        @"started": PATimestamp(),
        @"environment": PAEnvironment(),
        @"process": NSProcessInfo.processInfo.processName ?: @"",
        @"pid": @(NSProcessInfo.processInfo.processIdentifier),
        @"bundle": bundle
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PABaseRuntimeDiagnostics();
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PAFullDiagnosis(@"startup");
    });
}

__attribute__((constructor)) static void PhoneAuraDiagnosticsInitialize(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            PAInitializeDiagnostics();
        });
    }
}
