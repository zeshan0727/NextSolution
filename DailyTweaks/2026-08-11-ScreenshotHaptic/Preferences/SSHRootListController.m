#import "SSHRootListController.h"
#import <Preferences/PSSpecifier.h>

static CFStringRef const SSHPreferenceDomain = CFSTR("com.nextsolution.screenshothaptic");
static CFStringRef const SSHPreferencesChanged = CFSTR("com.nextsolution.screenshothaptic.preferences.changed");

@implementation SSHRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(SSHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, SSHPreferenceDomain));
    return value ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, SSHPreferenceDomain);
    CFPreferencesAppSynchronize(SSHPreferenceDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), SSHPreferencesChanged, NULL, NULL, true);
}
@end
