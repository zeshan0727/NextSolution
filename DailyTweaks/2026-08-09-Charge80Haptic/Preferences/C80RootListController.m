#import "C80RootListController.h"
#import <Preferences/PSSpecifier.h>

static CFStringRef const C80PreferenceDomain = CFSTR("com.nextsolution.charge80haptic");
static CFStringRef const C80PreferencesChanged = CFSTR("com.nextsolution.charge80haptic.preferences.changed");

@implementation C80RootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(C80PreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, C80PreferenceDomain));
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, C80PreferenceDomain);
    CFPreferencesAppSynchronize(C80PreferenceDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), C80PreferencesChanged, NULL, NULL, true);
}

@end
