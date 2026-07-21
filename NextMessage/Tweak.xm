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
    NSNumber *appearance = NMPreferenceValue(@"AppearanceMode");

    self.enabled = enabled ? enabled.boolValue : YES;
    self.redesignInbox = inbox ? inbox.boolValue : YES;
    self.redesignConversation = conversation ? conversation.boolValue : YES;
    self.enableToasts = toasts ? toasts.boolValue : YES;
    self.enableInfoAction = info ? info.boolValue : YES;
    self.enableDeleteAction = deleteAction ? deleteAction.boolValue : YES;
    self.appearanceMode = appearance ? (NMAppearanceMode)appearance.integerValue : NMAppearanceModeSystem;
}

@end

static UIUserInterfaceStyle NMForcedInterfaceStyle(void) {
    switch ([NMPreferences shared].appearanceMode) {
        case NMAppearanceModeLight:
            return UIUserInterfaceStyleLight;
        case NMAppearanceModeBlack:
            return UIUserInterfaceStyleDark;
        default:
            return UIUserInterfaceStyleUnspecified;
    }
}

static BOOL NMUsesDarkAppearance(UITraitCollection *traits) {
    NMAppearanceMode mode = [NMPreferences shared].appearanceMode;
    if (mode == NMAppearanceModeBlack) return YES;
    if (mode == NMAppearanceModeLight) return NO;
    return traits.userInterfaceStyle == UIUserInterfaceStyleDark;
}

static UIColor *NMCanvasColor(UITraitCollection *traits) {
    if ([NMPreferences shared].appearanceMode == NMAppearanceModeBlack) {
        return UIColor.blackColor;
    }
    return NMUsesDarkAppearance(traits)
        ? [UIColor colorWithWhite:0.025 alpha:1.0]
        : [UIColor colorWithWhite:0.975 alpha:1.0];
}

static UIBlurEffectStyle NMBlurStyle(UITraitCollection *traits) {
    return NMUsesDarkAppearance(traits)
        ? UIBlurEffectStyleSystemUltraThinMaterialDark
        : UIBlurEffectStyleSystemUltraThinMaterialLight;
}

static id NMSafeValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *NMSafeString(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = NMSafeValue(object, key);
        if ([value isKindOfClass:NSString.class] && [value length] > 0) {
            return value;
        }
        if ([value respondsToSelector:@selector(stringValue)]) {
            NSString *string = [value stringValue];
            if (string.length > 0) return string;
        }
    }
    return nil;
}

static UIViewController *NMTopControllerFrom(UIViewController *controller) {
    if (!controller) return nil;
    if (controller.presentedViewController) {
        return NMTopControllerFrom(controller.presentedViewController);
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        return NMTopControllerFrom(((UINavigationController *)controller).visibleViewController);
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        return NMTopControllerFrom(((UITabBarController *)controller).selectedViewController);
    }
    return controller;
}

static UIViewController *NMTopController(void) {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        if (keyWindow) break;
    }
    if (!keyWindow) keyWindow = UIApplication.sharedApplication.windows.firstObject;
    return NMTopControllerFrom(keyWindow.rootViewController);
}

static void NMDismissToast(UIView *toast) {
    if (!toast || !toast.superview) return;
    [UIView animateWithDuration:0.22 animations:^{
        toast.alpha = 0.0;
        toast.transform = CGAffineTransformMakeTranslation(0, 20);
    } completion:^(__unused BOOL finished) {
        [toast removeFromSuperview];
    }];
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
        container.layer.borderWidth = 0.5;
        container.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;

        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:NMBlurStyle(host.traitCollection)]];
        blur.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:blur];

        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"info.circle.fill"]];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.tintColor = [UIColor colorWithRed:0.52 green:0.39 blue:1.0 alpha:1.0];
        icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];
        [container addSubview:icon];

        UILabel *titleLabel = [UILabel new];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        titleLabel.text = title ?: @"Next Message";
        titleLabel.numberOfLines = 1;
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

            [icon.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
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
        [closeButton addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
            NMDismissToast(weakToast);
        }] forControlEvents:UIControlEventTouchUpInside];

        container.alpha = 0.0;
        container.transform = CGAffineTransformMakeTranslation(0, 24);
        [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.84 initialSpringVelocity:0.3 options:UIViewAnimationOptionCurveEaseOut animations:^{
            container.alpha = 1.0;
            container.transform = CGAffineTransformIdentity;
        } completion:nil];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NMDismissToast(weakToast);
        });
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
    if (!identifier) {
        identifier = NMSafeString(conversation, @[@"guid", @"chatGUID", @"chatIdentifier", @"identifier"]);
    }
    return identifier;
}

static NSString *NMConversationDisplayName(id conversation, UITableViewCell *cell) {
    id chat = NMChatObjectFromConversation(conversation);
    NSString *name = NMSafeString(conversation, @[@"displayName", @"name", @"title"]);
    if (!name) name = NMSafeString(chat, @[@"displayName", @"name", @"title"]);
    if (!name) name = cell.textLabel.text;
    return name.length > 0 ? name : @"Conversation details";
}

static NSDictionary<NSString *, id> *NMConversationStats(id conversation) {
    NSString *identifier = NMConversationIdentifier(conversation);
    long long count = 0;
    NSDate *firstDate = nil;

    if (identifier.length > 0) {
        sqlite3 *database = NULL;
        NSString *databasePath = @"/var/mobile/Library/SMS/sms.db";
        if (sqlite3_open_v2(databasePath.fileSystemRepresentation, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL) == SQLITE_OK) {
            const char *query =
                "SELECT COUNT(m.ROWID), MIN(CASE WHEN m.date > 0 THEN m.date ELSE NULL END) "
                "FROM chat c "
                "LEFT JOIN chat_message_join cmj ON cmj.chat_id = c.ROWID "
                "LEFT JOIN message m ON m.ROWID = cmj.message_id "
                "WHERE c.guid = ?1 OR c.chat_identifier = ?1";
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

    return @{
        @"count": @(MAX(count, 0)),
        @"firstDate": firstDate ?: NSNull.null,
        @"identifier": identifier ?: @"Unavailable",
    };
}

static void NMShowConversationInfo(id conversation, UITableViewCell *cell) {
    NSDictionary *stats = NMConversationStats(conversation);
    NSNumber *count = stats[@"count"];
    id dateObject = stats[@"firstDate"];

    NSString *dateText = @"Not available";
    if ([dateObject isKindOfClass:NSDate.class]) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
        dateText = [formatter stringFromDate:dateObject];
    }

    NSString *message = [NSString stringWithFormat:@"Messages in this conversation: %@\nFirst conversation date: %@", count, dateText];
    NMShowToast(NMConversationDisplayName(conversation, cell), message, 8.0);
}

static void NMApplyControllerStyle(UIViewController *controller) {
    if (![NMPreferences shared].enabled) return;

    controller.overrideUserInterfaceStyle = NMForcedInterfaceStyle();
    controller.view.backgroundColor = NMCanvasColor(controller.traitCollection);

    UINavigationBar *navigationBar = controller.navigationController.navigationBar;
    if (navigationBar) {
        UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
        [appearance configureWithTransparentBackground];
        appearance.backgroundEffect = [UIBlurEffect effectWithStyle:NMBlurStyle(controller.traitCollection)];
        appearance.backgroundColor = [NMCanvasColor(controller.traitCollection) colorWithAlphaComponent:0.72];
        appearance.shadowColor = UIColor.clearColor;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.labelColor};
        appearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName: UIColor.labelColor};
        navigationBar.standardAppearance = appearance;
        navigationBar.scrollEdgeAppearance = appearance;
        navigationBar.compactAppearance = appearance;
        navigationBar.tintColor = [UIColor colorWithRed:0.48 green:0.36 blue:1.0 alpha:1.0];
    }

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:controller.view];
    while (queue.count > 0) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        [queue addObjectsFromArray:view.subviews];

        if ([view isKindOfClass:UITableView.class]) {
            UITableView *tableView = (UITableView *)view;
            tableView.backgroundColor = UIColor.clearColor;
            tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        } else if ([view isKindOfClass:UICollectionView.class]) {
            ((UICollectionView *)view).backgroundColor = UIColor.clearColor;
        }
    }
}

static id NMConversationFromCell(UITableViewCell *cell) {
    return NMSafeValue(cell, @"conversation")
        ?: NMSafeValue(cell, @"representedConversation")
        ?: NMSafeValue(cell, @"chat")
        ?: NMSafeValue(cell, @"representedObject");
}

static BOOL NMInvokeDelete(id controller, NSIndexPath *indexPath, id conversation) {
    NSArray<NSString *> *indexSelectors = @[@"deleteConversationAtIndexPath:", @"_deleteConversationAtIndexPath:", @"removeConversationAtIndexPath:"];
    for (NSString *selectorName in indexSelectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([controller respondsToSelector:selector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, indexPath);
            return YES;
        }
    }

    NSArray<NSString *> *conversationSelectors = @[@"deleteConversation:", @"_deleteConversation:", @"removeConversation:"];
    for (NSString *selectorName in conversationSelectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if (conversation && [controller respondsToSelector:selector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, conversation);
            return YES;
        }
    }
    return NO;
}

static UIContextualAction *NMFallbackDeleteAction(id controller, NSIndexPath *indexPath, id conversation) {
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        UIViewController *host = [controller isKindOfClass:UIViewController.class] ? controller : NMTopController();
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Conversation?" message:@"This uses the stock Messages deletion method and cannot be undone." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *cancelAction) {
            completionHandler(NO);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *confirmAction) {
            BOOL deleted = NMInvokeDelete(controller, indexPath, conversation);
            completionHandler(deleted);
            if (!deleted) NMShowToast(@"Next Message", @"Delete is not available on this Messages build.", 4.0);
        }]];
        [host presentViewController:alert animated:YES completion:nil];
    }];
    deleteAction.image = [UIImage systemImageNamed:@"trash"];
    return deleteAction;
}

static const void *NMConversationCardKey = &NMConversationCardKey;

%hook CKConversationListCell

- (void)layoutSubviews {
    %orig;

    NMPreferences *preferences = [NMPreferences shared];
    UITableViewCell *cell = (UITableViewCell *)self;
    UIVisualEffectView *card = objc_getAssociatedObject(self, NMConversationCardKey);

    if (!preferences.enabled || !preferences.redesignInbox) {
        [card removeFromSuperview];
        objc_setAssociatedObject(self, NMConversationCardKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
        card.layer.cornerRadius = 18.0;
        card.layer.cornerCurve = kCACornerCurveContinuous;
        card.layer.masksToBounds = YES;
        card.layer.borderWidth = 0.5;
        card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
        [cell.contentView insertSubview:card atIndex:0];
        objc_setAssociatedObject(self, NMConversationCardKey, card, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        card.effect = [UIBlurEffect effectWithStyle:NMBlurStyle(cell.traitCollection)];
        [cell.contentView sendSubviewToBack:card];
    }

    card.frame = UIEdgeInsetsInsetRect(cell.contentView.bounds, UIEdgeInsetsMake(4, 9, 4, 9));
}

%end

%hook CKConversationListController

- (void)viewDidLoad {
    %orig;
    if ([NMPreferences shared].redesignInbox) NMApplyControllerStyle((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    if ([NMPreferences shared].redesignInbox) NMApplyControllerStyle((UIViewController *)self);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig(previousTraitCollection);
    if ([NMPreferences shared].appearanceMode == NMAppearanceModeSystem && [NMPreferences shared].redesignInbox) {
        NMApplyControllerStyle((UIViewController *)self);
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UISwipeActionsConfiguration *original = %orig;
    NMPreferences *preferences = [NMPreferences shared];
    if (!preferences.enabled || (!preferences.enableInfoAction && !preferences.enableDeleteAction)) return original;

    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    id conversation = NMConversationFromCell(cell);
    NSMutableArray<UIContextualAction *> *actions = [NSMutableArray array];

    if (preferences.enableInfoAction) {
        UIContextualAction *infoAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Info" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
            NMShowConversationInfo(conversation, cell);
            completionHandler(YES);
        }];
        infoAction.image = [UIImage systemImageNamed:@"info.circle"];
        infoAction.backgroundColor = [UIColor colorWithRed:0.48 green:0.36 blue:1.0 alpha:1.0];
        [actions addObject:infoAction];
    }

    BOOL hasDelete = NO;
    for (UIContextualAction *action in original.actions ?: @[]) {
        if (action.style == UIContextualActionStyleDestructive || [action.title localizedCaseInsensitiveCompare:@"Delete"] == NSOrderedSame) {
            hasDelete = YES;
        }
        [actions addObject:action];
    }

    if (preferences.enableDeleteAction && !hasDelete) {
        [actions addObject:NMFallbackDeleteAction(self, indexPath, conversation)];
    }

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
    if ([NMPreferences shared].redesignConversation) NMApplyControllerStyle((UIViewController *)self);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig(previousTraitCollection);
    if ([NMPreferences shared].appearanceMode == NMAppearanceModeSystem && [NMPreferences shared].redesignConversation) {
        NMApplyControllerStyle((UIViewController *)self);
    }
}

%end

%hook CKBalloonView

- (void)layoutSubviews {
    %orig;
    if (![NMPreferences shared].enabled || ![NMPreferences shared].redesignConversation) return;
    UIView *view = (UIView *)self;
    view.layer.cornerRadius = 19.0;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.masksToBounds = YES;
}

%end

%hook CKMessageEntryView

- (void)layoutSubviews {
    %orig;
    if (![NMPreferences shared].enabled || ![NMPreferences shared].redesignConversation) return;
    UIView *view = (UIView *)self;
    view.layer.cornerRadius = 22.0;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.masksToBounds = YES;
}

%end

static void NMPreferencesDidChange(__unused CFNotificationCenterRef center, __unused void *observer, __unused CFStringRef name, __unused const void *object, __unused CFDictionaryRef userInfo) {
    [[NMPreferences shared] reload];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *controller = NMTopController();
        if (controller) NMApplyControllerStyle(controller);
        [controller.view setNeedsLayout];
        [controller.view layoutIfNeeded];
    });
}

%ctor {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.MobileSMS"]) return;
        [NMPreferences shared];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NMPreferencesDidChange, NMPrefsChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
