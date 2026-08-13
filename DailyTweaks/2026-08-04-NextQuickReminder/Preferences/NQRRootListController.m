#import "NQRRootListController.h"
#import <Preferences/PSSpecifier.h>

static CFStringRef const NQRDomain = CFSTR("com.nextsolution.nextquickreminder");
static CFStringRef const NQRChanged = CFSTR("com.nextsolution.nextquickreminder.preferences.changed");
static CFStringRef const NQRShowPanel = CFSTR("com.nextsolution.nextquickreminder.showpanel");

@implementation NQRRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    CFPreferencesAppSynchronize(NQRDomain);
    id value = key.length
        ? CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, NQRDomain))
        : nil;
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;

    CFPreferencesSetAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFPropertyListRef)value,
        NQRDomain
    );
    CFPreferencesAppSynchronize(NQRDomain);
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NQRChanged,
        NULL,
        NULL,
        true
    );
}

- (void)testQuickPanel {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NQRShowPanel,
        NULL,
        NULL,
        true
    );
}

- (void)clearSavedDraft {
    CFPreferencesSetAppValue(CFSTR("draft"), NULL, NQRDomain);
    CFPreferencesAppSynchronize(NQRDomain);

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Draft Cleared"
        message:@"The saved quick-reminder draft has been removed."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
