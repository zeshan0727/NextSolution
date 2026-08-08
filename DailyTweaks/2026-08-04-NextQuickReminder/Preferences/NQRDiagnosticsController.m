#import "NQRDiagnosticsController.h"
#import <UIKit/UIKit.h>

static CFStringRef const NQRDomain = CFSTR("com.nextsolution.nextquickreminder");
static CFStringRef const NQRShowPanel = CFSTR("com.nextsolution.nextquickreminder.showpanel");

@interface NQRDiagnosticsController ()
@property(nonatomic,strong) UITextView *textView;
@end

@implementation NQRDiagnosticsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Quick Reminder Diagnostics";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.textView = [UITextView new];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.alwaysBounceVertical = YES;
    self.textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.textView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.textView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    self.textView.layer.cornerRadius = 12;
    [self.view addSubview:self.textView];

    [NSLayoutConstraint activateConstraints:@[
        [self.textView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
    ]];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
        target:self
        action:@selector(refreshLog)];

    UIBarButtonItem *test = [[UIBarButtonItem alloc] initWithTitle:@"Test Panel" style:UIBarButtonItemStylePlain target:self action:@selector(testPanel)];
    UIBarButtonItem *copy = [[UIBarButtonItem alloc] initWithTitle:@"Copy" style:UIBarButtonItemStylePlain target:self action:@selector(copyLog)];
    UIBarButtonItem *flex1 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *clear = [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain target:self action:@selector(clearLog)];
    self.toolbarItems = @[test, flex1, copy, clear];
    [self refreshLog];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:NO animated:animated];
    [self refreshLog];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setToolbarHidden:YES animated:animated];
}

- (NSString *)logPath {
    NSString *home = NSHomeDirectory();
    if (![home containsString:@"/var/mobile"]) home = @"/var/mobile";
    return [home stringByAppendingPathComponent:@"Library/Logs/NextQuickReminder.log"];
}

- (NSString *)selectedGesture {
    CFPreferencesAppSynchronize(NQRDomain);
    NSString *gesture = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("gesture"), NQRDomain));
    if (![gesture isKindOfClass:NSString.class] || !gesture.length) gesture = @"statusbar";
    NSDictionary *names = @{
        @"off": @"Off",
        @"statusbar": @"Double-tap status-bar time",
        @"shake": @"Shake device",
        @"volume": @"Hold Volume Up",
    };
    return names[gesture] ?: gesture;
}

- (void)refreshLog {
    NSString *path = [self logPath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length > 160 * 1024) {
        data = [data subdataWithRange:NSMakeRange(data.length - 160 * 1024, 160 * 1024)];
    }
    NSString *log = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"No diagnostic entries yet.";
    NSString *header = [NSString stringWithFormat:
        @"Next Quick Reminder 1.0.0\nSelected gesture: %@\nLog path: %@\n\n%@",
        [self selectedGesture],
        path,
        log ?: @"The log file could not be decoded."
    ];
    self.textView.text = header;
    if (self.textView.text.length) {
        NSRange bottom = NSMakeRange(self.textView.text.length - 1, 1);
        [self.textView scrollRangeToVisible:bottom];
    }
}

- (void)testPanel {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NQRShowPanel,
        NULL,
        NULL,
        true
    );
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshLog];
    });
}

- (void)copyLog {
    UIPasteboard.generalPasteboard.string = self.textView.text ?: @"";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Copied"
        message:@"Diagnostic information was copied to the clipboard."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearLog {
    NSString *path = [self logPath];
    [[NSData data] writeToFile:path atomically:YES];
    [self refreshLog];
}

@end
