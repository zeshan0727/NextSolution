#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <sqlite3.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const NMPrefsDomain = @"com.nextsolution.nextmessage";
static CFStringRef const NMPrefsChangedNotification = CFSTR("com.nextsolution.nextmessage/preferences.changed");
static NSInteger const NMToastTag = 7270727;

typedef NS_ENUM(NSInteger, NMAppearanceMode) {
    NMAppearanceModeSystem = 0,
    NMAppearanceModeLight = 1,
    NMAppearanceModeBlack = 2,
};

@interface NMPreferences : NSObject
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL redesignInbox;
@property (nonatomic, assign) BOOL redesignConversation;
@property (nonatomic, assign) BOOL enableToasts;
@property (nonatomic, assign) BOOL enableInfoAction;
@property (nonatomic, assign) BOOL enableDeleteAction;
@property (nonatomic, assign) BOOL enableConceptHeader;
@property (nonatomic, assign) BOOL enableBottomDock;
@property (nonatomic, assign) BOOL enableSmartReplies;
@property (nonatomic, assign) BOOL enableAuroraBackground;
@property (nonatomic, assign) NMAppearanceMode appearanceMode;
+ (instancetype)shared;
- (void)reload;
@end

static id NMPreferenceValue(NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)NMPrefsDomain);
    return CFBridgingRelease(value);
}

@implementation NMPreferences

+ (instancetype)shared {
    static NMPreferences *preferences;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        preferences = [NMPreferences new];
        [preferences reload];
    });
    return preferences;
}

- (void)reload {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NMPrefsDomain);
    NSNumber *enabled = NMPreferenceValue(@"Enabled");
    NSNumber *inbox = NMPreferenceValue(@"RedesignInbox");
    NSNumber *conversation = NMPreferenceValue(@"RedesignConversation");
    NSNumber *toasts = NMPreferenceValue(@"EnableToasts");
    NSNumber *info = NMPreferenceValue(@"EnableInfoAction");
    NSNumber *deleteAction = NMPreferenceValue(@"EnableDeleteAction");
    NSNumber *header = NMPreferenceValue(@"EnableConceptHeader");
    NSNumber *dock = NMPreferenceValue(@"EnableBottomDock");
    NSNumber *replies = NMPreferenceValue(@"EnableSmartReplies");
    NSNumber *aurora = NMPreferenceValue(@"EnableAuroraBackground");
    NSNumber *appearance = NMPreferenceValue(@"AppearanceMode");

    self.enabled = enabled ? enabled.boolValue : YES;
    self.redesignInbox = inbox ? inbox.boolValue : YES;
    self.redesignConversation = conversation ? conversation.boolValue : YES;
    self.enableToasts = toasts ? toasts.boolValue : YES;
    self.enableInfoAction = info ? info.boolValue : YES;
    self.enableDeleteAction = deleteAction ? deleteAction.boolValue : YES;
    self.enableConceptHeader = header ? header.boolValue : YES;
    self.enableBottomDock = dock ? dock.boolValue : YES;
    self.enableSmartReplies = replies ? replies.boolValue : YES;
    self.enableAuroraBackground = aurora ? aurora.boolValue : YES;
    self.appearanceMode = appearance ? (NMAppearanceMode)appearance.integerValue : NMAppearanceModeSystem;
}

@end

static UIColor *NMPurpleColor(void) {
    return [UIColor colorWithRed:0.45 green:0.35 blue:1.0 alpha:1.0];
}

static UIColor *NMBlueColor(void) {
    return [UIColor colorWithRed:0.20 green:0.55 blue:1.0 alpha:1.0];
}

static UIUserInterfaceStyle NMForcedInterfaceStyle(void) {
    switch ([NMPreferences shared].appearanceMode) {
        case NMAppearanceModeLight: return UIUserInterfaceStyleLight;
        case NMAppearanceModeBlack: return UIUserInterfaceStyleDark;
        default: return UIUserInterfaceStyleUnspecified;
    }
}

static BOOL NMUsesDarkAppearance(UITraitCollection *traits) {
    NMAppearanceMode mode = [NMPreferences shared].appearanceMode;
    if (mode == NMAppearanceModeBlack) return YES;
    if (mode == NMAppearanceModeLight) return NO;
    return traits.userInterfaceStyle == UIUserInterfaceStyleDark;
}

static UIColor *NMCanvasColor(UITraitCollection *traits) {
    if ([NMPreferences shared].appearanceMode == NMAppearanceModeBlack) return UIColor.blackColor;
    return NMUsesDarkAppearance(traits)
        ? [UIColor colorWithRed:0.015 green:0.035 blue:0.060 alpha:1.0]
        : [UIColor colorWithRed:0.935 green:0.955 blue:0.980 alpha:1.0];
}

static UIBlurEffectStyle NMBlurStyle(UITraitCollection *traits) {
    return NMUsesDarkAppearance(traits)
        ? UIBlurEffectStyleSystemUltraThinMaterialDark
        : UIBlurEffectStyleSystemUltraThinMaterialLight;
}

static id NMSafeValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try { return [object valueForKey:key]; }
    @catch (__unused NSException *exception) { return nil; }
}

static NSString *NMSafeString(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = NMSafeValue(object, key);
        if ([value isKindOfClass:NSString.class] && [value length] > 0) return value;
        if ([value respondsToSelector:@selector(stringValue)]) {
            NSString *string = [value stringValue];
            if (string.length > 0) return string;
        }
    }
    return nil;
}

static UIViewController *NMTopControllerFrom(UIViewController *controller) {
    if (!controller) return nil;
    if (controller.presentedViewController) return NMTopControllerFrom(controller.presentedViewController);
    if ([controller isKindOfClass:UINavigationController.class]) return NMTopControllerFrom(((UINavigationController *)controller).visibleViewController);
    if ([controller isKindOfClass:UITabBarController.class]) return NMTopControllerFrom(((UITabBarController *)controller).selectedViewController);
    return controller;
}

static UIWindow *NMKeyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) return window;
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static UIViewController *NMTopController(void) {
    return NMTopControllerFrom(NMKeyWindow().rootViewController);
}

static UIViewController *NMViewControllerForView(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
        responder = responder.nextResponder;
    }
    return nil;
}

static NSArray<UIView *> *NMAllSubviews(UIView *root) {
    if (!root) return @[];
    NSMutableArray<UIView *> *all = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        [all addObject:view];
        [queue addObjectsFromArray:view.subviews];
    }
    return all;
}

static UITableView *NMFindTableView(UIView *root) {
    for (UIView *view in NMAllSubviews(root)) if ([view isKindOfClass:UITableView.class]) return (UITableView *)view;
    return nil;
}

static UISearchBar *NMFindSearchBar(UIView *root) {
    for (UIView *view in NMAllSubviews(root)) if ([view isKindOfClass:UISearchBar.class]) return (UISearchBar *)view;
    return nil;
}

static UITextView *NMFindTextView(UIView *root) {
    for (UIView *view in NMAllSubviews(root)) if ([view isKindOfClass:UITextView.class]) return (UITextView *)view;
    return nil;
}

static void NMDismissToast(UIView *toast) {
    if (!toast || !toast.superview) return;
    [UIView animateWithDuration:0.22 animations:^{
        toast.alpha = 0.0;
        toast.transform = CGAffineTransformMakeTranslation(0, 18);
    } completion:^(__unused BOOL finished) { [toast removeFromSuperview]; }];
}

static void NMShowToast(NSString *title, NSString *message, NSTimeInterval duration) {
    if (![NMPreferences shared].enabled || ![NMPreferences shared].enableToasts) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *host = NMTopController();
        if (!host.view) return;
        UIView *oldToast = [host.view viewWithTag:NMToastTag];
        if (oldToast) [oldToast removeFromSuperview];

        UIView *container = [UIView new];
        container.tag = NMToastTag;
        container.translatesAutoresizingMaskIntoConstraints = NO;
        container.layer.cornerRadius = 22.0;
        container.layer.cornerCurve = kCACornerCurveContinuous;
        container.layer.masksToBounds = YES;
        container.layer.borderWidth = 0.6;
        container.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;

        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:NMBlurStyle(host.traitCollection)]];
        blur.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:blur];

        CAGradientLayer *accent = [CAGradientLayer layer];
        accent.colors = @[(__bridge id)NMBlueColor().CGColor, (__bridge id)NMPurpleColor().CGColor];
        accent.startPoint = CGPointMake(0, 0);
        accent.endPoint = CGPointMake(1, 1);
        accent.frame = CGRectMake(0, 0, 5, 120);
        [container.layer addSublayer:accent];

        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"info.circle.fill"]];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.tintColor = NMPurpleColor();
        icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];
        [container addSubview:icon];

        UILabel *titleLabel = [UILabel new];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        titleLabel.text = title ?: @"Next Message";
        [container addSubview:titleLabel];

        UILabel *messageLabel = [UILabel new];
        messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        messageLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        messageLabel.textColor = UIColor.secondaryLabelColor;
        messageLabel.text = message ?: @"";
        messageLabel.numberOfLines = 0;
        [container addSubview:messageLabel];

        UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
        closeButton.tintColor = UIColor.secondaryLabelColor;
        [container addSubview:closeButton];

        [host.view addSubview:container];
        [NSLayoutConstraint activateConstraints:@[
            [blur.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [blur.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [blur.topAnchor constraintEqualToAnchor:container.topAnchor],
            [blur.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
            [container.leadingAnchor constraintEqualToAnchor:host.view.safeAreaLayoutGuide.leadingAnchor constant:14],
            [container.trailingAnchor constraintEqualToAnchor:host.view.safeAreaLayoutGuide.trailingAnchor constant:-14],
            [container.bottomAnchor constraintEqualToAnchor:host.view.safeAreaLayoutGuide.bottomAnchor constant:-14],
            [container.heightAnchor constraintGreaterThanOrEqualToConstant:92],
            [icon.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:17],
            [icon.topAnchor constraintEqualToAnchor:container.topAnchor constant:17],
            [icon.widthAnchor constraintEqualToConstant:28],
            [icon.heightAnchor constraintEqualToConstant:28],
            [closeButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-14],
            [closeButton.topAnchor constraintEqualToAnchor:container.topAnchor constant:14],
            [closeButton.widthAnchor constraintEqualToConstant:30],
            [closeButton.heightAnchor constraintEqualToConstant:30],
            [titleLabel.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
            [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:closeButton.leadingAnchor constant:-8],
            [titleLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:15],
            [messageLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
            [messageLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
            [messageLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:5],
            [messageLabel.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-15],
        ]];

        __weak UIView *weakToast = container;
        [closeButton addAction:[UIAction actionWithHandler:^(__unused UIAction *action) { NMDismissToast(weakToast); }] forControlEvents:UIControlEventTouchUpInside];
        container.alpha = 0.0;
        container.transform = CGAffineTransformMakeTranslation(0, 22);
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.3 options:UIViewAnimationOptionCurveEaseOut animations:^{
            container.alpha = 1.0;
            container.transform = CGAffineTransformIdentity;
        } completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ NMDismissToast(weakToast); });
    });
}

static NSDate *NMDateFromMessagesValue(double rawValue) {
    if (rawValue <= 0) return nil;
    double seconds = rawValue;
    if (seconds > 100000000000.0) seconds /= 1000000000.0;
    return [NSDate dateWithTimeIntervalSinceReferenceDate:seconds];
}

static id NMChatObjectFromConversation(id conversation) {
    return NMSafeValue(conversation, @"chat") ?: NMSafeValue(conversation, @"representedChat") ?: conversation;
}

static NSString *NMConversationIdentifier(id conversation) {
    id chat = NMChatObjectFromConversation(conversation);
    NSString *identifier = NMSafeString(chat, @[@"guid", @"chatGUID", @"chatIdentifier", @"identifier"]);
    if (!identifier) identifier = NMSafeString(conversation, @[@"guid", @"chatGUID", @"chatIdentifier", @"identifier"]);
    return identifier;
}

static NSString *NMConversationDisplayName(id conversation, UITableViewCell *cell) {
    id chat = NMChatObjectFromConversation(conversation);
    NSString *name = NMSafeString(conversation, @[@"displayName", @"name", @"title"]);
    if (!name) name = NMSafeString(chat, @[@"displayName", @"name", @"title"]);
    if (!name) name = cell.textLabel.text;
    return name.length ? name : @"Conversation details";
}

static NSDictionary<NSString *, id> *NMConversationStats(id conversation) {
    NSString *identifier = NMConversationIdentifier(conversation);
    long long count = 0;
    NSDate *firstDate = nil;
    if (identifier.length) {
        sqlite3 *database = NULL;
        if (sqlite3_open_v2("/var/mobile/Library/SMS/sms.db", &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL) == SQLITE_OK) {
            const char *query = "SELECT COUNT(m.ROWID), MIN(CASE WHEN m.date > 0 THEN m.date ELSE NULL END) FROM chat c LEFT JOIN chat_message_join cmj ON cmj.chat_id = c.ROWID LEFT JOIN message m ON m.ROWID = cmj.message_id WHERE c.guid = ?1 OR c.chat_identifier = ?1";
            sqlite3_stmt *statement = NULL;
            if (sqlite3_prepare_v2(database, query, -1, &statement, NULL) == SQLITE_OK) {
                sqlite3_bind_text(statement, 1, identifier.UTF8String, -1, SQLITE_TRANSIENT);
                if (sqlite3_step(statement) == SQLITE_ROW) {
                    count = sqlite3_column_int64(statement, 0);
                    firstDate = NMDateFromMessagesValue(sqlite3_column_double(statement, 1));
                }
            }
            if (statement) sqlite3_finalize(statement);
        }
        if (database) sqlite3_close(database);
    }
    if (count <= 0) {
        id fallbackCount = NMSafeValue(conversation, @"messageCount") ?: NMSafeValue(NMChatObjectFromConversation(conversation), @"messageCount");
        if ([fallbackCount respondsToSelector:@selector(longLongValue)]) count = [fallbackCount longLongValue];
    }
    if (!firstDate) {
        id fallbackDate = NMSafeValue(conversation, @"firstMessageDate") ?: NMSafeValue(NMChatObjectFromConversation(conversation), @"firstMessageDate");
        if ([fallbackDate isKindOfClass:NSDate.class]) firstDate = fallbackDate;
    }
    return @{@"count": @(MAX(count, 0)), @"firstDate": firstDate ?: NSNull.null, @"identifier": identifier ?: @"Unavailable"};
}

static void NMShowConversationInfo(id conversation, UITableViewCell *cell) {
    NSDictionary *stats = NMConversationStats(conversation);
    NSString *dateText = @"Not available";
    id dateObject = stats[@"firstDate"];
    if ([dateObject isKindOfClass:NSDate.class]) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
        dateText = [formatter stringFromDate:dateObject];
    }
    NSString *message = [NSString stringWithFormat:@"Messages in this conversation: %@\nFirst conversation date: %@", stats[@"count"], dateText];
    NMShowToast(NMConversationDisplayName(conversation, cell), message, 8.0);
}

@interface NMAuroraView : UIView
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@end

@implementation NMAuroraView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _gradientLayer = [CAGradientLayer layer];
        _gradientLayer.startPoint = CGPointMake(0.0, 0.0);
        _gradientLayer.endPoint = CGPointMake(1.0, 1.0);
        [self.layer addSublayer:_gradientLayer];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.gradientLayer.frame = self.bounds;
    BOOL dark = NMUsesDarkAppearance(self.traitCollection);
    self.gradientLayer.colors = dark
        ? @[(id)[UIColor colorWithRed:0.015 green:0.040 blue:0.075 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.015 green:0.120 blue:0.180 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.155 green:0.080 blue:0.280 alpha:1.0].CGColor]
        : @[(id)[UIColor colorWithRed:0.92 green:0.96 blue:1.0 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.82 green:0.92 blue:0.98 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.91 green:0.86 blue:1.0 alpha:1.0].CGColor];
    self.gradientLayer.locations = @[@0.0, @0.56, @1.0];
}
@end

static const void *NMBackgroundKey = &NMBackgroundKey;
static const void *NMInboxChromeKey = &NMInboxChromeKey;
static const void *NMDockKey = &NMDockKey;
static const void *NMComposeKey = &NMComposeKey;
static const void *NMFilterKey = &NMFilterKey;
static const void *NMCardKey = &NMCardKey;
static const void *NMBalloonGradientKey = &NMBalloonGradientKey;
static const void *NMSmartBarKey = &NMSmartBarKey;

static void NMInstallBackground(UIViewController *controller) {
    if (!controller.view || ![NMPreferences shared].enableAuroraBackground) return;
    NMAuroraView *background = objc_getAssociatedObject(controller, NMBackgroundKey);
    if (!background) {
        background = [[NMAuroraView alloc] initWithFrame:controller.view.bounds];
        [controller.view insertSubview:background atIndex:0];
        objc_setAssociatedObject(controller, NMBackgroundKey, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    background.frame = controller.view.bounds;
    [background setNeedsLayout];
}

static void NMOpenPreferences(void) {
    NSArray<NSString *> *urls = @[@"App-Prefs:root=NextMessage", @"App-Prefs:root=NextMessagePrefs", @"prefs:root=NextMessage"];
    for (NSString *string in urls) {
        NSURL *url = [NSURL URLWithString:string];
        if ([UIApplication.sharedApplication canOpenURL:url]) {
            [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
            return;
        }
    }
    NMShowToast(@"Next Message", @"Open Settings and select Next Message.", 4.0);
}

static BOOL NMInvokeFirstSelector(id target, NSArray<NSString *> *selectorNames, id argument) {
    for (NSString *name in selectorNames) {
        SEL selector = NSSelectorFromString(name);
        if (![target respondsToSelector:selector]) continue;
        NSMethodSignature *signature = [target methodSignatureForSelector:selector];
        if (signature.numberOfArguments > 2) ((void (*)(id, SEL, id))objc_msgSend)(target, selector, argument);
        else ((void (*)(id, SEL))objc_msgSend)(target, selector);
        return YES;
    }
    return NO;
}

@interface NMInboxChromeView : UIVisualEffectView <UITextFieldDelegate>
@property (nonatomic, weak) UIViewController *controller;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UIStackView *chipStack;
@property (nonatomic, copy) NSString *selectedFilter;
- (instancetype)initWithController:(UIViewController *)controller;
@end

@implementation NMInboxChromeView

- (instancetype)initWithController:(UIViewController *)controller {
    self = [super initWithEffect:[UIBlurEffect effectWithStyle:NMBlurStyle(controller.traitCollection)]];
    if (!self) return nil;
    self.controller = controller;
    self.layer.cornerRadius = 26.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 0.6;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    _titleLabel.text = @"Next Message";
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_titleLabel];

    UIButton *moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    moreButton.backgroundColor = [UIColor.secondarySystemFillColor colorWithAlphaComponent:0.55];
    moreButton.layer.cornerRadius = 19;
    [moreButton setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
    moreButton.tintColor = UIColor.labelColor;
    [moreButton addAction:[UIAction actionWithHandler:^(__unused UIAction *action) { NMOpenPreferences(); }] forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:moreButton];

    _searchField = [UITextField new];
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    _searchField.placeholder = @"Search conversations";
    _searchField.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    _searchField.backgroundColor = [UIColor.secondarySystemFillColor colorWithAlphaComponent:0.62];
    _searchField.layer.cornerRadius = 18;
    _searchField.layer.cornerCurve = kCACornerCurveContinuous;
    _searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _searchField.returnKeyType = UIReturnKeySearch;
    _searchField.delegate = self;
    UIImageView *searchIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];
    searchIcon.tintColor = UIColor.secondaryLabelColor;
    searchIcon.contentMode = UIViewContentModeCenter;
    searchIcon.frame = CGRectMake(0, 0, 38, 36);
    _searchField.leftView = searchIcon;
    _searchField.leftViewMode = UITextFieldViewModeAlways;
    [_searchField addTarget:self action:@selector(searchChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.contentView addSubview:_searchField];

    _chipStack = [UIStackView new];
    _chipStack.translatesAutoresizingMaskIntoConstraints = NO;
    _chipStack.axis = UILayoutConstraintAxisHorizontal;
    _chipStack.spacing = 8;
    _chipStack.distribution = UIStackViewDistributionFillEqually;
    [self.contentView addSubview:_chipStack];

    for (NSString *name in @[@"All", @"Personal", @"Work", @"Unread", @"More"]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.accessibilityLabel = name;
        button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        button.layer.cornerRadius = 15;
        button.layer.cornerCurve = kCACornerCurveContinuous;
        button.layer.borderWidth = 0.6;
        [button setTitle:name forState:UIControlStateNormal];
        [button addTarget:self action:@selector(filterTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_chipStack addArrangedSubview:button];
    }
    self.selectedFilter = @"All";
    [self refreshChips];

    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18],
        [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:13],
        [moreButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-15],
        [moreButton.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [moreButton.widthAnchor constraintEqualToConstant:38],
        [moreButton.heightAnchor constraintEqualToConstant:38],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:moreButton.leadingAnchor constant:-10],
        [_searchField.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
        [_searchField.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14],
        [_searchField.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:8],
        [_searchField.heightAnchor constraintEqualToConstant:37],
        [_chipStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
        [_chipStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14],
        [_chipStack.topAnchor constraintEqualToAnchor:_searchField.bottomAnchor constant:9],
        [_chipStack.heightAnchor constraintEqualToConstant:31],
    ]];
    return self;
}

- (void)refreshChips {
    for (UIButton *button in self.chipStack.arrangedSubviews) {
        BOOL selected = [button.accessibilityLabel isEqualToString:self.selectedFilter];
        button.backgroundColor = selected ? NMPurpleColor() : [UIColor.secondarySystemFillColor colorWithAlphaComponent:0.42];
        button.layer.borderColor = selected ? [UIColor colorWithWhite:1 alpha:0.28].CGColor : [UIColor.separatorColor colorWithAlphaComponent:0.35].CGColor;
        [button setTitleColor:selected ? UIColor.whiteColor : UIColor.labelColor forState:UIControlStateNormal];
        button.layer.shadowOpacity = selected ? 0.25 : 0.0;
        button.layer.shadowColor = NMPurpleColor().CGColor;
        button.layer.shadowRadius = 8;
    }
}

- (void)filterTapped:(UIButton *)sender {
    self.selectedFilter = sender.accessibilityLabel ?: @"All";
    objc_setAssociatedObject(self.controller, NMFilterKey, self.selectedFilter, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self refreshChips];
    UITableView *tableView = NMFindTableView(self.controller.view);
    for (UITableViewCell *cell in tableView.visibleCells) [cell setNeedsLayout];
    if (![self.selectedFilter isEqualToString:@"All"]) NMShowToast([NSString stringWithFormat:@"%@ filter", self.selectedFilter], @"Visible conversations are highlighted using the selected category.", 2.8);
}

- (void)searchChanged:(UITextField *)sender {
    UISearchBar *nativeSearch = NMFindSearchBar(self.controller.view);
    if (nativeSearch && nativeSearch != (id)sender) {
        nativeSearch.text = sender.text;
        if ([nativeSearch.delegate respondsToSelector:@selector(searchBar:textDidChange:)]) [nativeSearch.delegate searchBar:nativeSearch textDidChange:sender.text ?: @""];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    UISearchBar *nativeSearch = NMFindSearchBar(self.controller.view);
    if (nativeSearch && [nativeSearch.delegate respondsToSelector:@selector(searchBarSearchButtonClicked:)]) [nativeSearch.delegate searchBarSearchButtonClicked:nativeSearch];
    return YES;
}
@end

@interface NMBottomDockView : UIVisualEffectView
@property (nonatomic, weak) UIViewController *controller;
- (instancetype)initWithController:(UIViewController *)controller;
@end

@implementation NMBottomDockView
- (instancetype)initWithController:(UIViewController *)controller {
    self = [super initWithEffect:[UIBlurEffect effectWithStyle:NMBlurStyle(controller.traitCollection)]];
    if (!self) return nil;
    self.controller = controller;
    self.layer.cornerRadius = 25;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 0.6;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    [self.contentView addSubview:stack];

    NSArray *items = @[
        @[@"message.fill", @"Messages"],
        @[@"person.2.fill", @"Pinned"],
        @[@"bell.fill", @"Alerts"],
        @[@"gearshape.fill", @"Settings"],
    ];
    for (NSArray *item in items) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.accessibilityLabel = item[1];
        button.tintColor = [item[1] isEqualToString:@"Messages"] ? NMPurpleColor() : UIColor.secondaryLabelColor;
        [button setImage:[UIImage systemImageNamed:item[0]] forState:UIControlStateNormal];
        button.imageView.contentMode = UIViewContentModeScaleAspectFit;
        [button addTarget:self action:@selector(itemTapped:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
    }
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8],
        [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
        [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5],
        [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5],
    ]];
    return self;
}
- (void)itemTapped:(UIButton *)sender {
    NSString *name = sender.accessibilityLabel;
    if ([name isEqualToString:@"Settings"]) NMOpenPreferences();
    else if ([name isEqualToString:@"Pinned"]) {
        UITableView *table = NMFindTableView(self.controller.view);
        [table setContentOffset:CGPointMake(0, -table.adjustedContentInset.top) animated:YES];
    } else if ([name isEqualToString:@"Alerts"]) NMShowToast(@"Quiet notifications", @"Next Message uses minimal, non-intrusive alerts.", 3.2);
}
@end

@interface NMSmartReplyBar : UIVisualEffectView
@property (nonatomic, weak) UIView *entryView;
- (instancetype)initWithEntryView:(UIView *)entryView;
@end

@implementation NMSmartReplyBar
- (instancetype)initWithEntryView:(UIView *)entryView {
    self = [super initWithEffect:[UIBlurEffect effectWithStyle:NMBlurStyle(entryView.traitCollection)]];
    if (!self) return nil;
    self.entryView = entryView;
    self.layer.cornerRadius = 19;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = @"✦ Smart Reply";
    label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    label.textColor = NMPurpleColor();
    [self.contentView addSubview:label];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 6;
    stack.distribution = UIStackViewDistributionFillEqually;
    [self.contentView addSubview:stack];

    for (NSString *reply in @[@"Me too!", @"Sounds perfect", @"See you then!"]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.accessibilityLabel = reply;
        button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        button.backgroundColor = [UIColor.secondarySystemFillColor colorWithAlphaComponent:0.55];
        button.layer.cornerRadius = 13;
        [button setTitle:reply forState:UIControlStateNormal];
        [button addTarget:self action:@selector(replyTapped:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
    }
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        [label.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5],
        [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8],
        [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
        [stack.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:3],
        [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
    ]];
    return self;
}
- (void)replyTapped:(UIButton *)sender {
    UITextView *textView = NMFindTextView(self.entryView);
    if (!textView) textView = NMFindTextView(self.entryView.superview);
    if (textView) {
        textView.text = sender.accessibilityLabel;
        [textView becomeFirstResponder];
        [textView.delegate textViewDidChange:textView];
        [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:textView];
    } else NMShowToast(@"Smart Reply", sender.accessibilityLabel, 2.0);
}
@end

static void NMApplyControllerStyle(UIViewController *controller) {
    if (![NMPreferences shared].enabled || !controller.view) return;
    controller.overrideUserInterfaceStyle = NMForcedInterfaceStyle();
    controller.view.backgroundColor = UIColor.clearColor;
    NMInstallBackground(controller);

    UINavigationBar *bar = controller.navigationController.navigationBar;
    if (bar) {
        UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
        [appearance configureWithTransparentBackground];
        appearance.backgroundEffect = [UIBlurEffect effectWithStyle:NMBlurStyle(controller.traitCollection)];
        appearance.backgroundColor = [NMCanvasColor(controller.traitCollection) colorWithAlphaComponent:0.55];
        appearance.shadowColor = UIColor.clearColor;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.labelColor};
        appearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName: UIColor.labelColor};
        bar.standardAppearance = appearance;
        bar.scrollEdgeAppearance = appearance;
        bar.compactAppearance = appearance;
        bar.tintColor = NMPurpleColor();
    }

    for (UIView *view in NMAllSubviews(controller.view)) {
        if ([view isKindOfClass:UITableView.class]) {
            UITableView *table = (UITableView *)view;
            table.backgroundColor = UIColor.clearColor;
            table.separatorStyle = UITableViewCellSeparatorStyleNone;
        } else if ([view isKindOfClass:UICollectionView.class]) {
            UICollectionView *collection = (UICollectionView *)view;
            collection.backgroundColor = UIColor.clearColor;
            collection.layer.cornerRadius = 22;
            collection.layer.cornerCurve = kCACornerCurveContinuous;
        } else if ([view isKindOfClass:UISearchBar.class]) {
            UISearchBar *search = (UISearchBar *)view;
            search.searchTextField.backgroundColor = [UIColor.secondarySystemFillColor colorWithAlphaComponent:0.55];
            search.searchTextField.layer.cornerRadius = 17;
            search.searchTextField.layer.cornerCurve = kCACornerCurveContinuous;
        }
    }
}

static void NMInstallInboxChrome(UIViewController *controller) {
    NMPreferences *prefs = [NMPreferences shared];
    if (!prefs.enabled || !prefs.redesignInbox || !controller.view) return;
    controller.navigationItem.title = @"";

    NMInboxChromeView *header = objc_getAssociatedObject(controller, NMInboxChromeKey);
    if (prefs.enableConceptHeader && !header) {
        header = [[NMInboxChromeView alloc] initWithController:controller];
        [controller.view addSubview:header];
        objc_setAssociatedObject(controller, NMInboxChromeKey, header, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NMBottomDockView *dock = objc_getAssociatedObject(controller, NMDockKey);
    if (prefs.enableBottomDock && !dock) {
        dock = [[NMBottomDockView alloc] initWithController:controller];
        [controller.view addSubview:dock];
        objc_setAssociatedObject(controller, NMDockKey, dock, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIButton *compose = objc_getAssociatedObject(controller, NMComposeKey);
    if (!compose) {
        compose = [UIButton buttonWithType:UIButtonTypeSystem];
        compose.backgroundColor = NMPurpleColor();
        compose.tintColor = UIColor.whiteColor;
        compose.layer.cornerRadius = 28;
        compose.layer.shadowOpacity = 0.35;
        compose.layer.shadowRadius = 12;
        compose.layer.shadowColor = NMPurpleColor().CGColor;
        compose.layer.shadowOffset = CGSizeMake(0, 5);
        [compose setImage:[UIImage systemImageNamed:@"square.and.pencil"] forState:UIControlStateNormal];
        compose.imageView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightSemibold];
        __weak UIViewController *weakController = controller;
        [compose addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
            BOOL invoked = NMInvokeFirstSelector(weakController, @[@"composeButtonClicked:", @"composeButtonPressed:", @"showNewMessageComposition", @"newMessage:", @"composeNewMessage:", @"_composeNewMessage"], compose);
            if (!invoked) NMShowToast(@"New Message", @"Use the stock compose button for this iOS build.", 3.0);
        }] forControlEvents:UIControlEventTouchUpInside];
        [controller.view addSubview:compose];
        objc_setAssociatedObject(controller, NMComposeKey, compose, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIWindow *window = controller.view.window ?: NMKeyWindow();
    CGFloat top = MAX(window.safeAreaInsets.top, 44.0) + 4.0;
    CGFloat bottom = MAX(window.safeAreaInsets.bottom, 8.0);
    CGFloat width = controller.view.bounds.size.width;
    header.hidden = !prefs.enableConceptHeader;
    dock.hidden = !prefs.enableBottomDock;
    if (!header.hidden) header.frame = CGRectMake(12, top, width - 24, 150);
    if (!dock.hidden) dock.frame = CGRectMake(18, controller.view.bounds.size.height - bottom - 62, width - 36, 56);
    compose.frame = CGRectMake(width - 76, controller.view.bounds.size.height - bottom - 132, 56, 56);
    [controller.view bringSubviewToFront:header];
    [controller.view bringSubviewToFront:dock];
    [controller.view bringSubviewToFront:compose];

    UIEdgeInsets insets = controller.additionalSafeAreaInsets;
    insets.top = prefs.enableConceptHeader ? 155 : 0;
    insets.bottom = prefs.enableBottomDock ? 72 : 0;
    controller.additionalSafeAreaInsets = insets;
}

static id NMConversationFromCell(UITableViewCell *cell) {
    return NMSafeValue(cell, @"conversation") ?: NMSafeValue(cell, @"representedConversation") ?: NMSafeValue(cell, @"chat") ?: NMSafeValue(cell, @"representedObject");
}

static BOOL NMConversationLooksUnread(id conversation) {
    id value = NMSafeValue(conversation, @"unreadCount") ?: NMSafeValue(NMChatObjectFromConversation(conversation), @"unreadCount") ?: NMSafeValue(conversation, @"hasUnreadMessages");
    return [value respondsToSelector:@selector(integerValue)] && [value integerValue] > 0;
}

static BOOL NMConversationMatchesFilter(id conversation, UITableViewCell *cell, NSString *filter) {
    if (!filter.length || [filter isEqualToString:@"All"] || [filter isEqualToString:@"More"]) return YES;
    if ([filter isEqualToString:@"Unread"]) return NMConversationLooksUnread(conversation);
    NSString *combined = [NSString stringWithFormat:@"%@ %@", NMConversationDisplayName(conversation, cell), cell.detailTextLabel.text ?: @""].lowercaseString;
    NSArray *workTerms = @[@"team", @"project", @"work", @"office", @"client", @"bank", @"company", @"business", @"otp"];
    BOOL work = NO;
    for (NSString *term in workTerms) if ([combined containsString:term]) { work = YES; break; }
    return [filter isEqualToString:@"Work"] ? work : !work;
}

static BOOL NMInvokeDelete(id controller, NSIndexPath *indexPath, id conversation) {
    for (NSString *name in @[@"deleteConversationAtIndexPath:", @"_deleteConversationAtIndexPath:", @"removeConversationAtIndexPath:"]) {
        SEL selector = NSSelectorFromString(name);
        if ([controller respondsToSelector:selector]) { ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, indexPath); return YES; }
    }
    for (NSString *name in @[@"deleteConversation:", @"_deleteConversation:", @"removeConversation:"]) {
        SEL selector = NSSelectorFromString(name);
        if (conversation && [controller respondsToSelector:selector]) { ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, conversation); return YES; }
    }
    return NO;
}

static UIContextualAction *NMFallbackDeleteAction(id controller, NSIndexPath *indexPath, id conversation) {
    UIContextualAction *action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(__unused UIContextualAction *contextAction, __unused UIView *source, void (^completion)(BOOL)) {
        UIViewController *host = [controller isKindOfClass:UIViewController.class] ? controller : NMTopController();
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Conversation?" message:@"This cannot be undone." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *cancel) { completion(NO); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *confirm) {
            BOOL deleted = NMInvokeDelete(controller, indexPath, conversation);
            completion(deleted);
            if (!deleted) NMShowToast(@"Next Message", @"Delete is not available on this Messages build.", 4.0);
        }]];
        [host presentViewController:alert animated:YES completion:nil];
    }];
    action.image = [UIImage systemImageNamed:@"trash"];
    return action;
}

%hook CKConversationListCell
- (void)layoutSubviews {
    %orig;
    NMPreferences *prefs = [NMPreferences shared];
    UITableViewCell *cell = (UITableViewCell *)self;
    UIVisualEffectView *card = objc_getAssociatedObject(self, NMCardKey);
    if (!prefs.enabled || !prefs.redesignInbox) {
        [card removeFromSuperview];
        objc_setAssociatedObject(self, NMCardKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.clipsToBounds = NO;
    cell.contentView.clipsToBounds = NO;
    cell.separatorInset = UIEdgeInsetsMake(0, CGRectGetWidth(cell.bounds) + 1000, 0, 0);
    if (!card) {
        card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:NMBlurStyle(cell.traitCollection)]];
        card.userInteractionEnabled = NO;
        card.layer.cornerRadius = 20;
        card.layer.cornerCurve = kCACornerCurveContinuous;
        card.layer.masksToBounds = YES;
        card.layer.borderWidth = 0.6;
        card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
        [cell.contentView insertSubview:card atIndex:0];
        objc_setAssociatedObject(self, NMCardKey, card, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        card.effect = [UIBlurEffect effectWithStyle:NMBlurStyle(cell.traitCollection)];
        [cell.contentView sendSubviewToBack:card];
    }
    card.frame = UIEdgeInsetsInsetRect(cell.contentView.bounds, UIEdgeInsetsMake(3, 9, 3, 9));
    UIViewController *controller = NMViewControllerForView(cell);
    NSString *filter = objc_getAssociatedObject(controller, NMFilterKey) ?: @"All";
    BOOL match = NMConversationMatchesFilter(NMConversationFromCell(cell), cell, filter);
    cell.contentView.alpha = match ? 1.0 : 0.22;
}
%end

%hook CKConversationListController
- (void)viewDidLoad {
    %orig;
    if ([NMPreferences shared].redesignInbox) {
        NMApplyControllerStyle((UIViewController *)self);
        NMInstallInboxChrome((UIViewController *)self);
    }
}
- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    if ([NMPreferences shared].redesignInbox) {
        UIViewController *controller = (UIViewController *)self;
        [controller setNeedsStatusBarAppearanceUpdate];
        controller.navigationController.navigationBarHidden = YES;
        NMApplyControllerStyle(controller);
        NMInstallInboxChrome(controller);
    }
}
- (void)viewDidLayoutSubviews {
    %orig;
    if ([NMPreferences shared].redesignInbox) NMInstallInboxChrome((UIViewController *)self);
}
- (void)viewWillDisappear:(BOOL)animated {
    %orig(animated);
    ((UIViewController *)self).navigationController.navigationBarHidden = NO;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig(previousTraitCollection);
    if ([NMPreferences shared].appearanceMode == NMAppearanceModeSystem && [NMPreferences shared].redesignInbox) {
        NMApplyControllerStyle((UIViewController *)self);
        NMInstallInboxChrome((UIViewController *)self);
    }
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UISwipeActionsConfiguration *original = %orig;
    NMPreferences *prefs = [NMPreferences shared];
    if (!prefs.enabled || (!prefs.enableInfoAction && !prefs.enableDeleteAction)) return original;
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    id conversation = NMConversationFromCell(cell);
    NSMutableArray<UIContextualAction *> *actions = [NSMutableArray array];
    if (prefs.enableInfoAction) {
        UIContextualAction *info = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Info" handler:^(__unused UIContextualAction *action, __unused UIView *source, void (^completion)(BOOL)) {
            NMShowConversationInfo(conversation, cell);
            completion(YES);
        }];
        info.image = [UIImage systemImageNamed:@"info.circle"];
        info.backgroundColor = NMPurpleColor();
        [actions addObject:info];
    }
    BOOL hasDelete = NO;
    for (UIContextualAction *action in original.actions ?: @[]) {
        if (action.style == UIContextualActionStyleDestructive || [action.title localizedCaseInsensitiveCompare:@"Delete"] == NSOrderedSame) hasDelete = YES;
        [actions addObject:action];
    }
    if (prefs.enableDeleteAction && !hasDelete) [actions addObject:NMFallbackDeleteAction(self, indexPath, conversation)];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:actions];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}
%end

%hook CKTranscriptCollectionViewController
- (void)viewDidLoad {
    %orig;
    if ([NMPreferences shared].redesignConversation) NMApplyControllerStyle((UIViewController *)self);
}
- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    UIViewController *controller = (UIViewController *)self;
    controller.navigationController.navigationBarHidden = NO;
    if ([NMPreferences shared].redesignConversation) NMApplyControllerStyle(controller);
}
- (void)viewDidLayoutSubviews {
    %orig;
    if ([NMPreferences shared].redesignConversation) NMApplyControllerStyle((UIViewController *)self);
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig(previousTraitCollection);
    if ([NMPreferences shared].appearanceMode == NMAppearanceModeSystem && [NMPreferences shared].redesignConversation) NMApplyControllerStyle((UIViewController *)self);
}
%end

%hook CKBalloonView
- (void)layoutSubviews {
    %orig;
    if (![NMPreferences shared].enabled || ![NMPreferences shared].redesignConversation) return;
    UIView *view = (UIView *)self;
    view.layer.cornerRadius = 21;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.masksToBounds = YES;
    BOOL outgoing = CGRectGetMidX(view.frame) > CGRectGetWidth(view.superview.bounds) * 0.52;
    CAGradientLayer *gradient = objc_getAssociatedObject(self, NMBalloonGradientKey);
    if (!gradient) {
        gradient = [CAGradientLayer layer];
        gradient.startPoint = CGPointMake(0, 0);
        gradient.endPoint = CGPointMake(1, 1);
        [view.layer insertSublayer:gradient atIndex:0];
        objc_setAssociatedObject(self, NMBalloonGradientKey, gradient, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    gradient.frame = view.bounds;
    gradient.cornerRadius = 21;
    gradient.colors = outgoing
        ? @[(id)NMBlueColor().CGColor, (id)NMPurpleColor().CGColor]
        : @[(id)[UIColor colorWithWhite:0.20 alpha:0.72].CGColor, (id)[UIColor colorWithWhite:0.12 alpha:0.62].CGColor];
    gradient.opacity = outgoing ? 0.88 : 0.40;
    view.layer.borderWidth = 0.5;
    view.layer.borderColor = [UIColor colorWithWhite:1 alpha:outgoing ? 0.20 : 0.10].CGColor;
}
%end

%hook CKMessageEntryView
- (void)layoutSubviews {
    %orig;
    NMPreferences *prefs = [NMPreferences shared];
    if (!prefs.enabled || !prefs.redesignConversation) return;
    UIView *entry = (UIView *)self;
    entry.layer.cornerRadius = 23;
    entry.layer.cornerCurve = kCACornerCurveContinuous;
    entry.layer.masksToBounds = NO;
    entry.layer.borderWidth = 0.5;
    entry.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
    entry.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.72];

    NMSmartReplyBar *bar = objc_getAssociatedObject(self, NMSmartBarKey);
    if (prefs.enableSmartReplies && entry.superview) {
        if (!bar) {
            bar = [[NMSmartReplyBar alloc] initWithEntryView:entry];
            [entry.superview addSubview:bar];
            objc_setAssociatedObject(self, NMSmartBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        bar.hidden = NO;
        bar.frame = CGRectMake(12, MAX(0, CGRectGetMinY(entry.frame) - 61), CGRectGetWidth(entry.superview.bounds) - 24, 55);
        [entry.superview bringSubviewToFront:bar];
        [entry.superview bringSubviewToFront:entry];
    } else bar.hidden = YES;
}
%end

static void NMPreferencesDidChange(__unused CFNotificationCenterRef center, __unused void *observer, __unused CFStringRef name, __unused const void *object, __unused CFDictionaryRef userInfo) {
    [[NMPreferences shared] reload];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *controller = NMTopController();
        if (controller) {
            controller.overrideUserInterfaceStyle = NMForcedInterfaceStyle();
            NMApplyControllerStyle(controller);
            [controller.view setNeedsLayout];
            [controller.view layoutIfNeeded];
        }
    });
}

%ctor {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.MobileSMS"]) return;
        [NMPreferences shared];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NMPreferencesDidChange, NMPrefsChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
