#import "BEHRootListController.h"
#import <Preferences/PSSpecifier.h>

static CFStringRef const BEHDomain = CFSTR("com.nextsolution.brightnessedgehaptic");
static CFStringRef const BEHChanged = CFSTR("com.nextsolution.brightnessedgehaptic.preferences.changed");

@implementation BEHRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    CFPreferencesAppSynchronize(BEHDomain);
    id value = key.length ? CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, BEHDomain)) : nil;
    return value ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, BEHDomain);
    CFPreferencesAppSynchronize(BEHDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), BEHChanged, NULL, NULL, true);
}
@end
