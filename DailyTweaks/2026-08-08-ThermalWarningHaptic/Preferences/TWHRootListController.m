#import "TWHRootListController.h"
#import <Preferences/PSSpecifier.h>

static CFStringRef const TWHPreferenceDomain = CFSTR("com.nextsolution.thermalwarninghaptic");
static CFStringRef const TWHPreferencesChanged = CFSTR("com.nextsolution.thermalwarninghaptic.preferences.changed");

@implementation TWHRootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(TWHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, TWHPreferenceDomain));
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, TWHPreferenceDomain);
    CFPreferencesAppSynchronize(TWHPreferenceDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), TWHPreferencesChanged, NULL, NULL, true);
}

@end
