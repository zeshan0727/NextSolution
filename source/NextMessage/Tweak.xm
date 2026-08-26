#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sqlite3.h>

static NSString * const NMDomain = @"com.nextsolution.nextmessage";
static NSString * const NMNotification = @"com.nextsolution.nextmessage/preferences.changed";
static const NSInteger NMBackgroundTag = 727210;
static const NSInteger NMCardTag = 727211;

static BOOL nmEnabled = YES;
static BOOL nmConversationCards = YES;
static BOOL nmGlassBackground = YES;
static BOOL nmBubbleStyling = YES;
static BOOL nmInputStyling = YES;
static BOOL nmDetailsSwipe = YES;
static BOOL nmShowMessageCount = YES;
static BOOL nmShowFirstDate = YES;
static BOOL nmDeleteFromCard = YES;
static BOOL nmHaptics = YES;
static BOOL nmAnimations = YES;
static CGFloat nmCardOpacity = 0.96;
static CGFloat nmCornerRadius = 18.0;

@interface CKConversationListViewController : UIViewController
- (UITableView *)tableView;
@end

@interface CKConversationViewController : UIViewController
@end

static BOOL NMIsMessagesProcess(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.MobileSMS"];
}

static UIColor *NMColor(uint32_t hex, CGFloat alpha) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:alpha];
}

static id NMSafeValue(id object, NSString *key) {
    if (!object || !key.length) return nil;
    @try { return [object valueForKey:key]; }
    @catch (__unused NSException *exception) { return nil; }
}

static BOOL NMPreferenceBool(NSString *key, BOOL fallback) {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                           (__bridge CFStringRef)NMDomain));
    return value ? [value boolValue] : fallback;
}

static CGFloat NMPreferenceFloat(NSString *key, CGFloat fallback) {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                           (__bridge CFStringRef)NMDomain));
    return value ? [value doubleValue] : fallback;
}

static void NMLoadPreferences(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NMDomain);
    nmEnabled = NMPreferenceBool(@"enabled", YES);
    nmConversationCards = NMPreferenceBool(@"conversationCards", YES);
    nmGlassBackground = NMPreferenceBool(@"glassBackground", YES);
    nmBubbleStyling = NMPreferenceBool(@"bubbleStyling", YES);
    nmInputStyling = NMPreferenceBool(@"inputStyling", YES);
    nmDetailsSwipe = NMPreferenceBool(@"detailsSwipe", YES);
    nmShowMessageCount = NMPreferenceBool(@"showMessageCount", YES);
    nmShowFirstDate = NMPreferenceBool(@"showFirstDate", YES);
    nmDeleteFromCard = NMPreferenceBool(@"deleteFromCard", YES);
    nmHaptics = NMPreferenceBool(@"haptics", YES);
    nmAnimations = NMPreferenceBool(@"animations", YES);
    nmCardOpacity = MIN(MAX(NMPreferenceFloat(@"cardOpacity", 0.96), 0.68), 1.0);
    nmCornerRadius = MIN(MAX(NMPreferenceFloat(@"cornerRadius", 18.0), 12.0), 28.0);
}

static void NMPreferencesChanged(__unused CFNotificationCenterRef center,
                                 __unused void *observer,
                                 __unused CFStringRef name,
                                 __unused const void *object,
                                 __unused CFDictionaryRef userInfo) {
    NMLoadPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NMRefreshTheme" object:nil];
    });
}

static void NMHaptic(BOOL warning) {
    if (!nmHaptics) return;
    if (warning) {
        UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
        [generator notificationOccurred:UINotificationFeedbackTypeWarning];
    } else {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [generator impactOccurred];
    }
}

static void NMCollectLabels(UIView *view, NSMutableArray<UILabel *> *labels) {
    if ([view isKindOfClass:UILabel.class]) [labels addObject:(UILabel *)view];
    for (UIView *subview in view.subviews) NMCollectLabels(subview, labels);
}

static NSArray<NSString *> *NMCandidatesForCell(UITableViewCell *cell) {
    NSMutableOrderedSet<NSString *> *values = [NSMutableOrderedSet orderedSet];
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    NMCollectLabels(cell.contentView, labels);
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        if (CGRectGetMinY(a.frame) < CGRectGetMinY(b.frame)) return NSOrderedAscending;
        if (CGRectGetMinY(a.frame) > CGRectGetMinY(b.frame)) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    for (UILabel *label in labels) {
        NSString *text = [label.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length > 1 && text.length < 160) [values addObject:text];
    }
    for (NSString *key in @[@"conversation", @"_conversation", @"chat", @"_chat", @"conversationListItem", @"_conversationListItem", @"model", @"_model"]) {
        id model = NMSafeValue(cell, key);
        for (NSString *modelKey in @[@"chatIdentifier", @"displayName", @"name", @"guid", @"identifier"]) {
            id value = NMSafeValue(model, modelKey);
            if ([value isKindOfClass:NSString.class] && [value length]) [values addObject:value];
        }
    }
    return values.array;
}

static id NMConversationModelForCell(UITableViewCell *cell) {
    for (NSString *key in @[@"conversation", @"_conversation", @"chat", @"_chat", @"conversationListItem", @"_conversationListItem", @"model", @"_model"]) {
        id model = NMSafeValue(cell, key);
        if (model) return model;
    }
    return nil;
}

static NSDate *NMDateFromNumericValue(NSNumber *number) {
    if (![number isKindOfClass:NSNumber.class]) return nil;
    double raw = number.doubleValue;
    if (raw <= 0) return nil;
    if (raw > 1000000000000.0) raw /= 1000000000.0;
    if (raw > 1300000000.0) return [NSDate dateWithTimeIntervalSince1970:raw];
    return [NSDate dateWithTimeIntervalSince1970:(raw + 978307200.0)];
}

static BOOL NMQueryDatabaseStats(NSArray<NSString *> *candidates, NSInteger *messageCount, NSDate **firstDate, NSString **resolvedIdentifier) {
    sqlite3 *database = NULL;
    const char *paths[] = {"/private/var/mobile/Library/SMS/sms.db", "/var/mobile/Library/SMS/sms.db"};
    for (NSUInteger i = 0; i < 2 && !database; i++) {
        if (sqlite3_open_v2(paths[i], &database, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
            if (database) sqlite3_close(database);
            database = NULL;
        }
    }
    if (!database) return NO;

    const char *sql =
        "SELECT COUNT(cmj.message_id), MIN(m.date), COALESCE(c.chat_identifier, c.guid, c.display_name) "
        "FROM chat c "
        "LEFT JOIN chat_message_join cmj ON cmj.chat_id = c.ROWID "
        "LEFT JOIN message m ON m.ROWID = cmj.message_id "
        "WHERE lower(c.chat_identifier)=lower(?) OR lower(c.guid)=lower(?) OR lower(c.display_name)=lower(?) "
        "GROUP BY c.ROWID ORDER BY MAX(m.date) DESC LIMIT 1";

    BOOL found = NO;
    for (NSString *candidate in candidates) {
        if (candidate.length < 2) continue;
        sqlite3_stmt *statement = NULL;
        if (sqlite3_prepare_v2(database, sql, -1, &statement, NULL) != SQLITE_OK) continue;
        const char *utf8 = candidate.UTF8String;
        sqlite3_bind_text(statement, 1, utf8, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 2, utf8, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 3, utf8, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(statement) == SQLITE_ROW) {
            if (messageCount) *messageCount = sqlite3_column_int64(statement, 0);
            if (firstDate && sqlite3_column_type(statement, 1) != SQLITE_NULL) {
                *firstDate = NMDateFromNumericValue(@(sqlite3_column_int64(statement, 1)));
            }
            if (resolvedIdentifier && sqlite3_column_type(statement, 2) != SQLITE_NULL) {
                const unsigned char *text = sqlite3_column_text(statement, 2);
                if (text) *resolvedIdentifier = [NSString stringWithUTF8String:(const char *)text];
            }
            found = YES;
        }
        sqlite3_finalize(statement);
        if (found) break;
    }
    sqlite3_close(database);
    return found;
}

static NSInteger NMFallbackMessageCount(id model) {
    for (NSString *key in @[@"messageCount", @"messagesCount", @"numberOfMessages", @"unreadCount"]) {
        id value = NMSafeValue(model, key);
        if ([value respondsToSelector:@selector(integerValue)]) {
            NSInteger count = [value integerValue];
            if (count >= 0) return count;
        }
    }
    for (NSString *key in @[@"messages", @"allMessages", @"transcriptItems", @"items"]) {
        id value = NMSafeValue(model, key);
        if ([value respondsToSelector:@selector(count)]) return [value count];
    }
    return NSNotFound;
}

static NSDate *NMFallbackFirstDate(id model) {
    for (NSString *key in @[@"firstMessageDate", @"dateOfFirstMessage", @"creationDate", @"startDate", @"date"]) {
        id value = NMSafeValue(model, key);
        if ([value isKindOfClass:NSDate.class]) return value;
        if ([value isKindOfClass:NSNumber.class]) return NMDateFromNumericValue(value);
    }
    return nil;
}

static NSString *NMReadableDate(NSDate *date) {
    if (!date) return @"Not available";
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
    });
    return [formatter stringFromDate:date] ?: @"Not available";
}

@interface NMConversationDetailsController : UIViewController
@property(nonatomic,copy) NSString *conversationTitle;
@property(nonatomic,copy) NSString *identifierText;
@property(nonatomic,copy) NSString *messageCountText;
@property(nonatomic,copy) NSString *firstDateText;
@property(nonatomic,copy) dispatch_block_t deleteHandler;
@property(nonatomic) BOOL allowDelete;
@property(nonatomic,strong) UIView *card;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *identifierLabel;
@property(nonatomic,strong) UILabel *countLabel;
@property(nonatomic,strong) UILabel *dateLabel;
@property(nonatomic,strong) UIButton *deleteButton;
@property(nonatomic,strong) UIButton *closeButton;
@end

@implementation NMConversationDetailsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.70];

    self.card = [[UIView alloc] init];
    self.card.backgroundColor = NMColor(0x10182E, 0.98);
    self.card.layer.cornerRadius = 28;
    self.card.layer.cornerCurve = kCACornerCurveContinuous;
    self.card.layer.borderWidth = 1;
    self.card.layer.borderColor = NMColor(0x8C98B8, 0.30).CGColor;
    self.card.layer.shadowColor = UIColor.blackColor.CGColor;
    self.card.layer.shadowOpacity = 0.45;
    self.card.layer.shadowRadius = 28;
    self.card.layer.shadowOffset = CGSizeMake(0, 12);
    [self.view addSubview:self.card];

    CAGradientLayer *strip = [CAGradientLayer layer];
    strip.name = @"NMDetailStrip";
    strip.colors = @[(id)NMColor(0xFF5B61,1).CGColor, (id)NMColor(0x6F63FF,1).CGColor, (id)NMColor(0x18C8B7,1).CGColor];
    strip.startPoint = CGPointMake(0, 0.5);
    strip.endPoint = CGPointMake(1, 0.5);
    strip.cornerRadius = 3;
    [self.card.layer addSublayer:strip];

    UILabel *(^makeLabel)(UIFont *, UIColor *) = ^UILabel *(UIFont *font, UIColor *color) {
        UILabel *label = [[UILabel alloc] init];
        label.font = font;
        label.textColor = color;
        label.numberOfLines = 0;
        return label;
    };

    self.titleLabel = makeLabel([UIFont systemFontOfSize:26 weight:UIFontWeightBold], UIColor.whiteColor);
    self.titleLabel.text = self.conversationTitle.length ? self.conversationTitle : @"Conversation Details";
    [self.card addSubview:self.titleLabel];

    self.identifierLabel = makeLabel([UIFont systemFontOfSize:14 weight:UIFontWeightMedium], NMColor(0xAEBBD5,1));
    self.identifierLabel.text = self.identifierText.length ? self.identifierText : @"Messages conversation";
    [self.card addSubview:self.identifierLabel];

    self.countLabel = makeLabel([UIFont systemFontOfSize:18 weight:UIFontWeightSemibold], UIColor.whiteColor);
    self.countLabel.text = [NSString stringWithFormat:@"Messages\n%@", self.messageCountText ?: @"Not available"];
    [self.card addSubview:self.countLabel];

    self.dateLabel = makeLabel([UIFont systemFontOfSize:18 weight:UIFontWeightSemibold], UIColor.whiteColor);
    self.dateLabel.text = [NSString stringWithFormat:@"First message\n%@", self.firstDateText ?: @"Not available"];
    [self.card addSubview:self.dateLabel];

    self.deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.deleteButton setTitle:@"Delete Conversation" forState:UIControlStateNormal];
    [self.deleteButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.deleteButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    self.deleteButton.backgroundColor = NMColor(0xE93856, 1);
    self.deleteButton.layer.cornerRadius = 17;
    self.deleteButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.deleteButton.hidden = !self.allowDelete;
    [self.deleteButton addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.card addSubview:self.deleteButton];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.closeButton setTitle:@"Close" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.closeButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.closeButton.backgroundColor = NMColor(0x273450, 1);
    self.closeButton.layer.cornerRadius = 17;
    self.closeButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.card addSubview:self.closeButton];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (nmAnimations) {
        self.card.transform = CGAffineTransformMakeScale(0.88, 0.88);
        self.card.alpha = 0;
        [UIView animateWithDuration:0.30 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0 options:0 animations:^{
            self.card.transform = CGAffineTransformIdentity;
            self.card.alpha = 1;
        } completion:nil];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = MIN(CGRectGetWidth(self.view.bounds) - 34, 390);
    CGFloat height = self.allowDelete ? 430 : 360;
    self.card.frame = CGRectMake((CGRectGetWidth(self.view.bounds)-width)/2,
                                 (CGRectGetHeight(self.view.bounds)-height)/2,
                                 width, height);
    for (CALayer *layer in self.card.layer.sublayers) {
        if ([layer.name isEqualToString:@"NMDetailStrip"]) layer.frame = CGRectMake(24, 20, width-48, 6);
    }
    self.titleLabel.frame = CGRectMake(24, 46, width-48, 68);
    self.identifierLabel.frame = CGRectMake(24, 110, width-48, 42);
    self.countLabel.frame = CGRectMake(24, 166, width-48, 70);
    self.dateLabel.frame = CGRectMake(24, 244, width-48, 74);
    if (self.allowDelete) {
        self.deleteButton.frame = CGRectMake(24, height-104, width-48, 52);
        self.closeButton.frame = CGRectMake(24, height-48, width-48, 42);
    } else {
        self.closeButton.frame = CGRectMake(24, height-72, width-48, 48);
    }
}

- (void)deleteTapped {
    NMHaptic(YES);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Conversation?"
                                                                   message:@"This removes the complete conversation from Messages. This action cannot be undone."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        if (weakSelf.deleteHandler) weakSelf.deleteHandler();
        [weakSelf dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)closeTapped {
    NMHaptic(NO);
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

static void NMApplyControllerTheme(UIViewController *controller) {
    if (!nmEnabled || !controller.view) return;
    controller.view.backgroundColor = NMColor(0x050914, 1);

    UIView *background = [controller.view viewWithTag:NMBackgroundTag];
    if (!background && nmGlassBackground) {
        background = [[UIView alloc] initWithFrame:controller.view.bounds];
        background.tag = NMBackgroundTag;
        background.userInteractionEnabled = NO;
        CAGradientLayer *gradient = [CAGradientLayer layer];
        gradient.name = @"NMMainGradient";
        gradient.colors = @[(id)NMColor(0x050914,1).CGColor,
                            (id)NMColor(0x10122B,1).CGColor,
                            (id)NMColor(0x071C25,1).CGColor];
        gradient.locations = @[@0, @0.58, @1];
        gradient.startPoint = CGPointMake(0,0);
        gradient.endPoint = CGPointMake(1,1);
        [background.layer addSublayer:gradient];
        [controller.view insertSubview:background atIndex:0];
    }
    background.frame = controller.view.bounds;
    for (CALayer *layer in background.layer.sublayers) layer.frame = background.bounds;

    UINavigationBar *bar = controller.navigationController.navigationBar;
    if (bar) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = NMColor(0x081126, 0.88);
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor,
                                           NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightBold]};
        appearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor,
                                                NSFontAttributeName: [UIFont systemFontOfSize:34 weight:UIFontWeightBold]};
        bar.standardAppearance = appearance;
        bar.scrollEdgeAppearance = appearance;
        bar.compactAppearance = appearance;
        bar.tintColor = NMColor(0x64DCCB, 1);
    }
}

static void NMStyleConversationCell(UITableViewCell *cell) {
    if (!nmEnabled || !nmConversationCards || !cell.window) return;
    NSString *className = NSStringFromClass(cell.class);
    if ([className rangeOfString:@"Conversation" options:NSCaseInsensitiveSearch].location == NSNotFound &&
        [className rangeOfString:@"CK" options:NSCaseInsensitiveSearch].location == NSNotFound) return;

    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    UIView *card = [cell.contentView viewWithTag:NMCardTag];
    if (!card) {
        card = [[UIView alloc] init];
        card.tag = NMCardTag;
        card.userInteractionEnabled = NO;
        card.layer.cornerCurve = kCACornerCurveContinuous;
        card.layer.borderWidth = 0.8;
        card.layer.shadowColor = UIColor.blackColor.CGColor;
        card.layer.shadowOpacity = 0.22;
        card.layer.shadowRadius = 10;
        card.layer.shadowOffset = CGSizeMake(0, 4);
        CAGradientLayer *gradient = [CAGradientLayer layer];
        gradient.name = @"NMCellGradient";
        [card.layer addSublayer:gradient];
        [cell.contentView insertSubview:card atIndex:0];
    }
    card.frame = CGRectInset(cell.contentView.bounds, 10, 5);
    card.layer.cornerRadius = nmCornerRadius;
    card.layer.borderColor = NMColor(0x7182AA, 0.24).CGColor;
    card.alpha = nmCardOpacity;
    for (CALayer *layer in card.layer.sublayers) {
        if ([layer.name isEqualToString:@"NMCellGradient"]) {
            CAGradientLayer *gradient = (CAGradientLayer *)layer;
            gradient.frame = card.bounds;
            gradient.cornerRadius = nmCornerRadius;
            gradient.colors = @[(id)NMColor(0x172544,1).CGColor,
                                (id)NMColor(0x111A33,1).CGColor,
                                (id)NMColor(0x18213C,1).CGColor];
            gradient.startPoint = CGPointMake(0,0.5);
            gradient.endPoint = CGPointMake(1,0.5);
        }
    }

    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    NMCollectLabels(cell.contentView, labels);
    for (UILabel *label in labels) {
        if ([label.textColor getWhite:NULL alpha:NULL]) {
            label.textColor = label.font.pointSize >= 16 ? UIColor.whiteColor : NMColor(0xAEBBD5,1);
        }
    }
}

static void NMStyleRuntimeView(UIView *view) {
    if (!nmEnabled || !view.window) return;
    NSString *name = NSStringFromClass(view.class);

    if (nmBubbleStyling && [name rangeOfString:@"Balloon" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        view.layer.cornerRadius = MIN(MAX(nmCornerRadius, 16), 24);
        view.layer.cornerCurve = kCACornerCurveContinuous;
        view.clipsToBounds = YES;
    }

    if (nmInputStyling && ([name rangeOfString:@"MessageEntry" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                           [name rangeOfString:@"EntryView" options:NSCaseInsensitiveSearch].location != NSNotFound)) {
        view.backgroundColor = NMColor(0x101A31, 0.92);
        view.layer.cornerRadius = 20;
        view.layer.cornerCurve = kCACornerCurveContinuous;
        view.layer.borderWidth = 0.8;
        view.layer.borderColor = NMColor(0x65779F,0.28).CGColor;
    }

    if ([name rangeOfString:@"TranscriptCollection" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [name rangeOfString:@"ConversationList" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        view.backgroundColor = UIColor.clearColor;
    }
}

static void NMInvokeDeleteAction(UIContextualAction *action,
                                 id controller,
                                 UITableView *tableView,
                                 NSIndexPath *indexPath) {
    if (action) {
        id handlerObject = NMSafeValue(action, @"handler") ?: NMSafeValue(action, @"_handler");
        if (handlerObject) {
            void (^handler)(UIContextualAction *, UIView *, void (^)(BOOL)) = handlerObject;
            handler(action, nil, ^(__unused BOOL success) {});
            return;
        }
    }

    SEL commitSelector = @selector(tableView:commitEditingStyle:forRowAtIndexPath:);
    if ([controller respondsToSelector:commitSelector]) {
        typedef void (*NMCommitFunction)(id, SEL, UITableView *, UITableViewCellEditingStyle, NSIndexPath *);
        ((NMCommitFunction)objc_msgSend)(controller, commitSelector, tableView, UITableViewCellEditingStyleDelete, indexPath);
        return;
    }

    for (NSString *selectorName in @[@"_deleteConversationAtIndexPath:", @"deleteConversationAtIndexPath:", @"removeConversationAtIndexPath:"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([controller respondsToSelector:selector]) {
            typedef void (*NMIndexFunction)(id, SEL, NSIndexPath *);
            ((NMIndexFunction)objc_msgSend)(controller, selector, indexPath);
            return;
        }
    }
}

static void NMPresentConversationDetails(UIViewController *controller,
                                         UITableView *tableView,
                                         NSIndexPath *indexPath,
                                         UIContextualAction *originalDeleteAction) {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    NSArray<NSString *> *candidates = NMCandidatesForCell(cell);
    id model = NMConversationModelForCell(cell);

    NSString *title = candidates.firstObject ?: @"Conversation";
    NSString *identifier = candidates.count > 1 ? candidates[1] : nil;
    NSInteger count = NSNotFound;
    NSDate *firstDate = nil;
    NSString *databaseIdentifier = nil;
    NMQueryDatabaseStats(candidates, &count, &firstDate, &databaseIdentifier);
    if (count == NSNotFound) count = NMFallbackMessageCount(model);
    if (!firstDate) firstDate = NMFallbackFirstDate(model);
    if (databaseIdentifier.length) identifier = databaseIdentifier;

    NMConversationDetailsController *details = [[NMConversationDetailsController alloc] init];
    details.modalPresentationStyle = UIModalPresentationOverFullScreen;
    details.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    details.conversationTitle = title;
    details.identifierText = identifier;
    details.messageCountText = nmShowMessageCount ? (count == NSNotFound ? @"Not available" : [NSString stringWithFormat:@"%ld", (long)count]) : @"Hidden in Settings";
    details.firstDateText = nmShowFirstDate ? NMReadableDate(firstDate) : @"Hidden in Settings";
    details.allowDelete = nmDeleteFromCard;

    __weak id weakController = controller;
    __weak UITableView *weakTable = tableView;
    NSIndexPath *capturedIndexPath = [indexPath copy];
    details.deleteHandler = ^{
        NMInvokeDeleteAction(originalDeleteAction, weakController, weakTable, capturedIndexPath);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakTable reloadData];
        });
    };

    NMHaptic(NO);
    [controller presentViewController:details animated:YES completion:nil];
}

%hook CKConversationListViewController

- (void)viewDidLoad {
    %orig;
    if (!nmEnabled) return;
    UITableView *tableView = nil;
    if ([self respondsToSelector:@selector(tableView)]) tableView = [self tableView];
    tableView.backgroundColor = UIColor.clearColor;
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    tableView.sectionHeaderTopPadding = 4;
    NMApplyControllerTheme(self);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nm_refreshTheme) name:@"NMRefreshTheme" object:nil];
}

%new
- (void)nm_refreshTheme {
    NMApplyControllerTheme(self);
    UITableView *tableView = [self respondsToSelector:@selector(tableView)] ? [self tableView] : nil;
    tableView.backgroundColor = UIColor.clearColor;
    [tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!nmEnabled) return;
    NMApplyControllerTheme(self);
    UITableView *tableView = [self respondsToSelector:@selector(tableView)] ? [self tableView] : nil;
    tableView.backgroundColor = UIColor.clearColor;
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (nmEnabled) NMApplyControllerTheme(self);
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UISwipeActionsConfiguration *original = %orig;
    if (!nmEnabled || !nmDetailsSwipe) return original;

    UIContextualAction *deleteAction = nil;
    for (UIContextualAction *action in original.actions) {
        if (action.style == UIContextualActionStyleDestructive || [action.title.lowercaseString containsString:@"delete"]) {
            deleteAction = action;
            break;
        }
    }

    __weak CKConversationListViewController *weakSelf = self;
    __weak UITableView *weakTable = tableView;
    UIContextualAction *detailsAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                title:@"Details"
                                                                              handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        NMPresentConversationDetails(weakSelf, weakTable, indexPath, deleteAction);
        completionHandler(YES);
    }];
    detailsAction.backgroundColor = NMColor(0x6F63FF, 1);
    if (@available(iOS 13.0, *)) detailsAction.image = [UIImage systemImageNamed:@"info.circle.fill"];

    NSMutableArray *actions = [NSMutableArray arrayWithObject:detailsAction];
    if (original.actions.count) [actions addObjectsFromArray:original.actions];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:actions];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

%end

%hook CKConversationViewController

- (void)viewDidLoad {
    %orig;
    if (!nmEnabled) return;
    NMApplyControllerTheme(self);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nm_refreshTheme) name:@"NMRefreshTheme" object:nil];
}

%new
- (void)nm_refreshTheme {
    NMApplyControllerTheme(self);
    [self.view setNeedsLayout];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (nmEnabled) NMApplyControllerTheme(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (nmEnabled) NMApplyControllerTheme(self);
}

%end

%hook UITableViewCell

- (void)layoutSubviews {
    %orig;
    if (NMIsMessagesProcess()) NMStyleConversationCell(self);
}

%end

%hook UIView

- (void)didMoveToWindow {
    %orig;
    if (NMIsMessagesProcess()) NMStyleRuntimeView(self);
}

%end

%ctor {
    if (!NMIsMessagesProcess()) return;
    NMLoadPreferences();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    NMPreferencesChanged,
                                    (__bridge CFStringRef)NMNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}
