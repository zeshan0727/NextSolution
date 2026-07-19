#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@interface PSListController : UIViewController
@property(nonatomic, retain) NSArray *specifiers;
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifiers;
@end

@interface DLRootListController : PSListController {
    NSArray *_dlSpecifiers;
}
@end

@implementation DLRootListController

- (NSArray *)specifiers {
    if (!_dlSpecifiers) _dlSpecifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _dlSpecifiers;
}

- (NSString *)preferencesPath {
    return @"/var/mobile/Library/Preferences/com.nextsolution.dailyledger.smsimport.plist";
}

- (NSMutableDictionary *)preferences {
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:self.preferencesPath];
    return stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
}

- (id)readPreferenceValue:(id)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id fallback = [specifier propertyForKey:@"default"];
    return [self preferences][key] ?: fallback;
}

- (void)setPreferenceValue:(id)value specifier:(id)specifier {
    NSMutableDictionary *preferences = [self preferences];
    NSString *key = [specifier propertyForKey:@"key"];
    if (key) preferences[key] = value;
    [preferences writeToFile:self.preferencesPath atomically:YES];
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.nextsolution.dailyledger.smsimport.preferences-changed"),
        NULL, NULL, true
    );
}

- (void)requestScan {
    NSMutableDictionary *preferences = [self preferences];
    preferences[@"scanRequestID"] = @([preferences[@"scanRequestID"] integerValue] + 1);
    preferences[@"lastResult"] = @"Manual scan requested. Reopen this pane after five seconds.";
    [preferences writeToFile:self.preferencesPath atomically:YES];
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.nextsolution.dailyledger.smsimport.preferences-changed"),
        NULL, NULL, true
    );
    [self reloadSpecifiers];
}

- (NSString *)statusText {
    NSDictionary *preferences = [self preferences];
    if (![preferences[@"tweakLoaded"] boolValue]) return @"Not loaded in SpringBoard yet";
    return preferences[@"lastResult"] ?: @"Loaded; waiting for an SMS or manual scan";
}

@end
