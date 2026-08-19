#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreMotion/CoreMotion.h>
#import <objc/runtime.h>
#import <substrate.h>

static CFStringRef const NQR105Domain = CFSTR("com.nextsolution.nextquickreminder");
static CFStringRef const NQR105PrefsChanged = CFSTR("com.nextsolution.nextquickreminder.preferences.changed");
static CFStringRef const NQR105ShowPanel = CFSTR("com.nextsolution.nextquickreminder.showpanel");

static UIWindow *NQR105StatusWindow;
static CMMotionManager *NQR105MotionManager;
static NSTimer *NQR105RefreshTimer;
static NSTimeInterval NQR105LastTriggerUptime;
static NSTimeInterval NQR105VolumeUpStart;
static NSTimeInterval NQR105VolumeDownStart;
static NSInteger NQR105VolumeUpPulseCount;
static NSInteger NQR105VolumeDownPulseCount;
static NSTimeInterval NQR105LastUpPulse;
static NSTimeInterval NQR105LastDownPulse;
static NSInteger NQR105ShakeSpikes;
static NSTimeInterval NQR105LastShakeSpike;

static BOOL NQR105StatusEnabled = YES;
static BOOL NQR105VolumeUpEnabled = YES;
static BOOL NQR105VolumeDownEnabled = NO;
static BOOL NQR105ShakeEnabled = NO;
static BOOL NQR105LockEnabled = YES;
static BOOL NQR105HapticEnabled = YES;

static id NQR105Read(NSString *key) {
    CFPreferencesAppSynchronize(NQR105Domain);
    CFPropertyListRef raw = CFPreferencesCopyAppValue((__bridge CFStringRef)key, NQR105Domain);
    return CFBridgingRelease(raw);
}

static BOOL NQR105Bool(NSString *key, BOOL fallback) {
    id value = NQR105Read(key);
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}

static void NQR105Write(NSString *key, BOOL value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, value ? kCFBooleanTrue : kCFBooleanFalse, NQR105Domain);
    CFPreferencesAppSynchronize(NQR105Domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), NQR105PrefsChanged, NULL, NULL, true);
}

static UIWindowScene *NQR105ActiveScene(void) {
    if (@available(iOS 13.0, *)) {
        UIWindowScene *fallback = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (scene.activationState == UISceneActivationStateForegroundActive) return windowScene;
            if (!fallback && scene.activationState != UISceneActivationStateUnattached) fallback = windowScene;
        }
        return fallback;
    }
    return nil;
}

static void NQR105RequestPanel(NSString *source) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (now - NQR105LastTriggerUptime < 1.15) return;
        NQR105LastTriggerUptime = now;
        if (NQR105HapticEnabled) {
            UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [feedback impactOccurred];
        }
        NSLog(@"[NextQuickReminder105] Quick panel trigger: %@", source);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), NQR105ShowPanel, NULL, NULL, true);
    });
}

@interface NQR105StatusTapController : UIViewController
@end

@implementation NQR105StatusTapController
- (void)loadView {
    UIView *view = [UIView new];
    view.backgroundColor = UIColor.clearColor;
    view.userInteractionEnabled = YES;
    self.view = view;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
    tap.numberOfTapsRequired = 2;
    tap.cancelsTouchesInView = NO;
    [view addGestureRecognizer:tap];
}
- (void)doubleTap:(UITapGestureRecognizer *)tap {
    if (tap.state == UIGestureRecognizerStateRecognized && NQR105StatusEnabled) {
        NQR105RequestPanel(@"status-bar time double tap");
    }
}
@end

static void NQR105DestroyStatusWindow(void) {
    if (!NQR105StatusWindow) return;
    NQR105StatusWindow.hidden = YES;
    NQR105StatusWindow.rootViewController = nil;
    NQR105StatusWindow = nil;
}

static void NQR105RefreshStatusWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!NQR105StatusEnabled) {
            NQR105DestroyStatusWindow();
            return;
        }
        UIWindowScene *scene = NQR105ActiveScene();
        if (!NQR105StatusWindow || (@available(iOS 13.0, *) && scene && NQR105StatusWindow.windowScene != scene)) {
            NQR105DestroyStatusWindow();
            if (@available(iOS 13.0, *)) {
                NQR105StatusWindow = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:CGRectZero];
            } else {
                NQR105StatusWindow = [[UIWindow alloc] initWithFrame:CGRectZero];
            }
            NQR105StatusWindow.rootViewController = [NQR105StatusTapController new];
            NQR105StatusWindow.backgroundColor = UIColor.clearColor;
            NQR105StatusWindow.windowLevel = UIWindowLevelStatusBar + 1900;
        }
        CGFloat screenWidth = scene ? CGRectGetWidth(scene.coordinateSpace.bounds) : CGRectGetWidth(UIScreen.mainScreen.bounds);
        CGFloat statusHeight = 50.0;
        if (@available(iOS 13.0, *)) {
            statusHeight = MAX(statusHeight, scene.statusBarManager.statusBarFrame.size.height);
        }
        // Covers the full left status area rather than a small fixed time hit box.
        NQR105StatusWindow.frame = CGRectMake(0, 0, MIN(150.0, screenWidth * 0.39), statusHeight + 8.0);
        NQR105StatusWindow.hidden = NO;
    });
}

static void NQR105StopMotion(void) {
    if (NQR105MotionManager.deviceMotionActive) [NQR105MotionManager stopDeviceMotionUpdates];
    NQR105MotionManager = nil;
    NQR105ShakeSpikes = 0;
}

static void NQR105StartMotionIfNeeded(void) {
    NQR105StopMotion();
    if (!NQR105ShakeEnabled) return;
    NQR105MotionManager = [CMMotionManager new];
    if (!NQR105MotionManager.deviceMotionAvailable) return;
    NQR105MotionManager.deviceMotionUpdateInterval = 0.06;
    [NQR105MotionManager startDeviceMotionUpdatesToQueue:NSOperationQueue.mainQueue withHandler:^(CMDeviceMotion *motion, NSError *error) {
        if (error || !NQR105ShakeEnabled || !motion) return;
        CMAcceleration a = motion.userAcceleration;
        CMRotationRate r = motion.rotationRate;
        double accel = sqrt(a.x*a.x + a.y*a.y + a.z*a.z);
        double rot = sqrt(r.x*r.x + r.y*r.y + r.z*r.z);
        if (accel < 1.7 || rot < 2.6) return;
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (now - NQR105LastShakeSpike > 0.6) NQR105ShakeSpikes = 0;
        NQR105LastShakeSpike = now;
        NQR105ShakeSpikes += 1;
        if (NQR105ShakeSpikes >= 2) {
            NQR105ShakeSpikes = 0;
            NQR105RequestPanel(@"device shake");
        }
    }];
}

static void NQR105VolumePulse(BOOL up, NSString *source) {
    BOOL enabled = up ? NQR105VolumeUpEnabled : NQR105VolumeDownEnabled;
    if (!enabled) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    NSTimeInterval *last = up ? &NQR105LastUpPulse : &NQR105LastDownPulse;
    NSTimeInterval *start = up ? &NQR105VolumeUpStart : &NQR105VolumeDownStart;
    NSInteger *count = up ? &NQR105VolumeUpPulseCount : &NQR105VolumeDownPulseCount;
    if (now - *last < 0.025) return;
    if (now - *last > 0.48 || now - *start > 1.8) {
        *count = 0;
        *start = now;
    }
    *last = now;
    *count += 1;
    if (*count >= 4 && now - *start >= 0.34) {
        *count = 0;
        NQR105RequestPanel(up ? @"Volume Up hold" : @"Volume Down hold");
    }
}

static void (*NQR105OrigIncrease)(id, SEL) = NULL;
static void (*NQR105OrigDecrease)(id, SEL) = NULL;
static void NQR105Increase(id self, SEL sel) {
    if (NQR105OrigIncrease) NQR105OrigIncrease(self, sel);
    NQR105VolumePulse(YES, NSStringFromSelector(sel));
}
static void NQR105Decrease(id self, SEL sel) {
    if (NQR105OrigDecrease) NQR105OrigDecrease(self, sel);
    NQR105VolumePulse(NO, NSStringFromSelector(sel));
}

static void NQR105InstallVolumeHooks(void) {
    Class cls = NSClassFromString(@"SBVolumeControl");
    if (!cls) return;
    for (NSString *name in @[@"increaseVolume", @"_increaseVolume"]) {
        SEL sel = NSSelectorFromString(name);
        if (class_getInstanceMethod(cls, sel)) {
            MSHookMessageEx(cls, sel, (IMP)NQR105Increase, (IMP *)&NQR105OrigIncrease);
            break;
        }
    }
    for (NSString *name in @[@"decreaseVolume", @"_decreaseVolume"]) {
        SEL sel = NSSelectorFromString(name);
        if (class_getInstanceMethod(cls, sel)) {
            MSHookMessageEx(cls, sel, (IMP)NQR105Decrease, (IMP *)&NQR105OrigDecrease);
            break;
        }
    }
    [NSNotificationCenter.defaultCenter addObserverForName:@"AVSystemController_SystemVolumeDidChangeNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        // This is only a fallback pulse. The private increase/decrease hooks above distinguish direction.
    }];
}

static void NQR105Reload(void) {
    NQR105StatusEnabled = NQR105Bool(@"triggerStatusBar", YES);
    NQR105VolumeUpEnabled = NQR105Bool(@"triggerVolumeUp", YES);
    NQR105VolumeDownEnabled = NQR105Bool(@"triggerVolumeDown", NO);
    NQR105ShakeEnabled = NQR105Bool(@"triggerShake", NO);
    NQR105LockEnabled = NQR105Bool(@"triggerLockScreen", YES);
    NQR105HapticEnabled = NQR105Bool(@"triggerHaptic", YES);
    // Keep 1.0.4 lock-screen code compatible with the new toggle.
    CFPreferencesSetAppValue(CFSTR("allowLockScreen"), NQR105LockEnabled ? kCFBooleanTrue : kCFBooleanFalse, NQR105Domain);
    // Disable the old exclusive gesture engine; v1.0.5 owns all triggers independently.
    CFPreferencesSetAppValue(CFSTR("gesture"), CFSTR("off"), NQR105Domain);
    CFPreferencesAppSynchronize(NQR105Domain);
    NQR105RefreshStatusWindow();
    NQR105StartMotionIfNeeded();
}

static void NQR105PrefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NQR105Reload();
}

@interface NQR105TriggerSettingsController : UIViewController
@end

@implementation NQR105TriggerSettingsController {
    UISwitch *_statusSwitch;
    UISwitch *_upSwitch;
    UISwitch *_downSwitch;
    UISwitch *_shakeSwitch;
    UISwitch *_lockSwitch;
    UISwitch *_hapticSwitch;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.title = @"Quick Access";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    [scroll addSubview:stack];

    UILabel *subtitle = [UILabel new];
    subtitle.text = @"Enable any combination. These settings are available here even when the Settings preference bundle cannot load on RootHide.";
    subtitle.numberOfLines = 0;
    subtitle.font = [UIFont systemFontOfSize:13];
    subtitle.textColor = UIColor.secondaryLabelColor;
    [stack addArrangedSubview:subtitle];

    _statusSwitch = [self addRow:@"Double-tap Status-Bar Time" detail:@"Keeps a small transparent hit area over the time and refreshes it after UI changes." value:NQR105StatusEnabled stack:stack];
    _upSwitch = [self addRow:@"Hold Volume Up" detail:@"Hold until the quick reminder card appears. Normal volume adjustment is preserved." value:NQR105VolumeUpEnabled stack:stack];
    _downSwitch = [self addRow:@"Hold Volume Down" detail:@"Alternative hardware trigger. Can be enabled together with Volume Up." value:NQR105VolumeDownEnabled stack:stack];
    _shakeSwitch = [self addRow:@"Shake Device" detail:@"Motion monitoring runs only while this option is enabled." value:NQR105ShakeEnabled stack:stack];
    _lockSwitch = [self addRow:@"Lock Screen Clock Double-Tap" detail:@"Opens the same quick reminder card from the Lock Screen clock." value:NQR105LockEnabled stack:stack];
    _hapticSwitch = [self addRow:@"Trigger Haptic" detail:@"Vibrates when a quick-access gesture is accepted." value:NQR105HapticEnabled stack:stack];

    UIButton *test = [UIButton buttonWithType:UIButtonTypeSystem];
    [test setTitle:@"Test Quick Reminder Card" forState:UIControlStateNormal];
    test.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    test.backgroundColor = UIColor.systemOrangeColor;
    [test setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    test.layer.cornerRadius = 13;
    test.contentEdgeInsets = UIEdgeInsetsMake(13, 16, 13, 16);
    [test addTarget:self action:@selector(testPanel) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:test];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32],
    ]];
}

- (UISwitch *)addRow:(NSString *)title detail:(NSString *)detail value:(BOOL)value stack:(UIStackView *)stack {
    UIView *row = [UIView new];
    row.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    row.layer.cornerRadius = 14;
    UIStackView *labels = [UIStackView new];
    labels.translatesAutoresizingMaskIntoConstraints = NO;
    labels.axis = UILayoutConstraintAxisVertical;
    labels.spacing = 3;
    UILabel *titleLabel = [UILabel new];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    UILabel *detailLabel = [UILabel new];
    detailLabel.text = detail;
    detailLabel.numberOfLines = 0;
    detailLabel.font = [UIFont systemFontOfSize:12];
    detailLabel.textColor = UIColor.secondaryLabelColor;
    [labels addArrangedSubview:titleLabel];
    [labels addArrangedSubview:detailLabel];
    UISwitch *toggle = [UISwitch new];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    toggle.on = value;
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    [row addSubview:labels];
    [row addSubview:toggle];
    [NSLayoutConstraint activateConstraints:@[
        [labels.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14],
        [labels.topAnchor constraintEqualToAnchor:row.topAnchor constant:12],
        [labels.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-12],
        [labels.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-12],
        [toggle.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14],
        [toggle.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    [stack addArrangedSubview:row];
    return toggle;
}

- (void)toggleChanged:(UISwitch *)sender {
    if (sender == _statusSwitch) NQR105Write(@"triggerStatusBar", sender.on);
    else if (sender == _upSwitch) NQR105Write(@"triggerVolumeUp", sender.on);
    else if (sender == _downSwitch) NQR105Write(@"triggerVolumeDown", sender.on);
    else if (sender == _shakeSwitch) NQR105Write(@"triggerShake", sender.on);
    else if (sender == _lockSwitch) NQR105Write(@"triggerLockScreen", sender.on);
    else if (sender == _hapticSwitch) NQR105Write(@"triggerHaptic", sender.on);
}

- (void)testPanel {
    [self dismissViewControllerAnimated:YES completion:^{ NQR105RequestPanel(@"Quick Access test button"); }];
}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

@interface NQRQuickPanelController : UIViewController
@end

@implementation NQRQuickPanelController (NQR105QuickAccess)
- (void)nqr105_showQuickAccess {
    NQR105TriggerSettingsController *settings = [NQR105TriggerSettingsController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        nav.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
        nav.sheetPresentationController.prefersGrabberVisible = YES;
    }
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)nqr105_installQuickAccessButton {
    if ([self.view viewWithTag:105105]) return;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = 105105;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    button.tintColor = UIColor.systemOrangeColor;
    button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.layer.cornerRadius = 18;
    button.layer.shadowColor = UIColor.blackColor.CGColor;
    button.layer.shadowOpacity = 0.15;
    button.layer.shadowRadius = 5;
    [button addTarget:self action:@selector(nqr105_showQuickAccess) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [button.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [button.widthAnchor constraintEqualToConstant:36],
        [button.heightAnchor constraintEqualToConstant:36],
    ]];
}
@end

static void NQR105InstallPanelAccessory(void) {
    Class cls = NSClassFromString(@"NQRQuickPanelController");
    SEL originalSel = @selector(viewDidAppear:);
    Method original = class_getInstanceMethod(cls, originalSel);
    if (!cls || !original) return;
    IMP originalIMP = method_getImplementation(original);
    id block = ^(id self, BOOL animated) {
        ((void(*)(id, SEL, BOOL))originalIMP)(self, originalSel, animated);
        if ([self respondsToSelector:@selector(nqr105_installQuickAccessButton)]) [self nqr105_installQuickAccessButton];
    };
    method_setImplementation(original, imp_implementationWithBlock(block));
}

__attribute__((constructor))
static void NQR105Init(void) {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"] && ![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NQR105PrefsChangedCallback, NQR105PrefsChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NQR105InstallVolumeHooks();
            NQR105InstallPanelAccessory();
            NQR105Reload();
            NQR105RefreshTimer = [NSTimer scheduledTimerWithTimeInterval:6.0 repeats:YES block:^(__unused NSTimer *timer) { NQR105RefreshStatusWindow(); }];
            NSLog(@"[NextQuickReminder105] Multi-trigger engine loaded");
        });
    }
}
