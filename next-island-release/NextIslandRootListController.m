#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <spawn.h>

extern char **environ;

@interface PSSpecifier : NSObject
- (id)propertyForKey:(NSString *)key;
@end

@interface PSListController : UIViewController
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
@end

@interface NextIslandRootListController : PSListController {
    NSArray *_nextIslandSpecifiers;
}
@end

// The package is now cc.nextsolution.nextisland, but the original preference
// domain and Darwin notification names stay unchanged. That preserves every
// existing Dynamic Island choice and lets the runtime remain byte-for-byte
// identical to the proven NextAura implementation.
static NSString * const NIPreferencesDomain = @"com.nextsolution.unlockvibrate";
static CFStringRef const NIChangedNotification = CFSTR("com.nextsolution.unlockvibrate/preferences.changed");
static CFStringRef const NIPreviewShowNotification = CFSTR("com.nextsolution.unlockvibrate/dynamic-island-preview-show");
static CFStringRef const NIPreviewHideNotification = CFSTR("com.nextsolution.unlockvibrate/dynamic-island-preview-hide");
static CFStringRef const NITestNotification = CFSTR("com.nextsolution.unlockvibrate/test-dynamic-island-suite");

static NSArray<NSString *> *NIAllPreferenceKeys(void) {
    return @[
        @"DynamicIslandLivePreview",
        @"DynamicIslandEnabled",
        @"DynamicIslandShowOnLockScreen",
        @"DynamicIslandShowInsideApps",
        @"DynamicIslandShowOnHomeScreen",
        @"DynamicIslandDoubleTapOpen",
        @"DynamicIslandSwipeDownExpand",
        @"DynamicIslandLongPress",
        @"DynamicIslandSwipeDismiss",
        @"DynamicIslandStackEnabled",
        @"DynamicIslandHideStockBanner",
        @"DynamicIslandStackLimit",
        @"DynamicIslandAppearanceMode",
        @"DynamicIslandBackgroundOpacity",
        @"DynamicIslandCustomHue",
        @"DynamicIslandBlurEnabled",
        @"DynamicIslandBlurStrength",
        @"DynamicIslandBlurStyle",
        @"DynamicIslandCompactWidth",
        @"DynamicIslandCompactHeight",
        @"DynamicIslandExpandedWidth",
        @"DynamicIslandTextScale",
        @"DynamicIslandShowIcon",
        @"DynamicIslandPriorityGlow",
        @"DynamicIslandDuration",
        @"DynamicIslandHaptic",
        @"DynamicIslandVisibilityMode"
    ];
}

static void NIPost(CFStringRef name) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        name,
        NULL,
        NULL,
        true
    );
}

static id NIReadValue(NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)NIPreferencesDomain
    );
    return CFBridgingRelease(value);
}

static void NIWriteValue(NSString *key, id value) {
    CFPreferencesSetAppValue(
        (__bridge CFStringRef)key,
        value ? (__bridge CFPropertyListRef)value : NULL,
        (__bridge CFStringRef)NIPreferencesDomain
    );
}

static void NISynchronize(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NIPreferencesDomain);
}

static NSString *NIJailbreakRoot(void) {
    NSString *bundlePath = [NSBundle bundleForClass:[NextIslandRootListController class]].bundlePath;
    if (bundlePath.length == 0) return nil;
    NSString *preferenceBundles = [bundlePath stringByDeletingLastPathComponent];
    NSString *library = [preferenceBundles stringByDeletingLastPathComponent];
    return [library stringByDeletingLastPathComponent];
}

static void NIRespring(void) {
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    NSString *root = NIJailbreakRoot();
    if (root.length > 0) {
        [candidates addObject:[root stringByAppendingPathComponent:@"usr/bin/sbreload"]];
    }
    [candidates addObject:@"/var/jb/usr/bin/sbreload"];
    [candidates addObject:@"/usr/bin/sbreload"];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        if (![fm isExecutableFileAtPath:path]) continue;
        pid_t pid = 0;
        const char *argv[] = { path.fileSystemRepresentation, NULL };
        if (posix_spawn(&pid, path.fileSystemRepresentation, NULL, NULL, (char * const *)argv, environ) == 0) {
            return;
        }
    }
}

@implementation NextIslandRootListController

- (NSArray *)specifiers {
    if (!_nextIslandSpecifiers) {
        _nextIslandSpecifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _nextIslandSpecifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Next Island";
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    NIPost(NIChangedNotification);

    NSString *key = [specifier propertyForKey:@"key"];
    BOOL livePreview = [[NIReadValue(@"DynamicIslandLivePreview") ?: @YES] boolValue];
    if ([key isEqualToString:@"DynamicIslandLivePreview"] && ![value boolValue]) {
        NIPost(NIPreviewHideNotification);
    } else if (livePreview) {
        NIPost(NIPreviewShowNotification);
    }
}

- (void)showDynamicIslandPreview:(id)sender {
    (void)sender;
    NIPost(NIPreviewShowNotification);
}

- (void)hideDynamicIslandPreview:(id)sender {
    (void)sender;
    NIPost(NIPreviewHideNotification);
}

- (void)testDynamicIslandSuite:(id)sender {
    (void)sender;
    NIPost(NITestNotification);
}

- (void)resetDynamicIslandAppearance:(id)sender {
    (void)sender;
    NSDictionary<NSString *, id> *defaults = @{
        @"DynamicIslandAppearanceMode": @0,
        @"DynamicIslandBackgroundOpacity": @0.96,
        @"DynamicIslandCustomHue": @0.58,
        @"DynamicIslandBlurEnabled": @NO,
        @"DynamicIslandBlurStrength": @0.7,
        @"DynamicIslandBlurStyle": @0,
        @"DynamicIslandCompactWidth": @360.0,
        @"DynamicIslandCompactHeight": @106.0,
        @"DynamicIslandExpandedWidth": @382.0,
        @"DynamicIslandTextScale": @1.0,
        @"DynamicIslandDuration": @4.0
    };
    [defaults enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        (void)stop;
        NIWriteValue(key, value);
    }];
    NISynchronize();
    NIPost(NIChangedNotification);
    if ([[NIReadValue(@"DynamicIslandLivePreview") ?: @YES] boolValue]) {
        NIPost(NIPreviewShowNotification);
    }
}

- (void)applyNextIslandChanges:(id)sender {
    (void)sender;
    NIPost(NIChangedNotification);
    NIRespring();
}

- (void)resetNextIslandSection:(id)sender {
    (void)sender;
    for (NSString *key in NIAllPreferenceKeys()) {
        NIWriteValue(key, nil);
    }
    NISynchronize();
    NIPost(NIPreviewHideNotification);
    NIPost(NIChangedNotification);
    NIRespring();
}

// Preserve the action names used by the original DynamicIsland.plist.
- (void)applySuiteChanges:(id)sender {
    [self applyNextIslandChanges:sender];
}

- (void)resetCurrentNextAuraSection:(id)sender {
    [self resetNextIslandSection:sender];
}

@end
