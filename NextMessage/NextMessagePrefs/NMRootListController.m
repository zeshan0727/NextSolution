#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

static NSString * const NMPrefsDomain = @"com.nextsolution.nextmessage";
static CFStringRef const NMPrefsChangedNotification = CFSTR("com.nextsolution.nextmessage/preferences.changed");

@interface NMRootListController : PSListController
@end

@implementation NMRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Next Message";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    [self buildHeader];
}

- (void)buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 154)];

    UIView *iconBackground = [UIView new];
    iconBackground.translatesAutoresizingMaskIntoConstraints = NO;
    iconBackground.backgroundColor = [UIColor colorWithRed:0.58 green:0.45 blue:1.0 alpha:1.0];
    iconBackground.layer.cornerRadius = 22.0;
    iconBackground.layer.cornerCurve = kCACornerCurveContinuous;
    iconBackground.layer.shadowColor = [UIColor colorWithRed:0.55 green:0.42 blue:1.0 alpha:1.0].CGColor;
    iconBackground.layer.shadowOpacity = 0.30;
    iconBackground.layer.shadowRadius = 14.0;
    iconBackground.layer.shadowOffset = CGSizeMake(0, 6);
    [header addSubview:iconBackground];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"message.fill"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.whiteColor;
    icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:29 weight:UIImageSymbolWeightSemibold];
    [iconBackground addSubview:icon];

    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"Next Message";
    titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [header addSubview:titleLabel];

    UILabel *subtitleLabel = [UILabel new];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = @"A calmer, cleaner Messages experience";
    subtitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    subtitleLabel.textColor = UIColor.secondaryLabelColor;
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    [header addSubview:subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [iconBackground.topAnchor constraintEqualToAnchor:header.topAnchor constant:12],
        [iconBackground.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [iconBackground.widthAnchor constraintEqualToConstant:64],
        [iconBackground.heightAnchor constraintEqualToConstant:64],

        [icon.centerXAnchor constraintEqualToAnchor:iconBackground.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:iconBackground.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:34],
        [icon.heightAnchor constraintEqualToConstant:34],

        [titleLabel.topAnchor constraintEqualToAnchor:iconBackground.bottomAnchor constant:12],
        [titleLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [titleLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],

        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
    ]];

    UITableView *tableView = [self valueForKey:@"table"];
    if ([tableView isKindOfClass:UITableView.class]) {
        tableView.tableHeaderView = header;
    }
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    CFPreferencesAppSynchronize((__bridge CFStringRef)NMPrefsDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), NMPrefsChangedNotification, NULL, NULL, true);
}

- (void)resetPreferences {
    NSArray<NSString *> *keys = @[
        @"Enabled",
        @"AppearanceMode",
        @"RedesignInbox",
        @"RedesignConversation",
        @"EnableToasts",
        @"EnableInfoAction",
        @"EnableDeleteAction",
    ];

    for (NSString *key in keys) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)NMPrefsDomain);
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)NMPrefsDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), NMPrefsChangedNotification, NULL, NULL, true);
    [self reloadSpecifiers];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Next Message" message:@"Preferences were reset to their defaults." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
