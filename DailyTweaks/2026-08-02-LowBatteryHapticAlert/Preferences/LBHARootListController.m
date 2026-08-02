#import "LBHARootListController.h"
#import <Preferences/PSSpecifier.h>

static CFStringRef const LBHAPreferenceDomain = CFSTR("com.nextsolution.lowbatteryhapticalert");
static CFStringRef const LBHAPreferencesChanged = CFSTR("com.nextsolution.lowbatteryhapticalert.preferences.changed");

@implementation LBHARootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(LBHAPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, LBHAPreferenceDomain));
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, LBHAPreferenceDomain);
    CFPreferencesAppSynchronize(LBHAPreferenceDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         LBHAPreferencesChanged,
                                         NULL,
                                         NULL,
                                         true);
}

@end
