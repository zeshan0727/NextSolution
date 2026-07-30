#import "NHLRootListController.h"
#import <Preferences/PSSpecifier.h>

static CFStringRef const NHLPreferenceDomain = CFSTR("com.nextsolution.nexthomelock");
static CFStringRef const NHLPreferencesChanged = CFSTR("com.nextsolution.nexthomelock.preferences.changed");

@implementation NHLRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];

    CFPreferencesAppSynchronize(NHLPreferenceDomain);
    id value = CFBridgingRelease(
        CFPreferencesCopyAppValue((__bridge CFStringRef)key, NHLPreferenceDomain)
    );
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;

    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             NHLPreferenceDomain);
    CFPreferencesAppSynchronize(NHLPreferenceDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         NHLPreferencesChanged,
                                         NULL,
                                         NULL,
                                         true);
}

@end
