#import "FCHRootListController.h"
#import <Preferences/PSSpecifier.h>

static CFStringRef const FCHPreferenceDomain = CFSTR("com.nextsolution.fullchargehaptic");
static CFStringRef const FCHPreferencesChanged = CFSTR("com.nextsolution.fullchargehaptic.preferences.changed");

@implementation FCHRootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(FCHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, FCHPreferenceDomain));
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, FCHPreferenceDomain);
    CFPreferencesAppSynchronize(FCHPreferenceDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), FCHPreferencesChanged, NULL, NULL, true);
}

@end
