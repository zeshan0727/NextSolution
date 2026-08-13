#import "CHLRootListController.h"
#import <Preferences/PSSpecifier.h>

static CFStringRef const CHLPreferenceDomain = CFSTR("com.nextsolution.cleanhomelabels");
static CFStringRef const CHLPreferencesChanged = CFSTR("com.nextsolution.cleanhomelabels.preferences.changed");
static CFStringRef const CHLRespringRequested = CFSTR("com.nextsolution.cleanhomelabels.respring");

@implementation CHLRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(CHLPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, CHLPreferenceDomain));
    return value ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, CHLPreferenceDomain);
    CFPreferencesAppSynchronize(CHLPreferenceDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CHLPreferencesChanged, NULL, NULL, true);
}
- (void)respring {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CHLRespringRequested, NULL, NULL, true);
}
@end
