#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parent
path = root / "Tweak.xm"
text = path.read_text()

# Apply the v1.0.2 safe-startup hardening to the original source when needed.
text = text.replace('static NSString *NQRSelectedGesture = @"statusbar";', 'static NSString *NQRSelectedGesture = @"off";', 1)
if 'static NSString *NQRLogPath(void) {' in text:
    start = text.index('static NSString *NQRLogPath(void) {')
    end = text.index('static void NQRLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);', start)
    text = text[:start] + text[end:]

start = text.index('static void NQRLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);')
end = text.index('static id NQRCopyPreference', start)
safe_log = r'''static NSString *NQRLastRuntimeLog = @"Tweak loaded; no gesture has been activated yet.";

static void NQRLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void NQRLog(NSString *format, ...) {
    if (!format.length) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    if (!message.length) return;
    NQRLastRuntimeLog = [message copy];
    NSLog(@"[NextQuickReminder] %@", message);
}

'''
text = text[:start] + safe_log + text[end:]
text = text.replace('? gesture : @"statusbar";', '? gesture : @"off";', 1)

if 'static void (*NQROriginalVolumeUp)' in text:
    start = text.index('static void (*NQROriginalVolumeUp)')
    end = text.index('\nstatic void NQRApplyGestureSelection(void)', start)
    safe_volume = r'''static BOOL NQRVolumeObserverInstalled = NO;

static void NQRInstallVolumeHook(void) {
    if (NQRVolumeObserverInstalled) return;
    NQRVolumeObserverInstalled = YES;
    [NSNotificationCenter.defaultCenter addObserverForName:@"AVSystemController_SystemVolumeDidChangeNotification"
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(__unused NSNotification *note) {
        NQRHandleVolumePulse(@"volume-change notification");
    }];
    NQRLog(@"Volume Up monitoring enabled without private method hooks");
}
'''
    text = text[:start] + safe_volume + text[end:]

text = text.replace('''        } else if ([NQRSelectedGesture isEqualToString:@"volume"]) {
            NQRLog(@"Volume Up hold selected; waiting for repeated button pulses");
''', '''        } else if ([NQRSelectedGesture isEqualToString:@"volume"]) {
            NQRInstallVolumeHook();
            NQRLog(@"Volume Up hold selected; waiting for repeated system volume notifications");
''', 1)

text = text.replace('''        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidChangeStatusBarFrameNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            NQRUpdateStatusGestureFrame();
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:@"AVSystemController_SystemVolumeDidChangeNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            NQRHandleVolumePulse(@"volume-change notification");
        }];

''', '', 1)
text = text.replace('''        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NQRInstallVolumeHook();
            NQRReloadPreferences();
        });
''', '''        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NQRReloadPreferences();
        });
''', 1)

# Retain the card and scroll view explicitly.
text = text.replace('''@property(nonatomic,strong) UIButton *repeatButton;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,copy) NSString *repeatMode;
''', '''@property(nonatomic,strong) UIButton *repeatButton;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UIScrollView *formScrollView;
@property(nonatomic,strong) UIView *cardView;
@property(nonatomic,copy) NSString *repeatMode;
''', 1)
text = text.replace('''    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
''', '''    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.cardView = card;
''', 1)
text = text.replace('''    UIScrollView *scrollView = [UIScrollView new];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
''', '''    UIScrollView *scrollView = [UIScrollView new];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    scrollView.alwaysBounceVertical = YES;
    self.formScrollView = scrollView;
''', 1)

old_constraints = '''    UILayoutGuide *frameGuide = scrollView.frameLayoutGuide;
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
'''
new_constraints = '''    UILayoutGuide *frameGuide = scrollView.frameLayoutGuide;
    UILayoutGuide *contentGuide = scrollView.contentLayoutGuide;
    CGFloat preferredCardHeight = MIN(620.0, MAX(500.0, UIScreen.mainScreen.bounds.size.height - 96.0));
    NSLayoutConstraint *preferredWidth = [card.widthAnchor constraintEqualToAnchor:self.view.widthAnchor constant:-28.0];
    preferredWidth.priority = UILayoutPriorityDefaultHigh;
    NSLayoutConstraint *preferredHeight = [card.heightAnchor constraintEqualToConstant:preferredCardHeight];
    preferredHeight.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [card.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12.0],
        [card.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:14.0],
        [card.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-14.0],
        [card.topAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12.0],
        [card.widthAnchor constraintLessThanOrEqualToConstant:420.0],
        preferredWidth,
        preferredHeight,
        [card.heightAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.heightAnchor constant:-24.0],
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
'''
if old_constraints not in text:
    raise SystemExit('Original zero-height card constraint block was not found')
text = text.replace(old_constraints, new_constraints, 1)

old_keyboard = '''- (void)keyboardWillShow:(NSNotification *)notification {
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
'''
new_keyboard = '''- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.cardView) return;
    self.cardView.transform = CGAffineTransformMakeTranslation(0.0, 28.0);
    self.cardView.alpha = 0.0;
    [UIView animateWithDuration:0.24 delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.cardView.transform = CGAffineTransformIdentity;
        self.cardView.alpha = 1.0;
    } completion:nil];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    CGRect keyboard = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat overlap = MAX(0.0, keyboard.size.height - self.view.safeAreaInsets.bottom);
    self.formScrollView.contentInset = UIEdgeInsetsMake(0, 0, overlap + 12.0, 0);
    self.formScrollView.scrollIndicatorInsets = self.formScrollView.contentInset;
}

- (void)keyboardWillHide:(NSNotification *)notification {
    self.formScrollView.contentInset = UIEdgeInsetsZero;
    self.formScrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
}
'''
if old_keyboard not in text:
    raise SystemExit('Original keyboard block was not found')
text = text.replace(old_keyboard, new_keyboard, 1)

old_window = '''        if (@available(iOS 13.0, *)) {
            NQRPanelWindow = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        } else {
            NQRPanelWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        }
        NQRPanelWindow.frame = UIScreen.mainScreen.bounds;
'''
new_window = '''        if (@available(iOS 13.0, *)) {
            NQRPanelWindow = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        } else {
            NQRPanelWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        }
        CGRect panelBounds = UIScreen.mainScreen.bounds;
        if (@available(iOS 13.0, *)) {
            if (scene) panelBounds = scene.coordinateSpace.bounds;
        }
        NQRPanelWindow.frame = panelBounds;
'''
if old_window not in text:
    raise SystemExit('Original panel window frame block was not found')
text = text.replace(old_window, new_window, 1)
text = text.replace('Next Quick Reminder 1.0.0 loaded', 'Next Quick Reminder 1.0.3 loaded with visible-panel layout fix in safe startup mode', 1)
path.write_text(text)

# Version all package and console surfaces consistently.
for rel in ['control', 'ConsoleBridge.m', 'Preferences/Resources/Info.plist', 'Preferences/NQRDiagnosticsController.m', 'layout/DEBIAN/postinst']:
    p = root / rel
    s = p.read_text()
    s = s.replace('1.0.2', '1.0.3').replace('1.0.1', '1.0.3').replace('1.0.0', '1.0.3')
    p.write_text(s)

print('Applied Next Quick Reminder 1.0.3 visible panel and safe-startup fixes.')
