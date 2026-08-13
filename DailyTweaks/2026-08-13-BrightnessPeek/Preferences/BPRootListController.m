#import "BPRootListController.h"
#import <Preferences/PSSpecifier.h>

static CFStringRef const BPPreferenceDomain = CFSTR("com.nextsolution.brightnesspeek");
static CFStringRef const BPPreferencesChanged = CFSTR("com.nextsolution.brightnesspeek.preferences.changed");

@implementation BPRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(BPPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, BPPreferenceDomain));
    return value ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, BPPreferenceDomain);
    CFPreferencesAppSynchronize(BPPreferenceDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), BPPreferencesChanged, NULL, NULL, true);
}
@end
