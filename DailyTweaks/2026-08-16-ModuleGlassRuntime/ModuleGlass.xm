#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

static NSString * const MGPrefsDomain = @"com.nextsolution.unlockvibrate";
static NSString * const MGPrefsChanged = @"com.nextsolution.unlockvibrate/preferences.changed";
static NSString * const MGNextLogChanged = @"com.nextsolution.nextlog/control.changed";
static NSString * const MGBackgroundDirectory = @"/var/mobile/Library/Preferences/NextSolutionTweaks/CCBackgrounds";
static NSString * const MGLogDirectory = @"/var/mobile/Library/Logs/NextSolution";
static NSString * const MGLogPath = @"/var/mobile/Library/Logs/NextSolution/module-glass.log";
static NSString * const MGNextLogControlPath = @"/var/mobile/Library/Preferences/com.nextsolution.nextlog.plist";
static NSInteger const MGImageTag = 0x4D474C53;

static NSHashTable *MGControllers;
static const void *MGOriginalHiddenKey = &MGOriginalHiddenKey;
static const void *MGOriginalAlphaKey = &MGOriginalAlphaKey;
static const void *MGBackgroundTouchedKey = &MGBackgroundTouchedKey;
static const void *MGLastSignatureKey = &MGLastSignatureKey;

static id MGSafeValue(id object, NSString *key) {
    if (!object || !key.length) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static NSString *MGStringValue(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value respondsToSelector:@selector(stringValue)]) {
        @try { return [value stringValue]; } @catch (__unused NSException *e) {}
    }
    if (value) return [value description];
    return nil;
}

static id MGPreference(NSString *key, id fallback) {
    if (!key.length) return fallback;
    CFPreferencesAppSynchronize((__bridge CFStringRef)MGPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)MGPrefsDomain);
    if (!value) return fallback;
    return CFBridgingRelease(value);
}

static BOOL MGPreferenceBool(NSString *key, BOOL fallback) {
    id value = MGPreference(key, @(fallback));
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

static CGFloat MGPreferenceFloat(NSString *key, CGFloat fallback) {
    id value = MGPreference(key, @(fallback));
    return [value respondsToSelector:@selector(doubleValue)] ? (CGFloat)[value doubleValue] : fallback;
}

static NSString *MGNormalized(NSString *value) {
    if (!value.length) return @"";
    NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
    NSMutableString *result = [NSMutableString string];
    NSString *lower = value.lowercaseString;
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        if ([allowed characterIsMember:c]) [result appendFormat:@"%C", c];
    }
    return result;
}

static BOOL MGDiagnosticEnabled(void) {
    NSDictionary *control = [NSDictionary dictionaryWithContentsOfFile:MGNextLogControlPath];
    if (![control isKindOfClass:NSDictionary.class] || ![control[@"enabled"] boolValue]) return NO;
    NSString *active = MGNormalized(MGStringValue(control[@"activeTweak"]));
    if (!active.length) active = MGNormalized(MGStringValue(control[@"displayName"]));
    return [active containsString:@"moduleglass"] || [active containsString:@"ccmodulebackground"];
}

static void MGEnsureLogDirectory(void) {
    [NSFileManager.defaultManager createDirectoryAtPath:MGLogDirectory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
}

static void MGLog(BOOL force, NSString *format, ...) {
    if (!force && !MGDiagnosticEnabled()) return;
    if (!format.length) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    MGEnsureLogDirectory();

    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:MGLogPath error:nil];
    if ([attrs fileSize] > (2 * 1024 * 1024)) {
        NSString *previous = [MGLogDirectory stringByAppendingPathComponent:@"module-glass.previous.log"];
        [NSFileManager.defaultManager removeItemAtPath:previous error:nil];
        [NSFileManager.defaultManager moveItemAtPath:MGLogPath toPath:previous error:nil];
    }

    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], message];
    @synchronized (NSFileManager.class) {
        if (![NSFileManager.defaultManager fileExistsAtPath:MGLogPath]) {
            [line writeToFile:MGLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:MGLogPath];
            [handle seekToEndOfFile];
            [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        }
    }
}

static NSArray<NSString *> *MGCandidateStrings(id controller) {
    if (!controller) return @[];
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSArray<NSString *> *keys = @[
        @"moduleIdentifier", @"_moduleIdentifier", @"identifier", @"_identifier",
        @"module", @"_module", @"contentModule", @"_contentModule", @"moduleInstance", @"_moduleInstance"
    ];
    for (NSString *key in keys) {
        id value = MGSafeValue(controller, key);
        if (!value) continue;
        NSString *text = MGStringValue(value);
        if (text.length) [values addObject:text];
        if (![value isKindOfClass:NSString.class] && value != controller) {
            for (NSString *innerKey in @[@"moduleIdentifier", @"identifier", @"bundleIdentifier", @"displayName"]) {
                NSString *inner = MGStringValue(MGSafeValue(value, innerKey));
                if (inner.length) [values addObject:inner];
            }
            [values addObject:NSStringFromClass([value class]) ?: @""];
        }
    }
    [values addObject:NSStringFromClass([controller class]) ?: @""];
    id parent = MGSafeValue(controller, @"parentViewController");
    if (parent && parent != controller) {
        for (NSString *key in @[@"moduleIdentifier", @"identifier"]) {
            NSString *text = MGStringValue(MGSafeValue(parent, key));
            if (text.length) [values addObject:text];
        }
        [values addObject:NSStringFromClass([parent class]) ?: @""];
    }
    return values;
}

static BOOL MGContainsNormalized(NSString *value, NSString *needle) {
    if (!value.length || !needle.length) return NO;
    return [MGNormalized(value) containsString:needle];
}

static NSString *MGSlotForCandidates(NSArray<NSString *> *values) {
    if (!values.count) return nil;

    // Prefer exact iOS 16 identifiers/classes observed by Next Log. These checks
    // intentionally run before broad fallback matching so Volume never becomes
    // Now Playing and Display never falls into "other".
    for (NSString *raw in values) {
        NSString *n = MGNormalized(raw);
        if (!n.length) continue;

        if ([n containsString:@"comapplemediaremotecontrolcenteraudio"] ||
            [n containsString:@"mediacontrolsaudiomodule"]) return @"volume";
        if ([n containsString:@"comapplemediaremotecontrolcenternowplaying"] ||
            [n isEqualToString:@"mediacontrolsmodule"]) return @"media";
        if ([n containsString:@"comapplecontrolcenterdisplaymodule"] ||
            [n containsString:@"ccuidisplaymodule"]) return @"brightness";
        if ([n containsString:@"comapplereplaykitcontrolcenterscreencapture"] ||
            [n containsString:@"rpcontrolcentermodule"]) return @"screenrecording";
        if ([n containsString:@"comapplemediaremotecontrolcenterairplaymirroring"] ||
            [n containsString:@"mpavairplaymirroringmodule"]) return @"screenmirroring";
        if ([n containsString:@"comapplecontrolcenterconnectivitymodule"] ||
            [n containsString:@"ccuiconnectivitymodule"]) return @"connectivity";
        if ([n containsString:@"comapplecontrolcenterorientationlockmodule"] ||
            [n containsString:@"ccuiorientationlockmodule"]) return @"orientation";
        if ([n containsString:@"comapplecontrolcenterlowpowermodule"] ||
            [n containsString:@"ccuilowpowermodule"]) return @"lowpower";
        if ([n containsString:@"comapplefocusuimodule"] ||
            [n containsString:@"fccccontrolcentermodule"]) return @"focus";
        if ([n containsString:@"comapplecontrolcenterflashlightmodule"] ||
            [n containsString:@"ccuiflashlightmodule"]) return @"flashlight";
        if ([n containsString:@"comapplemobiletimercontrolcentertimer"] ||
            [n containsString:@"mtcctimermodule"]) return @"timer";
        if ([n containsString:@"comapplecontrolcentercalculatormodule"] ||
            [n containsString:@"calculator"]) return @"calculator";
        if ([n containsString:@"comapplecontrolcentercameramodule"] ||
            [n containsString:@"ccuicameramodule"]) return @"camera";
        if ([n containsString:@"comappleaccessibilitycontrolcenterhearingdevices"] ||
            [n containsString:@"hacccontentmodule"]) return @"hearing";
    }

    NSString *joined = MGNormalized([values componentsJoinedByString:@" "]);
    if (!joined.length) return nil;
    if ([joined containsString:@"screencapture"] || [joined containsString:@"screenrecord"] || [joined containsString:@"recordingmodule"]) return @"screenrecording";
    if ([joined containsString:@"screenmirror"] || [joined containsString:@"airplaymirror"]) return @"screenmirroring";
    if ([joined containsString:@"orientation"] || [joined containsString:@"rotationlock"]) return @"orientation";
    if ([joined containsString:@"lowpower"] || [joined containsString:@"batterysaver"]) return @"lowpower";
    if ([joined containsString:@"darkmode"] || [joined containsString:@"appearance"]) return @"darkmode";
    if ([joined containsString:@"connectivity"] || [joined containsString:@"airplane"]) return @"connectivity";
    if ([joined containsString:@"displaymodule"] || [joined containsString:@"brightness"]) return @"brightness";
    if ([joined containsString:@"audiomodule"] || [joined containsString:@"volume"]) return @"volume";
    if ([joined containsString:@"nowplaying"] || [joined containsString:@"mediacontrolsmodule"] || [joined containsString:@"mrui"]) return @"media";
    if ([joined containsString:@"focus"] || [joined containsString:@"donotdisturb"]) return @"focus";
    if ([joined containsString:@"flashlight"] || [joined containsString:@"torch"]) return @"flashlight";
    if ([joined containsString:@"timer"] || [joined containsString:@"clockmodule"]) return @"timer";
    if ([joined containsString:@"calculator"]) return @"calculator";
    if ([joined containsString:@"camera"]) return @"camera";
    if ([joined containsString:@"hearing"]) return @"hearing";
    if ([joined containsString:@"quicknote"] || [joined containsString:@"notes"]) return @"notes";
    if ([joined containsString:@"homecontrol"] || [joined containsString:@"homekit"] || [joined containsString:@"homemodule"]) return @"home";
    return @"other";
}

static NSString *MGImagePathForSlot(NSString *slot) {
    if (!slot.length) return nil;
    return [MGBackgroundDirectory stringByAppendingPathComponent:[slot stringByAppendingString:@".jpg"]];
}

static BOOL MGIsExpandedPresentation(UIView *root) {
    if (!root) return NO;
    CGSize rootSize = root.bounds.size;
    CGSize screenSize = UIScreen.mainScreen.bounds.size;
    CGFloat rootArea = fabs(rootSize.width * rootSize.height);
    CGFloat screenArea = fabs(screenSize.width * screenSize.height);
    if (rootArea <= 0.0 || screenArea <= 0.0) return NO;

    // iOS 16 expanded CC modules become essentially screen-sized. The compact
    // connectivity tile can be ~320x158, so an area ratio is safer than width.
    return rootArea >= (screenArea * 0.55);
}

static BOOL MGIsBackgroundMaterialView(UIView *view) {
    if (!view || view.tag == MGImageTag) return NO;
    NSString *name = NSStringFromClass(view.class);
    // Only touch module-specific material classes. Hiding every UIVisualEffectView
    // can break expanded-module presentation/dismissal and system interactions.
    NSArray<NSString *> *needles = @[@"MTMaterialView", @"CCUIModuleBackground", @"ContentModuleBackground"];
    for (NSString *needle in needles) if ([name containsString:needle]) return YES;
    return NO;
}

static void MGSetMaterialHiddenRecursively(UIView *view, BOOL hide) {
    if (!view) return;
    if (MGIsBackgroundMaterialView(view)) {
        NSNumber *touched = objc_getAssociatedObject(view, MGBackgroundTouchedKey);
        if (hide) {
            if (!touched.boolValue) {
                objc_setAssociatedObject(view, MGOriginalHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(view, MGOriginalAlphaKey, @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(view, MGBackgroundTouchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            view.hidden = YES;
        } else if (touched.boolValue) {
            NSNumber *oldHidden = objc_getAssociatedObject(view, MGOriginalHiddenKey);
            NSNumber *oldAlpha = objc_getAssociatedObject(view, MGOriginalAlphaKey);
            view.hidden = oldHidden ? oldHidden.boolValue : NO;
            if (oldAlpha) view.alpha = oldAlpha.doubleValue;
            objc_setAssociatedObject(view, MGBackgroundTouchedKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    for (UIView *child in view.subviews) MGSetMaterialHiddenRecursively(child, hide);
}

static void MGApplyGlowRecursively(UIView *view, BOOL enabled, CGFloat intensity, CGFloat width) {
    if (!view || view.tag == MGImageTag) return;
    BOOL leaf = [view isKindOfClass:UIImageView.class] || [view isKindOfClass:UILabel.class];
    if (leaf) {
        if (enabled) {
            view.layer.shadowColor = UIColor.whiteColor.CGColor;
            view.layer.shadowOpacity = MIN(1.0, MAX(0.05, intensity));
            view.layer.shadowRadius = MIN(12.0, MAX(0.5, width * 2.0));
            view.layer.shadowOffset = CGSizeZero;
            view.layer.masksToBounds = NO;
        } else {
            view.layer.shadowOpacity = 0.0;
            view.layer.shadowRadius = 0.0;
        }
    }
    for (UIView *child in view.subviews) MGApplyGlowRecursively(child, enabled, intensity, width);
}

static void MGRestoreCompactBackgroundChanges(UIView *root) {
    if (!root) return;
    UIView *background = [root viewWithTag:MGImageTag];
    [background removeFromSuperview];
    MGSetMaterialHiddenRecursively(root, NO);
}

static void MGApplyToController(id controller, NSString *source) {
    if (!controller) return;
    UIView *root = nil;
    @try { root = [controller view]; } @catch (__unused NSException *e) { return; }
    if (!root) return;

    NSArray<NSString *> *candidates = MGCandidateStrings(controller);
    NSString *slot = MGSlotForCandidates(candidates);
    NSString *path = MGImagePathForSlot(slot);
    BOOL fileExists = path.length && [NSFileManager.defaultManager fileExistsAtPath:path];
    BOOL enabled = MGPreferenceBool(@"CCModuleBackgroundsEnabled", NO);
    BOOL removeBlur = MGPreferenceBool(@"CCModuleRemoveBlur", YES);
    CGFloat opacity = MGPreferenceFloat(@"CCModuleBackgroundOpacity", 1.0);
    BOOL glowEnabled = MGPreferenceBool(@"CCModuleControlGlowEnabled", YES);
    CGFloat glowIntensity = MGPreferenceFloat(@"CCModuleControlGlowIntensity", 0.8);
    CGFloat glowWidth = MGPreferenceFloat(@"CCModuleControlGlowWidth", 1.5);
    BOOL expanded = MGIsExpandedPresentation(root);

    NSString *signature = [NSString stringWithFormat:@"%@|%@|%d|%d|%.3f|expanded=%d|%.0fx%.0f|%@",
                           slot ?: @"nil", fileExists ? @"file" : @"nofile", enabled, removeBlur,
                           opacity, expanded, CGRectGetWidth(root.bounds), CGRectGetHeight(root.bounds), source ?: @""];
    NSString *previous = objc_getAssociatedObject(controller, MGLastSignatureKey);
    BOOL shouldLog = MGDiagnosticEnabled() && ![signature isEqualToString:previous];
    if (shouldLog) objc_setAssociatedObject(controller, MGLastSignatureKey, signature, OBJC_ASSOCIATION_COPY_NONATOMIC);

    // Critical safety rule: never place our image or hide material while a Control
    // Center module is expanded. iOS reuses this controller as a screen-sized view;
    // modifying that root can interfere with the system's tap-outside dismissal.
    if (expanded) {
        MGRestoreCompactBackgroundChanges(root);
        if (shouldLog) {
            MGLog(NO, @"expanded-bypass source=%@ controller=%@ slot=%@ frame=%@ candidates=%@",
                  source, NSStringFromClass([controller class]), slot, NSStringFromCGRect(root.frame), candidates);
        }
        return;
    }

    UIImageView *background = (UIImageView *)[root viewWithTag:MGImageTag];
    UIImage *image = nil;
    if (enabled && fileExists) image = [UIImage imageWithContentsOfFile:path];

    BOOL shouldShow = enabled && image != nil;
    if (shouldShow) {
        if (!background || ![background isKindOfClass:UIImageView.class]) {
            background = [[UIImageView alloc] initWithFrame:root.bounds];
            background.tag = MGImageTag;
            background.userInteractionEnabled = NO;
            background.contentMode = UIViewContentModeScaleAspectFill;
            background.clipsToBounds = YES;
            background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [root insertSubview:background atIndex:0];
        }
        background.frame = root.bounds;
        background.layer.cornerRadius = root.layer.cornerRadius;
        background.image = image;
        background.alpha = MIN(1.0, MAX(0.0, opacity));
        background.hidden = NO;
        MGSetMaterialHiddenRecursively(root, removeBlur);
    } else {
        MGRestoreCompactBackgroundChanges(root);
    }

    MGApplyGlowRecursively(root, glowEnabled, glowIntensity, glowWidth);

    if (shouldLog) {
        MGLog(NO, @"apply source=%@ controller=%@ candidates=%@ slot=%@ path=%@ exists=%d enabled=%d imageLoaded=%d removeBlur=%d opacity=%.2f expanded=%d root=%@ frame=%@ subviews=%lu imageView=%@",
              source, NSStringFromClass([controller class]), candidates, slot, path, fileExists, enabled,
              image != nil, removeBlur, opacity, expanded, NSStringFromClass(root.class), NSStringFromCGRect(root.frame),
              (unsigned long)root.subviews.count, shouldShow ? @"visible" : @"absent");
    }
}

static void MGRegisterController(id controller) {
    if (!controller) return;
    @synchronized (MGControllers) { [MGControllers addObject:controller]; }
}

static void MGApplyAll(NSString *source) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *controllers = nil;
        @synchronized (MGControllers) { controllers = MGControllers.allObjects; }
        MGLog(NO, @"refresh source=%@ controllers=%lu enabled=%d directoryExists=%d directory=%@",
              source, (unsigned long)controllers.count, MGPreferenceBool(@"CCModuleBackgroundsEnabled", NO),
              [NSFileManager.defaultManager fileExistsAtPath:MGBackgroundDirectory], MGBackgroundDirectory);
        for (id controller in controllers) MGApplyToController(controller, source);
    });
}

static void MGPreferencesChanged(__unused CFNotificationCenterRef center, __unused void *observer, __unused CFStringRef name, __unused const void *object, __unused CFDictionaryRef userInfo) {
    MGApplyAll(@"preferences.changed");
}

static void MGNextLogControlChanged(__unused CFNotificationCenterRef center, __unused void *observer, __unused CFStringRef name, __unused const void *object, __unused CFDictionaryRef userInfo) {
    BOOL active = MGDiagnosticEnabled();
    MGLog(active, @"diagnostic-control active=%d prefsDomain=%@ backgroundDirectory=%@ log=%@", active, MGPrefsDomain, MGBackgroundDirectory, MGLogPath);
    MGApplyAll(@"nextlog.control");
}

%hook CCUIModuleContainerViewController
- (void)viewDidLoad {
    %orig;
    MGRegisterController(self);
    MGApplyToController(self, @"CCUIModuleContainerViewController.viewDidLoad");
}
- (void)viewDidLayoutSubviews {
    %orig;
    MGRegisterController(self);
    MGApplyToController(self, @"CCUIModuleContainerViewController.layout");
}
%end

%hook CCUIContentModuleContainerViewController
- (void)viewDidLoad {
    %orig;
    MGRegisterController(self);
    MGApplyToController(self, @"CCUIContentModuleContainerViewController.viewDidLoad");
}
- (void)viewDidLayoutSubviews {
    %orig;
    MGRegisterController(self);
    MGApplyToController(self, @"CCUIContentModuleContainerViewController.layout");
}
%end

%ctor {
    @autoreleasepool {
        MGControllers = [NSHashTable weakObjectsHashTable];
        [NSFileManager.defaultManager createDirectoryAtPath:MGBackgroundDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, MGPreferencesChanged,
                                        (__bridge CFStringRef)MGPrefsChanged, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, MGNextLogControlChanged,
                                        (__bridge CFStringRef)MGNextLogChanged, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        MGLog(NO, @"ModuleGlassRuntime 1.0.3 loaded SpringBoard=%@ prefsEnabled=%d",
              NSBundle.mainBundle.bundleIdentifier, MGPreferenceBool(@"CCModuleBackgroundsEnabled", NO));
    }
}
