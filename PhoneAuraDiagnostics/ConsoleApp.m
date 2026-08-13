#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString * const PAStatusPath = @"/var/mobile/Library/Preferences/com.zeshan.phoneaura.diagnostics.plist";
static NSString * const PALogDirectory = @"/var/mobile/Library/Logs/PhoneAura";
static NSString * const PALogPath = @"/var/mobile/Library/Logs/PhoneAura/PhoneAuraDiagnostics.log";

static NSString *PAString(id value) {
    if (!value || value == NSNull.null) return @"—";
    if ([value isKindOfClass:NSString.class]) return value;
    return [value description];
}

@interface PAConsoleViewController : UIViewController
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UILabel *runningValue;
@property (nonatomic, strong) UILabel *versionValue;
@property (nonatomic, strong) UILabel *processValue;
@property (nonatomic, strong) UILabel *environmentValue;
@property (nonatomic, strong) UILabel *baseRuntimeValue;
@property (nonatomic, strong) UILabel *oldHookValue;
@property (nonatomic, strong) UILabel *heartbeatValue;
@property (nonatomic, strong) UILabel *screenValue;
@property (nonatomic, strong) UILabel *commandValue;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation PAConsoleViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PhoneAura Console";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self buildUI];
    [self refreshConsole];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refreshConsole) userInfo:nil repeats:YES];
}

- (void)dealloc {
    [self.timer invalidate];
}

- (UILabel *)valueLabel {
    UILabel *label = [UILabel new];
    label.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = UIColor.labelColor;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentRight;
    return label;
}

- (UIView *)cardWithTitle:(NSString *)title content:(UIView *)content {
    UIView *card = [UIView new];
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 16;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *header = [UILabel new];
    header.text = title;
    header.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];

    UIStackView *inner = [[UIStackView alloc] initWithArrangedSubviews:@[header, content]];
    inner.axis = UILayoutConstraintAxisVertical;
    inner.spacing = 10;
    inner.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:inner];
    [NSLayoutConstraint activateConstraints:@[
        [inner.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [inner.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [inner.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [inner.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14]
    ]];
    return card;
}

- (UIView *)statusRows {
    UIStackView *rows = [UIStackView new];
    rows.axis = UILayoutConstraintAxisVertical;
    rows.spacing = 8;
    NSArray *titles = @[@"Running", @"Version", @"Process", @"Environment", @"Base PhoneAura", @"Old 0.5.0 Hook", @"Heartbeat", @"Current Screen", @"Last Command"];
    self.runningValue = [self valueLabel];
    self.versionValue = [self valueLabel];
    self.processValue = [self valueLabel];
    self.environmentValue = [self valueLabel];
    self.baseRuntimeValue = [self valueLabel];
    self.oldHookValue = [self valueLabel];
    self.heartbeatValue = [self valueLabel];
    self.screenValue = [self valueLabel];
    self.commandValue = [self valueLabel];
    NSArray *values = @[self.runningValue, self.versionValue, self.processValue, self.environmentValue, self.baseRuntimeValue, self.oldHookValue, self.heartbeatValue, self.screenValue, self.commandValue];
    [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger idx, BOOL *stop) {
        UILabel *key = [UILabel new];
        key.text = title;
        key.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        key.textColor = UIColor.secondaryLabelColor;
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[key, values[idx]]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentFirstBaseline;
        row.distribution = UIStackViewDistributionFill;
        [key setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [rows addArrangedSubview:row];
    }];
    return rows;
}

- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    button.backgroundColor = UIColor.tertiarySystemFillColor;
    button.layer.cornerRadius = 12;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.contentEdgeInsets = UIEdgeInsetsMake(11, 12, 11, 12);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)buildUI {
    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    self.stack = [UIStackView new];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 12;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:14],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-14],
        [self.stack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:14],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-24],
        [self.stack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-28]
    ]];

    UILabel *intro = [UILabel new];
    intro.text = @"Diagnostic build: keep this console available, open PhoneAura, reproduce one broken feature, then return here and tap that feature test. The report records what loaded and what did not.";
    intro.font = [UIFont systemFontOfSize:13];
    intro.textColor = UIColor.secondaryLabelColor;
    intro.numberOfLines = 0;
    [self.stack addArrangedSubview:[self cardWithTitle:@"How to diagnose" content:intro]];
    [self.stack addArrangedSubview:[self cardWithTitle:@"Runtime Status" content:[self statusRows]]];

    UIStackView *mainActions = [UIStackView new];
    mainActions.axis = UILayoutConstraintAxisVertical;
    mainActions.spacing = 8;
    [mainActions addArrangedSubview:[self button:@"Run Full Diagnosis" action:@selector(runFull)]];
    [mainActions addArrangedSubview:[self button:@"Snapshot Current Phone UI" action:@selector(runSnapshot)]];
    [mainActions addArrangedSubview:[self button:@"Import Latest MobilePhone Crash" action:@selector(importCrash)]];
    [self.stack addArrangedSubview:[self cardWithTitle:@"Diagnosis" content:mainActions]];

    UIStackView *features = [UIStackView new];
    features.axis = UILayoutConstraintAxisVertical;
    features.spacing = 8;
    [features addArrangedSubview:[self button:@"Test Favorites" action:@selector(testFavorites)]];
    [features addArrangedSubview:[self button:@"Test Recents" action:@selector(testRecents)]];
    [features addArrangedSubview:[self button:@"Test Contacts + Accounts" action:@selector(testContacts)]];
    [features addArrangedSubview:[self button:@"Test Keypad" action:@selector(testKeypad)]];
    [features addArrangedSubview:[self button:@"Test Voicemail / System Tab" action:@selector(testVoicemail)]];
    [self.stack addArrangedSubview:[self cardWithTitle:@"Feature Tests" content:features]];

    self.logView = [UITextView new];
    self.logView.editable = NO;
    self.logView.selectable = YES;
    self.logView.scrollEnabled = YES;
    self.logView.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
    self.logView.backgroundColor = UIColor.systemBackgroundColor;
    self.logView.layer.cornerRadius = 10;
    self.logView.layer.borderWidth = 0.5;
    self.logView.layer.borderColor = UIColor.separatorColor.CGColor;
    [self.logView.heightAnchor constraintEqualToConstant:360].active = YES;
    [self.stack addArrangedSubview:[self cardWithTitle:@"Live Diagnostic Log" content:self.logView]];

    UIStackView *logActions = [UIStackView new];
    logActions.axis = UILayoutConstraintAxisVertical;
    logActions.spacing = 8;
    [logActions addArrangedSubview:[self button:@"Copy Log" action:@selector(copyLog)]];
    [logActions addArrangedSubview:[self button:@"Share Log" action:@selector(shareLog)]];
    [logActions addArrangedSubview:[self button:@"Clear Log" action:@selector(clearLog)]];
    [self.stack addArrangedSubview:[self cardWithTitle:@"Log Actions" content:logActions]];
}

- (void)postCommand:(NSString *)suffix {
    NSString *name = [@"com.zeshan.phoneaura.diag.command." stringByAppendingString:suffix];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)name,
                                         NULL, NULL, true);
    [self refreshConsole];
}

- (void)runFull { [self postCommand:@"full"]; }
- (void)runSnapshot { [self postCommand:@"snapshot"]; }
- (void)testFavorites { [self postCommand:@"favorites"]; }
- (void)testRecents { [self postCommand:@"recents"]; }
- (void)testContacts { [self postCommand:@"contacts"]; }
- (void)testKeypad { [self postCommand:@"keypad"]; }
- (void)testVoicemail { [self postCommand:@"voicemail"]; }

- (NSString *)currentLog {
    NSString *log = [NSString stringWithContentsOfFile:PALogPath encoding:NSUTF8StringEncoding error:nil];
    return log ?: @"No diagnostic log yet. Open the Phone app once after installing this build.";
}

- (void)refreshConsole {
    NSDictionary *status = [NSDictionary dictionaryWithContentsOfFile:PAStatusPath] ?: @{};
    NSTimeInterval heartbeat = [status[@"heartbeatEpoch"] doubleValue];
    NSTimeInterval age = heartbeat > 0 ? [[NSDate date] timeIntervalSince1970] - heartbeat : DBL_MAX;
    BOOL running = age <= 12.0;
    self.runningValue.text = running ? @"YES" : @"NO";
    self.runningValue.textColor = running ? UIColor.systemGreenColor : UIColor.systemRedColor;
    self.versionValue.text = PAString(status[@"diagnosticVersion"]);
    self.processValue.text = [NSString stringWithFormat:@"%@ (%@)", PAString(status[@"process"]), PAString(status[@"pid"])];
    self.environmentValue.text = PAString(status[@"environment"]);
    self.baseRuntimeValue.text = [status[@"baseRuntimeLoaded"] boolValue] ? @"LOADED" : @"NOT LOADED";
    self.baseRuntimeValue.textColor = [status[@"baseRuntimeLoaded"] boolValue] ? UIColor.systemGreenColor : UIColor.systemRedColor;
    self.oldHookValue.text = [status[@"oldNativeFeatureLoaded"] boolValue] ? @"STILL LOADED" : @"NOT LOADED";
    self.oldHookValue.textColor = [status[@"oldNativeFeatureLoaded"] boolValue] ? UIColor.systemOrangeColor : UIColor.systemGreenColor;
    self.heartbeatValue.text = heartbeat > 0 ? [NSString stringWithFormat:@"%@ (%.0fs ago)", PAString(status[@"heartbeat"]), MAX(age, 0)] : @"Never";
    self.screenValue.text = PAString(status[@"topController"]);
    self.commandValue.text = PAString(status[@"lastCommand"]);

    NSString *newLog = [self currentLog];
    if (![self.logView.text isEqualToString:newLog]) {
        BOOL nearBottom = self.logView.contentOffset.y + self.logView.bounds.size.height >= self.logView.contentSize.height - 50;
        self.logView.text = newLog;
        if (nearBottom && newLog.length) {
            [self.logView scrollRangeToVisible:NSMakeRange(newLog.length - 1, 1)];
        }
    }
}

- (void)copyLog {
    UIPasteboard.generalPasteboard.string = [self currentLog];
    [self showMessage:@"Copied" body:@"The complete PhoneAura diagnostic log is on the clipboard."];
}

- (void)shareLog {
    [[NSFileManager defaultManager] createDirectoryAtPath:PALogDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    if (![[NSFileManager defaultManager] fileExistsAtPath:PALogPath]) {
        [[self currentLog] writeToFile:PALogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:PALogPath]] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.view;
    share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMaxY(self.view.bounds) - 40, 1, 1);
    [self presentViewController:share animated:YES completion:nil];
}

- (void)clearLog {
    [[NSFileManager defaultManager] removeItemAtPath:PALogPath error:nil];
    [self postCommand:@"clear"];
    self.logView.text = @"Log cleared. Reproduce the issue, then run the matching feature test.";
}

- (NSArray<NSString *> *)crashDirectories {
    return @[@"/var/mobile/Library/Logs/CrashReporter",
             @"/var/mobile/Library/Logs/CrashReporter/Retired",
             @"/var/mobile/Library/Logs/CrashReporter/DiagnosticLogs"];
}

- (void)importCrash {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *bestPath = nil;
    NSDate *bestDate = nil;
    for (NSString *directory in [self crashDirectories]) {
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:directory];
        for (NSString *relative in enumerator) {
            NSString *lower = relative.lowercaseString;
            if (!([lower containsString:@"mobilephone"] || [lower containsString:@"phoneaura"])) continue;
            if (!([lower hasSuffix:@".ips"] || [lower hasSuffix:@".crash"] || [lower hasSuffix:@".log"])) continue;
            NSString *path = [directory stringByAppendingPathComponent:relative];
            NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
            NSDate *date = attrs[NSFileModificationDate];
            if (!bestDate || [date compare:bestDate] == NSOrderedDescending) {
                bestDate = date;
                bestPath = path;
            }
        }
    }
    if (!bestPath) {
        [self showMessage:@"No crash log found" body:@"The console could not find a MobilePhone/PhoneAura .ips or .crash file in the usual CrashReporter folders."];
        return;
    }
    NSData *data = [NSData dataWithContentsOfFile:bestPath];
    if (!data.length) {
        [self showMessage:@"Crash log unreadable" body:bestPath];
        return;
    }
    NSUInteger maxBytes = 180 * 1024;
    if (data.length > maxBytes) data = [data subdataWithRange:NSMakeRange(data.length - maxBytes, maxBytes)];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"<binary/unreadable crash log>";
    NSString *block = [NSString stringWithFormat:@"\n[%@] [INFO] [CRASH-IMPORT] source=%@ modified=%@\n%@\n[END CRASH IMPORT]\n",
                       [NSDate date], bestPath, bestDate ?: [NSDate date], text];
    [[NSFileManager defaultManager] createDirectoryAtPath:PALogDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    if (![fm fileExistsAtPath:PALogPath]) [@"" writeToFile:PALogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:PALogPath];
    [handle seekToEndOfFile];
    [handle writeData:[block dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
    [self refreshConsole];
    [self showMessage:@"Crash imported" body:[NSString stringWithFormat:@"Added the latest crash log to the report:\n%@", bestPath.lastPathComponent]];
}

- (void)showMessage:(NSString *)title body:(NSString *)body {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

@interface PAConsoleAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation PAConsoleAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    PAConsoleViewController *root = [PAConsoleViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(PAConsoleAppDelegate.class));
    }
}
