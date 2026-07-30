#import "NHLRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

static CFStringRef const NHLPreferenceDomain = CFSTR("com.nextsolution.nexthomelock");
static CFStringRef const NHLRuntimeDomain = CFSTR("com.nextsolution.nexthomelock.runtime");
static CFStringRef const NHLPreferencesChanged = CFSTR("com.nextsolution.nexthomelock.preferences.changed");
static CFStringRef const NHLTestLockNotification = CFSTR("com.nextsolution.nexthomelock.test-lock");

@implementation NHLRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

- (id)preferenceValueForKey:(NSString *)key defaultValue:(id)defaultValue {
    CFPreferencesAppSynchronize(NHLPreferenceDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                            NHLPreferenceDomain));
    return value ?: defaultValue;
}

- (id)runtimeValueForKey:(NSString *)key {
    CFPreferencesAppSynchronize(NHLRuntimeDomain);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                       NHLRuntimeDomain));
}

- (void)setRuntimeValue:(id)value forKey:(NSString *)key {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             NHLRuntimeDomain);
    CFPreferencesAppSynchronize(NHLRuntimeDomain);
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    return [self preferenceValueForKey:key defaultValue:[specifier propertyForKey:@"default"]];
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

- (NSString *)formattedTimeForValue:(id)value {
    NSTimeInterval timestamp = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
    if (timestamp <= 0) return @"Never";

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]] ?: @"Unknown";
}

- (NSString *)installedVersion {
    return @"1.0.4";
}

- (NSString *)implementationStatus {
    return [self runtimeValueForKey:@"implementation"] ?: @"Waiting for SpringBoard injection";
}

- (NSString *)injectionStatus {
    BOOL loaded = [[self runtimeValueForKey:@"tweakLoaded"] boolValue];
    NSString *version = [self runtimeValueForKey:@"loadedVersion"];
    if (!loaded) return @"Not detected in SpringBoard";
    if (![version isEqualToString:@"1.0.4"]) {
        return [NSString stringWithFormat:@"Stale runtime: %@", version ?: @"unknown"];
    }
    return [NSString stringWithFormat:@"Active · PID %@", [self runtimeValueForKey:@"springBoardPID"] ?: @"?"];
}

- (NSString *)loadedAtStatus {
    return [self formattedTimeForValue:[self runtimeValueForKey:@"loadedAt"]];
}

- (NSString *)iconListClassStatus {
    if (![[self runtimeValueForKey:@"tweakLoaded"] boolValue]) return @"Unknown until injected";
    return [[self runtimeValueForKey:@"iconListClassPresent"] boolValue]
        ? @"SBIconListView found"
        : @"SBIconListView missing";
}

- (NSString *)touchHookStatus {
    if (![[self runtimeValueForKey:@"tweakLoaded"] boolValue]) return @"Unknown until injected";
    if (![[self runtimeValueForKey:@"iconListHookSeen"] boolValue]) {
        return @"Not reached — tap empty Home Screen once";
    }
    return [NSString stringWithFormat:@"Reached at %@",
            [self formattedTimeForValue:[self runtimeValueForKey:@"iconListHookSeenAt"]]];
}

- (NSString *)lockSelectorStatus {
    if (![[self runtimeValueForKey:@"tweakLoaded"] boolValue]) return @"Unknown until injected";
    return [[self runtimeValueForKey:@"simulateLockSelectorPresent"] boolValue]
        ? @"_simulateLockButtonPress available"
        : @"Primary selector missing; fallbacks enabled";
}

- (NSString *)lastTapStatus {
    id tapValue = [self runtimeValueForKey:@"lastTapCount"];
    if (!tapValue) return @"No SBIconListView tap recorded";
    NSString *viewClass = [self runtimeValueForKey:@"lastTouchClass"] ?: @"Unknown view";
    return [NSString stringWithFormat:@"%@ tap(s) · %@",
            tapValue,
            viewClass];
}

- (NSString *)testCommandStatus {
    if (![[self runtimeValueForKey:@"testCommandReceived"] boolValue]) {
        return @"Not received by SpringBoard";
    }
    return [NSString stringWithFormat:@"Received at %@",
            [self formattedTimeForValue:[self runtimeValueForKey:@"testCommandReceivedAt"]]];
}

- (NSString *)lastLockStatus {
    NSString *source = [self runtimeValueForKey:@"lastLockSource"];
    NSString *route = [self runtimeValueForKey:@"lastLockRoute"];
    if (!source.length && !route.length) return @"No lock request recorded";
    return [NSString stringWithFormat:@"%@ · %@",
            source ?: @"Unknown source",
            route ?: @"Unknown route"];
}

- (void)testLock {
    [self setRuntimeValue:@NO forKey:@"testCommandReceived"];
    [self setRuntimeValue:@([NSDate date].timeIntervalSince1970) forKey:@"lastSettingsCommandSentAt"];

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         NHLTestLockNotification,
                                         NULL,
                                         NULL,
                                         true);
    [self reloadSpecifiers];
}

- (void)refreshStatus {
    CFPreferencesAppSynchronize(NHLRuntimeDomain);
    [self reloadSpecifiers];
}

@end
