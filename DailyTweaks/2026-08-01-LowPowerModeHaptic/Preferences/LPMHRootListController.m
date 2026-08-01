#import "LPMHRootListController.h"
#import <Preferences/PSSpecifier.h>

static CFStringRef const LPMHPreferenceDomain = CFSTR("com.nextsolution.lowpowermodehaptic");
static CFStringRef const LPMHPreferencesChanged = CFSTR("com.nextsolution.lowpowermodehaptic.preferences.changed");

@implementation LPMHRootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(LPMHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, LPMHPreferenceDomain));
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, LPMHPreferenceDomain);
    CFPreferencesAppSynchronize(LPMHPreferenceDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), LPMHPreferencesChanged, NULL, NULL, true);
}

@end
