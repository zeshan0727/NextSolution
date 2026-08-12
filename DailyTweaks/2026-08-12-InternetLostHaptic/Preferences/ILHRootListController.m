#import "ILHRootListController.h"
#import <Preferences/PSSpecifier.h>

static CFStringRef const ILHPreferenceDomain = CFSTR("com.nextsolution.internetlosthaptic");
static CFStringRef const ILHPreferencesChanged = CFSTR("com.nextsolution.internetlosthaptic.preferences.changed");

@implementation ILHRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(ILHPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, ILHPreferenceDomain));
    return value ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, ILHPreferenceDomain);
    CFPreferencesAppSynchronize(ILHPreferenceDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ILHPreferencesChanged, NULL, NULL, true);
}
@end
