#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

static NSString * const NMPrefsDomain = @"com.nextsolution.nextmessage";
static NSString * const NMDiagnosticPath = @"/var/mobile/Library/Preferences/com.nextsolution.nextmessage.diagnostic.txt";
static CFStringRef const NMPrefsChangedNotification = CFSTR("com.nextsolution.nextmessage/preferences.changed");
static CFStringRef const NMCaptureNotification = CFSTR("com.nextsolution.nextmessage.capturediagnostic");
static CFStringRef const NMClearNotification = CFSTR("com.nextsolution.nextmessage.cleardiagnostic");

@interface NMRootListController : PSListController
@end

@implementation NMRootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Next Message";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    [self buildHeader];
}

- (void)buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 158)];

    UIView *iconBackground = [UIView new];
    iconBackground.translatesAutoresizingMaskIntoConstraints = NO;
    iconBackground.backgroundColor = [UIColor colorWithRed:0.45 green:0.35 blue:1.0 alpha:1.0];
    iconBackground.layer.cornerRadius = 22.0;
    iconBackground.layer.cornerCurve = kCACornerCurveContinuous;
    iconBackground.layer.shadowColor = [UIColor colorWithRed:0.35 green:0.48 blue:1.0 alpha:1.0].CGColor;
    iconBackground.layer.shadowOpacity = 0.32;
    iconBackground.layer.shadowRadius = 15.0;
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
    subtitleLabel.text = @"v0.2.1 — iOS 16 diagnostic build";
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
    if ([tableView isKindOfClass:UITableView.class]) tableView.tableHeaderView = header;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    CFPreferencesAppSynchronize((__bridge CFStringRef)NMPrefsDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), NMPrefsChangedNotification, NULL, NULL, true);
}

- (void)showTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)diagnosticReport {
    NSError *error = nil;
    NSString *report = [NSString stringWithContentsOfFile:NMDiagnosticPath encoding:NSUTF8StringEncoding error:&error];
    return report.length > 0 ? report : nil;
}

- (void)captureDiagnostic {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), NMCaptureNotification, NULL, NULL, true);
    [self showTitle:@"Capture Requested"
            message:@"For the best report, first open the Messages inbox, open one conversation, return to the inbox, and then come back here. Next Message also captures each Messages screen automatically. Wait three seconds, then use Share Last Report."];
}

- (void)copyDiagnostic {
    NSString *report = [self diagnosticReport];
    if (!report) {
        [self showTitle:@"No Report Yet"
                message:@"Open Messages and visit the inbox and one conversation. Return here after a few seconds, then try again."];
        return;
    }
    UIPasteboard.generalPasteboard.string = report;
    [self showTitle:@"Report Copied"
            message:@"The privacy-safe report is on the clipboard. Paste it into the ChatGPT conversation."];
}

- (void)shareDiagnostic {
    NSString *report = [self diagnosticReport];
    if (!report) {
        [self showTitle:@"No Report Yet"
                message:@"Open Messages and visit the inbox and one conversation. Return here after a few seconds, then try again."];
        return;
    }

    NSString *temporaryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"NextMessage-Diagnostic-v0.2.1.txt"];
    [report writeToFile:temporaryPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSURL *fileURL = [NSURL fileURLWithPath:temporaryPath];
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    if (activity.popoverPresentationController) {
        activity.popoverPresentationController.sourceView = self.view;
        activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    }
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)clearDiagnostic {
    [NSFileManager.defaultManager removeItemAtPath:NMDiagnosticPath error:nil];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), NMClearNotification, NULL, NULL, true);
    [self showTitle:@"Report Cleared" message:@"Open Messages again to generate a fresh diagnostic report."];
}

- (void)resetPreferences {
    NSArray<NSString *> *keys = @[
        @"Enabled", @"AppearanceMode", @"RedesignInbox", @"RedesignConversation",
        @"EnableAuroraBackground", @"EnableConceptHeader", @"EnableBottomDock",
        @"EnableSmartReplies", @"EnableToasts", @"EnableInfoAction", @"EnableDeleteAction"
    ];
    for (NSString *key in keys) CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)NMPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)NMPrefsDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), NMPrefsChangedNotification, NULL, NULL, true);
    [self reloadSpecifiers];
    [self showTitle:@"Next Message" message:@"Preferences were reset to their defaults."];
}

@end
