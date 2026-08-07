#import "HDHRootListController.h"
#import <Preferences/PSSpecifier.h>

static CFStringRef const HDHPreferenceDomain = CFSTR("com.nextsolution.headphonedisconnecthaptic");
static CFStringRef const HDHPreferencesChanged = CFSTR("com.nextsolution.headphonedisconnecthaptic.preferences.changed");

@implementation HDHRootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(HDHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, HDHPreferenceDomain));
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, HDHPreferenceDomain);
    CFPreferencesAppSynchronize(HDHPreferenceDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), HDHPreferencesChanged, NULL, NULL, true);
}

@end
