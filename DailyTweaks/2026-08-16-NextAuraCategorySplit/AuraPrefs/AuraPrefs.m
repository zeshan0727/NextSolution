#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString * const AuraDefaultsDomain = @"com.nextsolution.unlockvibrate";
static NSString * const AuraChangedNotification = @"com.nextsolution.unlockvibrate/preferences.changed";

static void AuraPost(NSString *name) {
    if (!name.length) return;
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)name,
                                         NULL, NULL, YES);
}

static NSString *AuraPlistForLabel(NSString *label) {
    NSDictionary *map = @{
        @"Pulse": @"Feedback",
        @"Therma": @"ThermalSweat",
        @"HomeFlow": @"HomeScreen",
        @"DockCraft": @"DockFolders",
        @"LockCraft": @"LockScreen",
        @"StatusKit": @"StatusBar",
        @"ControlKit": @"ControlCenter",
        @"Control Deck": @"CCSecondPage",
        @"Module Glass": @"CCModuleBackgrounds",
        @"Notify Island": @"DynamicIsland",
        @"Notify Glow": @"NotificationGlow",
        @"NowPlay": @"NowPlaying",
        @"NotifyKit": @"Notifications",
        @"SwitchDeck": @"AppSwitcher",
        @"HUDKit": @"SystemOverlays",
        @"Motion": @"Animations",
        @"Rescue": @"SafetyRecovery"
    };
    return map[label ?: @""];
}

@interface AuraCategoryListController : PSListController <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property(nonatomic,copy) NSString *pendingModuleSlot;
@end

@implementation AuraCategoryListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSString *plistName = [self.specifier propertyForKey:@"plist"];
        NSString *label = [self.specifier propertyForKey:@"label"] ?: self.specifier.name;
        if (!plistName.length) plistName = AuraPlistForLabel(label);
        if (!plistName.length) plistName = @"Feedback";
        _specifiers = [self loadSpecifiersFromPlistName:plistName target:self];
        self.title = label.length ? label : @"Settings";
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    NSString *post = [specifier propertyForKey:@"PostNotification"];
    if (post.length) AuraPost(post);
}

- (void)testDynamicIslandSuite:(id)sender { AuraPost(@"com.nextsolution.unlockvibrate/test-dynamic-island-suite"); }
- (void)testNotificationIsland:(id)sender { AuraPost(@"com.nextsolution.unlockvibrate/test-notification-island"); }
- (void)testNotificationScreen:(id)sender { AuraPost(@"com.nextsolution.unlockvibrate/test-notification-screen"); }
- (void)testNotificationAOD:(id)sender { AuraPost(@"com.nextsolution.unlockvibrate/test-notification-aod"); }
- (void)testNotificationBurning:(id)sender { AuraPost(@"com.nextsolution.unlockvibrate/test-notification-burning"); }
- (void)refreshBatteryReading:(id)sender { AuraPost(@"com.nextsolution.unlockvibrate/refresh-battery-reading"); }
- (void)testSweat:(id)sender { AuraPost(@"com.nextsolution.unlockvibrate/test-sweat"); }

- (void)clearSafeSuiteRecovery:(id)sender {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:AuraDefaultsDomain];
    [d removeObjectForKey:@"SafeSuiteBootPending"];
    [d removeObjectForKey:@"SafeSuiteSafeModeTriggered"];
    [d synchronize];
    AuraPost(AuraChangedNotification);
}

- (void)resetSafeSuiteSettings:(id)sender {
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"SafeLabKeys" withExtension:@"plist"];
    NSDictionary *dict = url ? [NSDictionary dictionaryWithContentsOfURL:url] : nil;
    NSArray *keys = [dict[@"keys"] isKindOfClass:NSArray.class] ? dict[@"keys"] : @[];
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:AuraDefaultsDomain];
    for (NSString *key in keys) if ([key isKindOfClass:NSString.class]) [d removeObjectForKey:key];
    [d synchronize];
    AuraPost(AuraChangedNotification);
}

- (NSString *)ccBackgroundDirectory {
    NSArray<NSString *> *libraries = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *library = libraries.firstObject ?: @"/var/mobile/Library";
    NSString *preferences = [library stringByAppendingPathComponent:@"Preferences"];
    return [preferences stringByAppendingPathComponent:@"NextSolutionTweaks/CCBackgrounds"];
}

- (void)removeCCModuleFilesForSlot:(NSString *)slot {
    if (!slot.length) return;
    NSString *dir = [self ccBackgroundDirectory];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        if ([name isEqualToString:slot] || [name hasPrefix:[slot stringByAppendingString:@"."]]) {
            [fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
        }
    }
}

- (void)configureCCModuleBackground:(PSSpecifier *)specifier {
    NSString *slot = [specifier propertyForKey:@"moduleSlot"];
    NSString *title = [specifier propertyForKey:@"moduleTitle"] ?: @"Module";
    if (!slot.length) return;
    self.pendingModuleSlot = slot;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
                                                                   message:@"Choose a background image or remove the current one."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Choose Photo" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIImagePickerController *picker = [UIImagePickerController new];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.delegate = weakSelf;
        [weakSelf presentViewController:picker animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
        [weakSelf removeCCModuleFilesForSlot:slot];
        AuraPost(AuraChangedNotification);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), 40, 1, 1);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    NSString *slot = self.pendingModuleSlot;
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (!image || !slot.length) return;

    NSString *dir = [self ccBackgroundDirectory];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [self removeCCModuleFilesForSlot:slot];

    // The existing CCModuleBackgrounds runtime reads <slot>.jpg specifically.
    NSData *data = UIImageJPEGRepresentation(image, 0.92);
    NSString *path = [dir stringByAppendingPathComponent:[slot stringByAppendingString:@".jpg"]];
    if ([data writeToFile:path atomically:YES]) {
        AuraPost(AuraChangedNotification);
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)resetAllCCModuleBackgrounds:(id)sender {
    NSString *dir = [self ccBackgroundDirectory];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        [fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
    }
    AuraPost(AuraChangedNotification);
}

@end
