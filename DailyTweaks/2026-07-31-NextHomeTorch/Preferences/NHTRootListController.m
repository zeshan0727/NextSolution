#import "NHTRootListController.h"
#import <Preferences/PSSpecifier.h>

static CFStringRef const NHTPreferenceDomain = CFSTR("com.nextsolution.nexthometorch");
static CFStringRef const NHTPreferencesChanged = CFSTR("com.nextsolution.nexthometorch.preferences.changed");

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

@end
