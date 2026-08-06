#import "CIHRootListController.h"
#import <Preferences/PSSpecifier.h>

static CFStringRef const CIHPreferenceDomain = CFSTR("com.nextsolution.charginginterruptedhaptic");
static CFStringRef const CIHPreferencesChanged = CFSTR("com.nextsolution.charginginterruptedhaptic.preferences.changed");

@implementation CIHRootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(CIHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, CIHPreferenceDomain));
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, CIHPreferenceDomain);
    CFPreferencesAppSynchronize(CIHPreferenceDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CIHPreferencesChanged, NULL, NULL, true);
}

@end
