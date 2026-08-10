#import "WDHRootListController.h"
#import <Preferences/PSSpecifier.h>

static CFStringRef const WDHPreferenceDomain = CFSTR("com.nextsolution.wifidrophaptic");
static CFStringRef const WDHPreferencesChanged = CFSTR("com.nextsolution.wifidrophaptic.preferences.changed");

@implementation WDHRootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(WDHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, WDHPreferenceDomain));
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, WDHPreferenceDomain);
    CFPreferencesAppSynchronize(WDHPreferenceDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), WDHPreferencesChanged, NULL, NULL, true);
}

@end
