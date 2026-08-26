#import "PARootListController.h"
#import <Preferences/PSSpecifier.h>
#import <QuartzCore/QuartzCore.h>
#import <spawn.h>

extern char **environ;
static NSString * const PADomain = @"com.zeshan.phoneaura";
static NSString * const PANotification = @"com.zeshan.phoneaura/preferences.changed";

@implementation PARootListController

- (PSSpecifier *)groupNamed:(NSString *)name footer:(NSString *)footer {
    PSSpecifier *specifier = [PSSpecifier groupSpecifierWithName:name];
    if (footer.length) [specifier setProperty:footer forKey:@"footerText"];
    return specifier;
}

- (PSSpecifier *)switchNamed:(NSString *)name key:(NSString *)key defaultValue:(BOOL)defaultValue {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
                                                             target:self
                                                                set:@selector(setPreferenceValue:specifier:)
                                                                get:@selector(readPreferenceValue:)
                                                             detail:nil
                                                               cell:PSSwitchCell
                                                               edit:nil];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:@(defaultValue) forKey:@"default"];
    return specifier;
}

- (PSSpecifier *)sliderNamed:(NSString *)name
                         key:(NSString *)key
                defaultValue:(CGFloat)defaultValue
                         min:(CGFloat)minimum
                         max:(CGFloat)maximum {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
                                                             target:self
                                                                set:@selector(setPreferenceValue:specifier:)
                                                                get:@selector(readPreferenceValue:)
                                                             detail:nil
                                                               cell:PSSliderCell
                                                               edit:nil];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:@(defaultValue) forKey:@"default"];
    [specifier setProperty:@(minimum) forKey:@"min"];
    [specifier setProperty:@(maximum) forKey:@"max"];
    [specifier setProperty:@YES forKey:@"showValue"];
    return specifier;
}

- (PSSpecifier *)buttonNamed:(NSString *)name action:(SEL)action destructive:(BOOL)destructive {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
                                                             target:self
                                                                set:nil
                                                                get:nil
                                                             detail:nil
                                                               cell:PSButtonCell
                                                               edit:nil];
    [specifier setButtonAction:action];
    if (destructive) [specifier setProperty:@YES forKey:@"isDestructive"];
    return specifier;
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;

    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[self groupNamed:@"PHONEAURA 0.4.3"
                                footer:@"RootHide configuration is generated directly by the preference controller. Changes apply after the Phone app is restarted."]];
    [items addObject:[self buttonNamed:@"Open PhoneAura Studio" action:@selector(openStudioApp) destructive:NO]];
    [items addObject:[self switchNamed:@"Enable PhoneAura" key:@"enabled" defaultValue:YES]];

    [items addObject:[self groupNamed:@"CUSTOM PHONE SCREENS"
                                footer:@"When a screen is disabled, PhoneAura restores Apple’s complete stock screen instead of mixing the two interfaces."]];
    [items addObject:[self switchNamed:@"Replace Favorites" key:@"fullFavorites" defaultValue:YES]];
    [items addObject:[self switchNamed:@"Replace Recents" key:@"fullRecents" defaultValue:YES]];
    [items addObject:[self switchNamed:@"Replace Contacts" key:@"fullContacts" defaultValue:YES]];
    [items addObject:[self switchNamed:@"Replace Keypad" key:@"fullKeypad" defaultValue:YES]];

    [items addObject:[self groupNamed:@"APPEARANCE" footer:nil]];
    [items addObject:[self switchNamed:@"Header Subtitles" key:@"showSubtitles" defaultValue:YES]];
    [items addObject:[self sliderNamed:@"Card Opacity" key:@"cardOpacity" defaultValue:0.96 min:0.65 max:1.0]];
    [items addObject:[self sliderNamed:@"Corner Radius" key:@"cornerRadius" defaultValue:16.0 min:10.0 max:26.0]];

    [items addObject:[self groupNamed:@"BEHAVIOR"
                                footer:@"Use Restart Phone App after changing complete screens. Favorite contacts are selected in PhoneAura Studio."]];
    [items addObject:[self switchNamed:@"Haptic Feedback" key:@"haptics" defaultValue:YES]];
    [items addObject:[self switchNamed:@"Fluid Animations" key:@"animations" defaultValue:YES]];
    [items addObject:[self buttonNamed:@"Restart Phone App" action:@selector(restartPhoneApp) destructive:NO]];
    [items addObject:[self buttonNamed:@"Reset PhoneAura Settings" action:@selector(resetPreferences) destructive:YES]];

    _specifiers = [items copy];
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PhoneAura";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 142)];
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[(id)[UIColor colorWithRed:1.0 green:0.35 blue:0.37 alpha:1].CGColor,
                        (id)[UIColor colorWithRed:0.42 green:0.38 blue:1.0 alpha:1].CGColor,
                        (id)[UIColor colorWithRed:0.05 green:0.78 blue:0.72 alpha:1].CGColor];
    gradient.startPoint = CGPointMake(0, 0.5);
    gradient.endPoint = CGPointMake(1, 0.5);
    gradient.frame = CGRectMake(18, 14, UIScreen.mainScreen.bounds.size.width - 54, 108);
    gradient.cornerRadius = 24;
    [header.layer addSublayer:gradient];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(38, 31, UIScreen.mainScreen.bounds.size.width - 120, 38)];
    title.text = @"PhoneAura 0.4.3";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:29 weight:UIFontWeightBold];
    [header addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(39, 71, UIScreen.mainScreen.bounds.size.width - 120, 25)];
    subtitle.text = @"RootHide controls · isolated screens";
    subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    subtitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [header addSubview:subtitle];

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(UIScreen.mainScreen.bounds.size.width - 102, 42, 46, 46)];
    icon.image = [UIImage systemImageNamed:@"phone.fill"];
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [header addSubview:icon];
    self.table.tableHeaderView = header;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return nil;
    CFPreferencesAppSynchronize((__bridge CFStringRef)PADomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                           (__bridge CFStringRef)PADomain));
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)PADomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PADomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)PANotification,
                                         NULL,
                                         NULL,
                                         true);
}

- (void)openStudioApp {
    NSURL *url = [NSURL URLWithString:@"phoneaurastudio://settings"];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)resetPreferences {
    NSArray *keys = @[@"enabled", @"fullFavorites", @"fullRecents", @"fullContacts", @"fullKeypad",
                      @"haptics", @"animations", @"showSubtitles", @"cardOpacity", @"cornerRadius", @"favoriteIdentifiers"];
    for (NSString *key in keys) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)PADomain);
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)PADomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)PANotification,
                                         NULL,
                                         NULL,
                                         true);
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)restartPhoneApp {
    pid_t pid = 0;
    const char *arguments[] = {"killall", "-9", "MobilePhone", NULL};
    posix_spawnp(&pid, "killall", NULL, NULL, (char * const *)arguments, environ);
}

@end
