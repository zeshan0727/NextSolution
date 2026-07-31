#import "NHTRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

static CFStringRef const NHTPreferenceDomain = CFSTR("com.nextsolution.nexthometorch");
static CFStringRef const NHTRuntimeDomain = CFSTR("com.nextsolution.nexthometorch.runtime");
static CFStringRef const NHTPreferencesChanged = CFSTR("com.nextsolution.nexthometorch.preferences.changed");
static CFStringRef const NHTTestFlashlight = CFSTR("com.nextsolution.nexthometorch.test-flashlight");

@implementation NHTRootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(NHTPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, NHTPreferenceDomain));
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, NHTPreferenceDomain);
    CFPreferencesAppSynchronize(NHTPreferenceDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), NHTPreferencesChanged, NULL, NULL, true);
}

- (void)testFlashlight {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), NHTTestFlashlight, NULL, NULL, true);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize(NHTRuntimeDomain);
        id route = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("lastRoute"), NHTRuntimeDomain));
        id loaded = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("tweakLoaded"), NHTRuntimeDomain));
        NSString *message = [loaded boolValue]
            ? [NSString stringWithFormat:@"SpringBoard received the command. Route: %@", route ?: @"Waiting for result"]
            : @"The tweak is not loaded into SpringBoard. Reinstall the correct RootHide or rootless package and respring.";

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Flashlight Test"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

@end
