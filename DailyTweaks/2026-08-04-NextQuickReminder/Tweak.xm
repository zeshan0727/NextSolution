#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreMotion/CoreMotion.h>
#import <objc/runtime.h>
#import <substrate.h>

static CFStringRef const NQRDomain = CFSTR("com.nextsolution.nextquickreminder");
static CFStringRef const NQRPreferencesChanged = CFSTR("com.nextsolution.nextquickreminder.preferences.changed");
static CFStringRef const NQRShowPanelNotification = CFSTR("com.nextsolution.nextquickreminder.showpanel");

static NSString *NQRSelectedGesture = @"statusbar";
static BOOL NQRDiagnosticLogging = YES;
static UIWindow *NQRStatusGestureWindow = nil;
static UIWindow *NQRPanelWindow = nil;
static __weak UIWindow *NQRPreviousKeyWindow = nil;
static CMMotionManager *NQRMotionManager = nil;
static NSTimeInterval NQRLastTriggerUptime = 0;
static NSInteger NQRShakeSpikeCount = 0;
static NSTimeInterval NQRLastShakeSpikeUptime = 0;
static NSInteger NQRVolumePulseCount = 0;
static NSTimeInterval NQRVolumeSequenceStart = 0;
static NSTimeInterval NQRLastVolumePulse = 0;
static dispatch_queue_t NQRLogQueue;

static NSString *NQRLogPath(void) {
    NSString *home = NSHomeDirectory();
    if (![home containsString:@"/var/mobile"]) home = @"/var/mobile";
    return [home stringByAppendingPathComponent:@"Library/Logs/NextQuickReminder.log"];
}

static void NQRLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void NQRLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[NextQuickReminder] %@", message);
    if (!NQRDiagnosticLogging || !message.length) return;

    NSString *line = [NSString stringWithFormat:@"%@ | %@\n", [NSDate date].descriptionWithLocale, message];
    dispatch_async(NQRLogQueue ?: dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            NSString *path = NQRLogPath();
            NSString *directory = [path stringByDeletingLastPathComponent];
            [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];

            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
            if ([attributes fileSize] > 512 * 1024) {
                NSData *existing = [NSData dataWithContentsOfFile:path];
                NSUInteger keep = MIN((NSUInteger)192 * 1024, existing.length);
                NSData *tail = keep ? [existing subdataWithRange:NSMakeRange(existing.length - keep, keep)] : [NSData data];
                [tail writeToFile:path atomically:YES];
            }

            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                [data writeToFile:path atomically:YES];
            } else {
                NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
                [handle seekToEndOfFile];
                [handle writeData:data];
                [handle closeFile];
            }
        }
    });
}

static id NQRCopyPreference(NSString *key) {
    CFPreferencesAppSynchronize(NQRDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, NQRDomain);
    return CFBridgingRelease(value);
}

static void NQRSetPreference(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, NQRDomain);
    CFPreferencesAppSynchronize(NQRDomain);
}

static UIWindowScene *NQRActiveWindowScene(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState != UISceneActivationStateUnattached) {
                return (UIWindowScene *)scene;
            }
        }
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if (window.windowScene) return window.windowScene;
        }
    }
    return nil;
}

static void NQRDismissPanel(void);
static void NQRPresentPanel(NSString *trigger);
static void NQRApplyGestureSelection(void);

@interface NQRStatusTapController : UIViewController
@end

@implementation NQRStatusTapController
- (void)loadView {
    UIView *view = [UIView new];
    view.backgroundColor = UIColor.clearColor;
    view.userInteractionEnabled = YES;
    self.view = view;

    UITapGestureRecognizer *recognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(nqr_doubleTap:)];
    recognizer.numberOfTapsRequired = 2;
    recognizer.numberOfTouchesRequired = 1;
    recognizer.cancelsTouchesInView = YES;
    [view addGestureRecognizer:recognizer];
}

- (void)nqr_doubleTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateRecognized) return;
    NQRLog(@"Status-bar time double tap recognized");
    NQRPresentPanel(@"status-bar time double tap");
}
@end

@interface NQRQuickPanelController : UIViewController <UITextViewDelegate>
@property(nonatomic,strong) UITextField *titleField;
@property(nonatomic,strong) UITextView *notesView;
@property(nonatomic,strong) UILabel *notesPlaceholder;
@property(nonatomic,strong) UIDatePicker *datePicker;
@property(nonatomic,strong) UISwitch *notificationSwitch;
@property(nonatomic,strong) UISwitch *emailSwitch;
@property(nonatomic,strong) UIButton *repeatButton;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,copy) NSString *repeatMode;
@property(nonatomic,copy) NSString *triggerName;
@end

@implementation NQRQuickPanelController

- (instancetype)initWithTrigger:(NSString *)trigger {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _triggerName = [trigger copy] ?: @"unknown";
        _repeatMode = @"never";
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.44];

    UIControl *dismissArea = [UIControl new];
    dismissArea.translatesAutoresizingMaskIntoConstraints = NO;
    [dismissArea addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:dismissArea];
    [NSLayoutConstraint activateConstraints:@[
        [dismissArea.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [dismissArea.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [dismissArea.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [dismissArea.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    card.layer.cornerRadius = 22;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.shadowColor = UIColor.blackColor.CGColor;
    card.layer.shadowOpacity = 0.25;
    card.layer.shadowRadius = 24;
    card.layer.shadowOffset = CGSizeMake(0, 10);
    [self.view addSubview:card];

    UIScrollView *scrollView = [UIScrollView new];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [card addSubview:scrollView];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    [scrollView addSubview:stack];

    UILabel *heading = [UILabel new];
    heading.text = @"Quick Reminder";
    heading.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];

    UILabel *triggerLabel = [UILabel new];
    triggerLabel.text = [NSString stringWithFormat:@"Opened by %@", self.triggerName];
    triggerLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    triggerLabel.textColor = UIColor.secondaryLabelColor;

    self.titleField = [UITextField new];
    self.titleField.borderStyle = UITextBorderStyleRoundedRect;
    self.titleField.placeholder = @"Reminder title";
    self.titleField.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.titleField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.titleField.returnKeyType = UIReturnKeyNext;
    [self.titleField addTarget:self action:@selector(titleSubmitted) forControlEvents:UIControlEventEditingDidEndOnExit];

    UILabel *notesLabel = [self fieldLabel:@"Notes"];
    UIView *notesContainer = [UIView new];
    notesContainer.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    notesContainer.layer.cornerRadius = 10;
    notesContainer.layer.borderWidth = 1;
    notesContainer.layer.borderColor = UIColor.separatorColor.CGColor;

    self.notesView = [UITextView new];
    self.notesView.translatesAutoresizingMaskIntoConstraints = NO;
    self.notesView.backgroundColor = UIColor.clearColor;
    self.notesView.font = [UIFont systemFontOfSize:15];
    self.notesView.delegate = self;
    [notesContainer addSubview:self.notesView];

    self.notesPlaceholder = [UILabel new];
    self.notesPlaceholder.translatesAutoresizingMaskIntoConstraints = NO;
    self.notesPlaceholder.text = @"Optional details";
    self.notesPlaceholder.textColor = UIColor.placeholderTextColor;
    self.notesPlaceholder.font = [UIFont systemFontOfSize:15];
    [notesContainer addSubview:self.notesPlaceholder];

    [NSLayoutConstraint activateConstraints:@[
        [self.notesView.leadingAnchor constraintEqualToAnchor:notesContainer.leadingAnchor constant:8],
        [self.notesView.trailingAnchor constraintEqualToAnchor:notesContainer.trailingAnchor constant:-8],
        [self.notesView.topAnchor constraintEqualToAnchor:notesContainer.topAnchor constant:4],
        [self.notesView.bottomAnchor constraintEqualToAnchor:notesContainer.bottomAnchor constant:-4],
        [self.notesPlaceholder.leadingAnchor constraintEqualToAnchor:self.notesView.leadingAnchor constant:5],
        [self.notesPlaceholder.topAnchor constraintEqualToAnchor:self.notesView.topAnchor constant:8],
        [notesContainer.heightAnchor constraintEqualToConstant:76],
    ]];

    UILabel *dateLabel = [self fieldLabel:@"Reminder date and time"];
    self.datePicker = [UIDatePicker new];
    self.datePicker.datePickerMode = UIDatePickerModeDateAndTime;
    self.datePicker.preferredDatePickerStyle = UIDatePickerStyleCompact;
    self.datePicker.minimumDate = [NSDate dateWithTimeIntervalSinceNow:5];
    self.datePicker.date = [NSDate dateWithTimeIntervalSinceNow:600];
    self.datePicker.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;

    UILabel *repeatLabel = [self fieldLabel:@"Repeat"];
    self.repeatButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.repeatButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.repeatButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.repeatButton.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    self.repeatButton.layer.cornerRadius = 10;
    self.repeatButton.contentEdgeInsets = UIEdgeInsetsMake(12, 12, 12, 12);
    self.repeatButton.showsMenuAsPrimaryAction = YES;

    self.notificationSwitch = [UISwitch new];
    self.notificationSwitch.on = YES;
    UIView *notificationRow = [self switchRow:@"Notification at reminder time" control:self.notificationSwitch];

    self.emailSwitch = [UISwitch new];
    self.emailSwitch.on = NO;
    UIView *emailRow = [self switchRow:@"Send reminder email" control:self.emailSwitch];

    self.statusLabel = [UILabel new];
    self.statusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.statusLabel.textColor = UIColor.systemRedColor;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.hidden = YES;

    UIStackView *buttons = [[UIStackView alloc] init];
    buttons.axis = UILayoutConstraintAxisHorizontal;
    buttons.spacing = 8;
    buttons.distribution = UIStackViewDistributionFillEqually;

    UIButton *cancel = [self actionButton:@"Cancel" color:UIColor.systemGrayColor selector:@selector(cancelTapped)];
    UIButton *draft = [self actionButton:@"Save Draft" color:UIColor.systemBlueColor selector:@selector(saveDraftTapped)];
    UIButton *schedule = [self actionButton:@"Schedule" color:[UIColor colorWithRed:1.0 green:0.43 blue:0 alpha:1] selector:@selector(scheduleTapped)];
    [buttons addArrangedSubview:cancel];
    [buttons addArrangedSubview:draft];
    [buttons addArrangedSubview:schedule];

    [stack addArrangedSubview:heading];
    [stack addArrangedSubview:triggerLabel];
    [stack setCustomSpacing:18 afterView:triggerLabel];
    [stack addArrangedSubview:self.titleField];
    [stack addArrangedSubview:notesLabel];
    [stack addArrangedSubview:notesContainer];
    [stack addArrangedSubview:dateLabel];
    [stack addArrangedSubview:self.datePicker];
    [stack addArrangedSubview:repeatLabel];
    [stack addArrangedSubview:self.repeatButton];
    [stack addArrangedSubview:notificationRow];
    [stack addArrangedSubview:emailRow];
    [stack addArrangedSubview:self.statusLabel];
    [stack addArrangedSubview:buttons];

    UILayoutGuide *frameGuide = scrollView.frameLayoutGuide;
    UILayoutGuide *contentGuide = scrollView.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [card.widthAnchor constraintLessThanOrEqualToConstant:420],
        [card.widthAnchor constraintEqualToAnchor:self.view.widthAnchor constant:-28],
        [card.topAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [card.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [scrollView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:card.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:contentGuide.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:contentGuide.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:contentGuide.topAnchor constant:18],
        [stack.bottomAnchor constraintEqualToAnchor:contentGuide.bottomAnchor constant:-18],
        [stack.widthAnchor constraintEqualToAnchor:frameGuide.widthAnchor constant:-36],
        [buttons.heightAnchor constraintEqualToConstant:46],
    ]];

    [self rebuildRepeatMenu];
    [self loadSavedDraft];

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [center addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (UILabel *)fieldLabel:(NSString *)text {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    label.textColor = UIColor.secondaryLabelColor;
    return label;
}

- (UIView *)switchRow:(NSString *)title control:(UISwitch *)control {
    UIView *row = [UIView new];
    row.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    row.layer.cornerRadius = 10;

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = title;
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    label.numberOfLines = 2;
    control.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];
    [row addSubview:control];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-10],
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.heightAnchor constraintEqualToConstant:52],
    ]];
    return row;
}

- (UIButton *)actionButton:(NSString *)title color:(UIColor *)color selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    button.backgroundColor = color;
    button.layer.cornerRadius = 11;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)rebuildRepeatMenu {
    NSArray<NSDictionary *> *items = @[
        @{@"title": @"No Repeat", @"value": @"never"},
        @{@"title": @"Daily", @"value": @"daily"},
        @{@"title": @"Weekly", @"value": @"weekly"},
        @{@"title": @"Monthly", @"value": @"monthly"},
        @{@"title": @"Yearly", @"value": @"yearly"},
        @{@"title": @"Every 1 Hour", @"value": @"hourly1"},
        @{@"title": @"Every 2 Hours", @"value": @"hourly2"},
        @{@"title": @"Every 3 Hours", @"value": @"hourly3"},
        @{@"title": @"Every 4 Hours", @"value": @"hourly4"},
    ];

    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *item in items) {
        NSString *title = item[@"title"];
        NSString *value = item[@"value"];
        UIAction *action = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
            weakSelf.repeatMode = value;
            [weakSelf rebuildRepeatMenu];
        }];
        action.state = [self.repeatMode isEqualToString:value] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    self.repeatButton.menu = [UIMenu menuWithTitle:@"Repeat" children:actions];
    NSString *selectedTitle = [items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
        return [item[@"value"] isEqualToString:self.repeatMode];
    }]].firstObject[@"title"] ?: @"No Repeat";
    [self.repeatButton setTitle:[NSString stringWithFormat:@"  %@  ▾", selectedTitle] forState:UIControlStateNormal];
}

- (void)loadSavedDraft {
    NSDictionary *draft = NQRCopyPreference(@"draft");
    if (![draft isKindOfClass:NSDictionary.class]) return;
    self.titleField.text = [draft[@"title"] isKindOfClass:NSString.class] ? draft[@"title"] : @"";
    self.notesView.text = [draft[@"notes"] isKindOfClass:NSString.class] ? draft[@"notes"] : @"";
    self.notesPlaceholder.hidden = self.notesView.text.length > 0;
    NSNumber *timestamp = draft[@"dueTimestamp"];
    if ([timestamp isKindOfClass:NSNumber.class]) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue];
        if ([date timeIntervalSinceNow] > 5) self.datePicker.date = date;
    }
    self.notificationSwitch.on = draft[@"notificationsEnabled"] ? [draft[@"notificationsEnabled"] boolValue] : YES;
    self.emailSwitch.on = [draft[@"emailWhenDue"] boolValue];
    NSString *repeat = draft[@"repeatMode"];
    if ([repeat isKindOfClass:NSString.class] && repeat.length) self.repeatMode = repeat;
    [self rebuildRepeatMenu];
    NQRLog(@"Restored saved draft into quick panel");
}

- (NSDictionary *)currentDraftDictionary {
    return @{
        @"title": self.titleField.text ?: @"",
        @"notes": self.notesView.text ?: @"",
        @"dueTimestamp": @(self.datePicker.date.timeIntervalSince1970),
        @"notificationsEnabled": @(self.notificationSwitch.isOn),
        @"emailWhenDue": @(self.emailSwitch.isOn),
        @"repeatMode": self.repeatMode ?: @"never",
    };
}

- (void)titleSubmitted {
    [self.notesView becomeFirstResponder];
}

- (void)textViewDidChange:(UITextView *)textView {
    self.notesPlaceholder.hidden = textView.text.length > 0;
}

- (void)showStatus:(NSString *)message error:(BOOL)isError {
    self.statusLabel.hidden = NO;
    self.statusLabel.text = message;
    self.statusLabel.textColor = isError ? UIColor.systemRedColor : UIColor.systemGreenColor;
}

- (void)cancelTapped {
    NQRLog(@"Quick panel cancelled");
    NQRDismissPanel();
}

- (void)saveDraftTapped {
    NQRSetPreference(@"draft", [self currentDraftDictionary]);
    NQRLog(@"Quick reminder draft saved title=%@", self.titleField.text ?: @"");
    UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
    [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
    NQRDismissPanel();
}

- (void)scheduleTapped {
    NSString *title = [self.titleField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!title.length) {
        [self showStatus:@"Enter a reminder title." error:YES];
        [self.titleField becomeFirstResponder];
        NQRLog(@"Schedule blocked: missing title");
        return;
    }
    if ([self.datePicker.date timeIntervalSinceNow] <= 3) {
        [self showStatus:@"Choose a future reminder date and time." error:YES];
        NQRLog(@"Schedule blocked: date is not in the future");
        return;
    }

    NSString *requestID = NSUUID.UUID.UUIDString;
    NSDictionary *payload = @{
        @"version": @1,
        @"requestID": requestID,
        @"title": title,
        @"notes": self.notesView.text ?: @"",
        @"dueTimestamp": @(self.datePicker.date.timeIntervalSince1970),
        @"notificationsEnabled": @(self.notificationSwitch.isOn),
        @"emailWhenDue": @(self.emailSwitch.isOn),
        @"repeatMode": self.repeatMode ?: @"never",
        @"source": @"NextQuickReminderRootHide",
    };

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
    if (!data || error) {
        [self showStatus:@"Could not prepare the quick reminder." error:YES];
        NQRLog(@"Payload encoding failed: %@", error.localizedDescription);
        return;
    }

    NSString *encoded = [data base64EncodedStringWithOptions:0];
    encoded = [[encoded stringByReplacingOccurrencesOfString:@"+" withString:@"-"] stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    encoded = [encoded stringByReplacingOccurrencesOfString:@"=" withString:@""];
    NSString *urlText = [NSString stringWithFormat:@"nextreminder://quick-add?payload=%@", encoded];
    NSURL *url = [NSURL URLWithString:urlText];
    if (!url) {
        [self showStatus:@"Could not create the Next Reminder link." error:YES];
        NQRLog(@"URL creation failed requestID=%@", requestID);
        return;
    }

    [self.view endEditing:YES];
    [self showStatus:@"Sending to Next Reminder…" error:NO];
    NQRLog(@"Scheduling request %@ title=%@ repeat=%@ notification=%@ email=%@ due=%@", requestID, title, self.repeatMode, self.notificationSwitch.isOn ? @"yes" : @"no", self.emailSwitch.isOn ? @"yes" : @"no", self.datePicker.date);

    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NQRLog(@"Next Reminder URL open result requestID=%@ success=%@", requestID, success ? @"YES" : @"NO");
            if (success) {
                NQRSetPreference(@"draft", nil);
                NQRDismissPanel();
            } else {
                [self showStatus:@"Next Reminder could not be opened. Install or update the app, then retry." error:YES];
            }
        });
    }];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    UIScrollView *scroll = [self.view.subviews.lastObject.subviews.firstObject isKindOfClass:UIScrollView.class]
        ? (UIScrollView *)self.view.subviews.lastObject.subviews.firstObject
        : nil;
    CGRect keyboard = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    if (scroll) scroll.contentInset = UIEdgeInsetsMake(0, 0, keyboard.size.height * 0.35, 0);
}

- (void)keyboardWillHide:(NSNotification *)notification {
    UIScrollView *scroll = [self.view.subviews.lastObject.subviews.firstObject isKindOfClass:UIScrollView.class]
        ? (UIScrollView *)self.view.subviews.lastObject.subviews.firstObject
        : nil;
    if (scroll) scroll.contentInset = UIEdgeInsetsZero;
}
@end

static void NQRDismissPanel(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!NQRPanelWindow) return;
        NQRLog(@"Quick panel dismissed");
        [NQRPanelWindow endEditing:YES];
        NQRPanelWindow.hidden = YES;
        NQRPanelWindow.rootViewController = nil;
        NQRPanelWindow = nil;
        if (NQRPreviousKeyWindow) [NQRPreviousKeyWindow makeKeyWindow];
        NQRPreviousKeyWindow = nil;
    });
}

static void NQRPresentPanel(NSString *trigger) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (NQRPanelWindow || now - NQRLastTriggerUptime < 1.2) {
            NQRLog(@"Trigger ignored because panel is already open or cooldown is active: %@", trigger);
            return;
        }
        NQRLastTriggerUptime = now;
        NQRLog(@"Presenting quick panel from %@ (selected=%@)", trigger, NQRSelectedGesture);

        UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
        [feedback prepare];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];

        NQRPreviousKeyWindow = UIApplication.sharedApplication.keyWindow;
        UIWindowScene *scene = NQRActiveWindowScene();
        if (@available(iOS 13.0, *)) {
            NQRPanelWindow = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        } else {
            NQRPanelWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        }
        NQRPanelWindow.frame = UIScreen.mainScreen.bounds;
        NQRPanelWindow.windowLevel = UIWindowLevelAlert + 3000;
        NQRPanelWindow.backgroundColor = UIColor.clearColor;
        NQRPanelWindow.rootViewController = [[NQRQuickPanelController alloc] initWithTrigger:trigger];
        [NQRPanelWindow makeKeyAndVisible];
        NQRLog(@"Panel window visible scene=%@ frame=%@", scene, NSStringFromCGRect(NQRPanelWindow.frame));
    });
}

static void NQRDestroyStatusGestureWindow(void) {
    if (!NQRStatusGestureWindow) return;
    NQRStatusGestureWindow.hidden = YES;
    NQRStatusGestureWindow.rootViewController = nil;
    NQRStatusGestureWindow = nil;
    NQRLog(@"Status-bar gesture window disabled");
}

static void NQRUpdateStatusGestureFrame(void) {
    if (!NQRStatusGestureWindow) return;
    CGFloat width = UIScreen.mainScreen.bounds.size.width;
    CGFloat statusHeight = 50;
    if (@available(iOS 13.0, *)) {
        UIStatusBarManager *manager = NQRStatusGestureWindow.windowScene.statusBarManager;
        statusHeight = MAX(statusHeight, manager.statusBarFrame.size.height);
    }
    NQRStatusGestureWindow.frame = CGRectMake(0, 0, MIN(128, width * 0.36), statusHeight + 4);
    NQRLog(@"Status-bar gesture frame updated: %@", NSStringFromCGRect(NQRStatusGestureWindow.frame));
}

static void NQREnableStatusGestureWindow(void) {
    if (NQRStatusGestureWindow) {
        NQRUpdateStatusGestureFrame();
        return;
    }
    UIWindowScene *scene = NQRActiveWindowScene();
    if (@available(iOS 13.0, *)) {
        NQRStatusGestureWindow = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:CGRectZero];
    } else {
        NQRStatusGestureWindow = [[UIWindow alloc] initWithFrame:CGRectZero];
    }
    NQRStatusGestureWindow.backgroundColor = UIColor.clearColor;
    NQRStatusGestureWindow.windowLevel = UIWindowLevelStatusBar + 1100;
    NQRStatusGestureWindow.rootViewController = [NQRStatusTapController new];
    NQRStatusGestureWindow.hidden = NO;
    NQRUpdateStatusGestureFrame();
    NQRLog(@"Status-bar time double-tap gesture enabled");
}

static void NQRStopShakeMonitoring(void) {
    if (NQRMotionManager.deviceMotionActive) [NQRMotionManager stopDeviceMotionUpdates];
    NQRMotionManager = nil;
    NQRShakeSpikeCount = 0;
    NQRLog(@"Shake monitoring disabled");
}

static void NQRStartShakeMonitoring(void) {
    NQRStopShakeMonitoring();
    NQRMotionManager = [CMMotionManager new];
    if (!NQRMotionManager.deviceMotionAvailable) {
        NQRLog(@"ERROR: Device motion is not available; shake gesture cannot start");
        return;
    }

    NQRMotionManager.deviceMotionUpdateInterval = 0.05;
    __weak CMMotionManager *weakManager = NQRMotionManager;
    [NQRMotionManager startDeviceMotionUpdatesToQueue:NSOperationQueue.mainQueue withHandler:^(CMDeviceMotion *motion, NSError *error) {
        if (error) {
            NQRLog(@"Motion update error: %@", error.localizedDescription);
            return;
        }
        if (![NQRSelectedGesture isEqualToString:@"shake"] || !weakManager.deviceMotionActive) return;

        CMAcceleration a = motion.userAcceleration;
        CMRotationRate r = motion.rotationRate;
        double acceleration = sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
        double rotation = sqrt(r.x * r.x + r.y * r.y + r.z * r.z);
        if (acceleration < 1.65 || rotation < 2.5) return;

        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (now - NQRLastShakeSpikeUptime > 0.55) NQRShakeSpikeCount = 0;
        NQRLastShakeSpikeUptime = now;
        NQRShakeSpikeCount += 1;
        if (NQRShakeSpikeCount >= 2) {
            NQRShakeSpikeCount = 0;
            NQRLog(@"Shake gesture recognized acceleration=%.2f rotation=%.2f", acceleration, rotation);
            NQRPresentPanel(@"device shake");
        }
    }];
    NQRLog(@"Shake monitoring enabled at %.2f second interval", NQRMotionManager.deviceMotionUpdateInterval);
}

static void NQRHandleVolumePulse(NSString *source) {
    if (![NQRSelectedGesture isEqualToString:@"volume"] || NQRPanelWindow) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - NQRLastVolumePulse < 0.025) return;

    if (now - NQRLastVolumePulse > 0.42 || now - NQRVolumeSequenceStart > 1.6) {
        NQRVolumePulseCount = 0;
        NQRVolumeSequenceStart = now;
    }
    NQRLastVolumePulse = now;
    NQRVolumePulseCount += 1;
    NQRLog(@"Volume-up pulse %ld source=%@ elapsed=%.2f", (long)NQRVolumePulseCount, source, now - NQRVolumeSequenceStart);

    if (NQRVolumePulseCount >= 4 && now - NQRVolumeSequenceStart >= 0.32) {
        NQRVolumePulseCount = 0;
        NQRLog(@"Volume Up hold recognized");
        NQRPresentPanel(@"Volume Up hold");
    }
}

static void (*NQROriginalVolumeUp)(id, SEL) = NULL;
static void NQRHookedVolumeUp(id self, SEL selector) {
    if (NQROriginalVolumeUp) NQROriginalVolumeUp(self, selector);
    NQRHandleVolumePulse(NSStringFromSelector(selector));
}

static void NQRLogVolumeRuntimeMethods(Class cls) {
    if (!cls || !NQRDiagnosticLogging) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        NSString *lower = name.lowercaseString;
        if ([lower containsString:@"volume"] || [lower containsString:@"increase"] || [lower containsString:@"button"]) {
            [matches addObject:name];
        }
    }
    free(methods);
    NQRLog(@"%@ relevant runtime methods: %@", NSStringFromClass(cls), matches);
}

static void NQRInstallVolumeHook(void) {
    Class cls = NSClassFromString(@"SBVolumeControl");
    NQRLogVolumeRuntimeMethods(cls);
    if (!cls) {
        NQRLog(@"ERROR: SBVolumeControl class not found; Volume Up hold may rely only on volume-change notifications");
        return;
    }

    NSArray<NSString *> *candidateNames = @[@"increaseVolume", @"_increaseVolume"];
    for (NSString *name in candidateNames) {
        SEL selector = NSSelectorFromString(name);
        if (class_getInstanceMethod(cls, selector)) {
            MSHookMessageEx(cls, selector, (IMP)NQRHookedVolumeUp, (IMP *)&NQROriginalVolumeUp);
            NQRLog(@"Installed Volume Up hook on -[%@ %@]", NSStringFromClass(cls), name);
            return;
        }
    }
    NQRLog(@"ERROR: No supported SBVolumeControl increase selector found");
}

static void NQRApplyGestureSelection(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NQRDestroyStatusGestureWindow();
        NQRStopShakeMonitoring();
        NQRVolumePulseCount = 0;

        if ([NQRSelectedGesture isEqualToString:@"statusbar"]) {
            NQREnableStatusGestureWindow();
        } else if ([NQRSelectedGesture isEqualToString:@"shake"]) {
            NQRStartShakeMonitoring();
        } else if ([NQRSelectedGesture isEqualToString:@"volume"]) {
            NQRLog(@"Volume Up hold selected; waiting for repeated button pulses");
        } else {
            NQRLog(@"All quick-reminder gestures are off");
        }
    });
}

static void NQRReloadPreferences(void) {
    NSString *gesture = NQRCopyPreference(@"gesture");
    NSNumber *logging = NQRCopyPreference(@"diagnosticLogging");
    NSArray *valid = @[@"off", @"statusbar", @"shake", @"volume"];
    NQRSelectedGesture = [gesture isKindOfClass:NSString.class] && [valid containsObject:gesture] ? gesture : @"statusbar";
    NQRDiagnosticLogging = logging ? logging.boolValue : YES;
    NQRLog(@"Preferences reloaded selectedGesture=%@ diagnosticLogging=%@", NQRSelectedGesture, NQRDiagnosticLogging ? @"YES" : @"NO");
    NQRApplyGestureSelection();
}

static void NQRPreferencesDidChange(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{ NQRReloadPreferences(); });
}

static void NQRShowPanelRequested(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NQRLog(@"Test Panel request received from Settings");
    NQRPresentPanel(@"Settings test button");
}

%ctor {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if (![bundleID isEqualToString:@"com.apple.springboard"] && ![[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"]) return;

        NQRLogQueue = dispatch_queue_create("com.nextsolution.nextquickreminder.log", DISPATCH_QUEUE_SERIAL);
        NQRLog(@"Next Quick Reminder 1.0.0 loaded in process=%@ bundle=%@", NSProcessInfo.processInfo.processName, bundleID);

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NQRPreferencesDidChange, NQRPreferencesChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NQRShowPanelRequested, NQRShowPanelNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidChangeStatusBarFrameNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            NQRUpdateStatusGestureFrame();
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:@"AVSystemController_SystemVolumeDidChangeNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            NQRHandleVolumePulse(@"volume-change notification");
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NQRInstallVolumeHook();
            NQRReloadPreferences();
        });
    }
}
