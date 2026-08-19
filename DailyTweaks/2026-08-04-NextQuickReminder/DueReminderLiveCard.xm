#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

// iOS 16.0 doesn't contain ActivityKit. This SpringBoard-side card is the
// RootHide fallback: it stays visible on the Lock Screen for a due reminder
// and disappears immediately after Completed or Extend 10m.

static UIWindow *NQR107DueWindow = nil;
static NSDictionary *NQR107CurrentReminder = nil;
static NSString *NQR107DatabasePath = nil;
static NSArray *NQR107CachedReminders = nil;
static NSArray *NQR107CachedCategories = nil;
static NSDate *NQR107LastDatabaseLoad = nil;
static NSTimer *NQR107Timer = nil;

static NSDateFormatter *NQR107ISOFormatter(void) {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssXXXXX";
    });
    return formatter;
}

static NSDate *NQR107DateFromJSON(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text = (NSString *)value;
    if (@available(iOS 10.0, *)) {
        NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
        NSDate *date = [iso dateFromString:text];
        if (date) return date;
        iso.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        date = [iso dateFromString:text];
        if (date) return date;
    }
    return [NQR107ISOFormatter() dateFromString:text];
}

static NSString *NQR107JSONStringFromDate(NSDate *date) {
    if (@available(iOS 10.0, *)) {
        NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
        iso.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        return [iso stringFromDate:date];
    }
    return [NQR107ISOFormatter() stringFromDate:date];
}

static UIWindowScene *NQR107ActiveScene(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState != UISceneActivationStateUnattached) {
                return (UIWindowScene *)scene;
            }
        }
    }
    return nil;
}

static BOOL NQR107IsUILocked(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    if (cls) {
        id manager = nil;
        SEL shared = NSSelectorFromString(@"sharedInstance");
        SEL sharedAlt = NSSelectorFromString(@"_sharedInstance");
        if ([cls respondsToSelector:shared]) {
            manager = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
        } else if ([cls respondsToSelector:sharedAlt]) {
            manager = ((id (*)(id, SEL))objc_msgSend)(cls, sharedAlt);
        }
        SEL locked = NSSelectorFromString(@"isUILocked");
        if (manager && [manager respondsToSelector:locked]) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(manager, locked);
        }
    }
    return !UIApplication.sharedApplication.isProtectedDataAvailable;
}

static NSString *NQR107FindDatabasePath(void) {
    if (NQR107DatabasePath.length && [[NSFileManager defaultManager] fileExistsAtPath:NQR107DatabasePath]) {
        return NQR107DatabasePath;
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *roots = @[
        @"/var/mobile/Containers/Data/Application",
        @"/private/var/mobile/Containers/Data/Application"
    ];
    for (NSString *root in roots) {
        NSArray<NSString *> *containers = [fm contentsOfDirectoryAtPath:root error:nil];
        for (NSString *container in containers) {
            NSString *candidate = [[[[root stringByAppendingPathComponent:container]
                stringByAppendingPathComponent:@"Library"]
                stringByAppendingPathComponent:@"Application Support/NextReminder"]
                stringByAppendingPathComponent:@"NextReminderDatabase.json"];
            if ([fm fileExistsAtPath:candidate]) {
                NQR107DatabasePath = candidate;
                NSLog(@"[NextQuickReminder] Due live-card database found at %@", candidate);
                return candidate;
            }
        }
    }
    return nil;
}

static void NQR107ReloadDatabaseIfNeeded(BOOL force) {
    NSDate *now = [NSDate date];
    if (!force && NQR107LastDatabaseLoad && [now timeIntervalSinceDate:NQR107LastDatabaseLoad] < 20.0) return;
    NQR107LastDatabaseLoad = now;

    NSString *path = NQR107FindDatabasePath();
    if (!path.length) return;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return;
    NSDictionary *database = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![database isKindOfClass:NSDictionary.class]) return;
    NSArray *reminders = database[@"reminders"];
    NSArray *categories = database[@"categories"];
    NQR107CachedReminders = [reminders isKindOfClass:NSArray.class] ? reminders : @[];
    NQR107CachedCategories = [categories isKindOfClass:NSArray.class] ? categories : @[];
}

static NSString *NQR107CategoryName(NSString *categoryID) {
    for (NSDictionary *category in NQR107CachedCategories) {
        if (![category isKindOfClass:NSDictionary.class]) continue;
        if ([category[@"id"] isEqual:categoryID]) {
            NSString *name = category[@"name"];
            if ([name isKindOfClass:NSString.class] && name.length) return name;
        }
    }
    return @"Reminder";
}

static NSDictionary *NQR107DueReminder(void) {
    NSDate *now = [NSDate date];
    NSDictionary *best = nil;
    NSDate *bestDate = nil;
    for (NSDictionary *item in NQR107CachedReminders) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        id completed = item[@"completedAt"];
        if (completed && completed != NSNull.null) continue;
        NSNumber *enabled = item[@"notificationsEnabled"];
        if (enabled && !enabled.boolValue) continue;
        NSDate *due = NQR107DateFromJSON(item[@"dueDate"]);
        if (!due || [due compare:now] == NSOrderedDescending) continue;
        if (!bestDate || [due compare:bestDate] == NSOrderedAscending) {
            best = item;
            bestDate = due;
        }
    }
    return best;
}

static NSMutableDictionary *NQR107MutableDatabase(void) {
    NSString *path = NQR107FindDatabasePath();
    NSData *data = path.length ? [NSData dataWithContentsOfFile:path] : nil;
    if (!data.length) return nil;
    NSDictionary *decoded = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    return [decoded isKindOfClass:NSDictionary.class] ? [decoded mutableCopy] : nil;
}

static BOOL NQR107WriteDatabase(NSMutableDictionary *database) {
    NSString *path = NQR107FindDatabasePath();
    if (!path.length || !database) return NO;
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:database options:0 error:&error];
    if (!data || error) return NO;
    BOOL ok = [data writeToFile:path options:NSDataWritingAtomic error:&error];
    if (ok) {
        NQR107LastDatabaseLoad = nil;
        NQR107ReloadDatabaseIfNeeded(YES);
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.nextsolution.nextreminder.database.changed"),
            NULL,
            NULL,
            true
        );
    }
    return ok;
}

static NSDate *NQR107NextRepeatDate(NSString *rule, NSDate *date) {
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDateComponents *components = [NSDateComponents new];
    if ([rule isEqualToString:@"daily"]) components.day = 1;
    else if ([rule isEqualToString:@"weekly"]) components.weekOfYear = 1;
    else if ([rule isEqualToString:@"monthly"]) components.month = 1;
    else if ([rule isEqualToString:@"yearly"]) components.year = 1;
    else return nil;
    return [calendar dateByAddingComponents:components toDate:date options:0];
}

static BOOL NQR107UpdateReminder(NSString *reminderID, BOOL complete, NSTimeInterval extensionSeconds) {
    NSMutableDictionary *database = NQR107MutableDatabase();
    NSMutableArray *reminders = [database[@"reminders"] mutableCopy];
    if (!database || !reminders) return NO;

    BOOL changed = NO;
    NSDate *now = [NSDate date];
    for (NSUInteger index = 0; index < reminders.count; index++) {
        NSDictionary *raw = reminders[index];
        if (![raw isKindOfClass:NSDictionary.class] || ![raw[@"id"] isEqual:reminderID]) continue;
        NSMutableDictionary *item = [raw mutableCopy];
        if (complete) {
            NSString *repeatRule = [item[@"repeatRule"] isKindOfClass:NSString.class] ? item[@"repeatRule"] : @"never";
            NSDate *due = NQR107DateFromJSON(item[@"dueDate"]) ?: now;
            NSDate *next = NQR107NextRepeatDate(repeatRule, due);
            if (next) {
                while ([next compare:now] != NSOrderedDescending) {
                    NSDate *later = NQR107NextRepeatDate(repeatRule, next);
                    if (!later) break;
                    next = later;
                }
                item[@"dueDate"] = NQR107JSONStringFromDate(next);
                item[@"completedAt"] = NSNull.null;
                item[@"completionComment"] = @"Completed from Lock Screen live card";
            } else {
                item[@"completedAt"] = NQR107JSONStringFromDate(now);
                item[@"completionComment"] = @"Completed from Lock Screen live card";
            }
        } else if (extensionSeconds > 0) {
            NSDate *newDue = [now dateByAddingTimeInterval:extensionSeconds];
            item[@"dueDate"] = NQR107JSONStringFromDate(newDue);
            item[@"completedAt"] = NSNull.null;
            item[@"completionComment"] = NSNull.null;
        }
        item[@"updatedAt"] = NQR107JSONStringFromDate(now);
        reminders[index] = item;
        changed = YES;
        break;
    }
    if (!changed) return NO;
    database[@"reminders"] = reminders;
    return NQR107WriteDatabase(database);
}

@class NQR107DueCardController;

@interface NQR107TouchWindow : UIWindow
@property(nonatomic, weak) NQR107DueCardController *cardController;
@end

@interface NQR107DueCardController : UIViewController
@property(nonatomic, copy) NSString *reminderID;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *notesLabel;
@property(nonatomic, strong) UILabel *metaLabel;
- (instancetype)initWithReminder:(NSDictionary *)reminder;
@end

@implementation NQR107TouchWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return [super pointInside:point withEvent:event];
}
@end

static void NQR107HideDueCard(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!NQR107DueWindow) return;
        NQR107DueWindow.hidden = YES;
        NQR107DueWindow.rootViewController = nil;
        NQR107DueWindow = nil;
        NQR107CurrentReminder = nil;
    });
}

@implementation NQR107DueCardController
- (instancetype)initWithReminder:(NSDictionary *)reminder {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _reminderID = [reminder[@"id"] isKindOfClass:NSString.class] ? reminder[@"id"] : @"";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial]];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = 22;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.18].CGColor;
    [self.view addSubview:card];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 7;
    [card.contentView addSubview:stack];

    UILabel *eyebrow = [UILabel new];
    eyebrow.text = @"● LIVE REMINDER";
    eyebrow.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    eyebrow.textColor = UIColor.systemOrangeColor;

    self.titleLabel = [UILabel new];
    self.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    self.titleLabel.numberOfLines = 2;

    self.notesLabel = [UILabel new];
    self.notesLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    self.notesLabel.textColor = UIColor.secondaryLabelColor;
    self.notesLabel.numberOfLines = 2;

    self.metaLabel = [UILabel new];
    self.metaLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    self.metaLabel.textColor = UIColor.secondaryLabelColor;

    UIStackView *buttons = [UIStackView new];
    buttons.axis = UILayoutConstraintAxisHorizontal;
    buttons.distribution = UIStackViewDistributionFillEqually;
    buttons.spacing = 8;

    UIButton *complete = [UIButton buttonWithType:UIButtonTypeSystem];
    [complete setTitle:@"✓ Completed" forState:UIControlStateNormal];
    complete.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [complete setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    complete.backgroundColor = UIColor.systemGreenColor;
    complete.layer.cornerRadius = 11;
    [complete addTarget:self action:@selector(completeTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *extend = [UIButton buttonWithType:UIButtonTypeSystem];
    [extend setTitle:@"↻ Extend 10m" forState:UIControlStateNormal];
    extend.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [extend setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    extend.backgroundColor = UIColor.systemOrangeColor;
    extend.layer.cornerRadius = 11;
    [extend addTarget:self action:@selector(extendTapped) forControlEvents:UIControlEventTouchUpInside];

    [buttons addArrangedSubview:complete];
    [buttons addArrangedSubview:extend];
    [stack addArrangedSubview:eyebrow];
    [stack addArrangedSubview:self.titleLabel];
    [stack addArrangedSubview:self.notesLabel];
    [stack addArrangedSubview:self.metaLabel];
    [stack addArrangedSubview:buttons];

    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [card.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [card.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:card.contentView.topAnchor constant:13],
        [stack.bottomAnchor constraintEqualToAnchor:card.contentView.bottomAnchor constant:-13],
        [buttons.heightAnchor constraintEqualToConstant:42],
    ]];

    [self refreshLabels];
}

- (void)refreshLabels {
    NSDictionary *reminder = NQR107CurrentReminder;
    self.titleLabel.text = [reminder[@"title"] isKindOfClass:NSString.class] ? reminder[@"title"] : @"Reminder due";
    NSString *notes = [reminder[@"notes"] isKindOfClass:NSString.class] ? reminder[@"notes"] : @"";
    self.notesLabel.text = notes.length ? notes : @"Reminder time reached";
    NSString *category = NQR107CategoryName(reminder[@"categoryID"]);
    NSString *priority = [reminder[@"priority"] isKindOfClass:NSString.class] ? [reminder[@"priority"] capitalizedString] : @"Medium";
    self.metaLabel.text = [NSString stringWithFormat:@"%@  •  %@ priority", category, priority];
}

- (void)completeTapped {
    if (self.reminderID.length) NQR107UpdateReminder(self.reminderID, YES, 0);
    UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
    [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
    NQR107HideDueCard();
}

- (void)extendTapped {
    if (self.reminderID.length) NQR107UpdateReminder(self.reminderID, NO, 10 * 60);
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    NQR107HideDueCard();
}
@end

static void NQR107ShowDueCard(NSDictionary *reminder) {
    if (!reminder || NQR107DueWindow) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!NQR107IsUILocked() || NQR107DueWindow) return;
        NQR107CurrentReminder = reminder;
        CGRect screen = UIScreen.mainScreen.bounds;
        CGRect frame = CGRectMake(14, 118, MAX(280, screen.size.width - 28), 188);
        UIWindowScene *scene = NQR107ActiveScene();
        NQR107TouchWindow *window;
        if (@available(iOS 13.0, *)) {
            window = scene ? [[NQR107TouchWindow alloc] initWithWindowScene:scene] : [[NQR107TouchWindow alloc] initWithFrame:frame];
        } else {
            window = [[NQR107TouchWindow alloc] initWithFrame:frame];
        }
        window.frame = frame;
        window.backgroundColor = UIColor.clearColor;
        window.windowLevel = UIWindowLevelAlert + 32.0;
        NQR107DueCardController *controller = [[NQR107DueCardController alloc] initWithReminder:reminder];
        window.rootViewController = controller;
        window.hidden = NO;
        NQR107DueWindow = window;
        NSLog(@"[NextQuickReminder] Presented iOS16 RootHide due live card for %@", reminder[@"title"]);
    });
}

static void NQR107EvaluateDueCard(void) {
    if (!NQR107IsUILocked()) {
        NQR107HideDueCard();
        return;
    }
    NQR107ReloadDatabaseIfNeeded(NO);
    NSDictionary *due = NQR107DueReminder();
    if (!due) {
        NQR107HideDueCard();
        return;
    }
    if (NQR107DueWindow) {
        NSString *currentID = NQR107CurrentReminder[@"id"];
        if ([currentID isEqual:due[@"id"]]) return;
        NQR107HideDueCard();
    }
    NQR107ShowDueCard(due);
}

__attribute__((constructor)) static void NQR107DueLiveCardInit(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            NQR107ReloadDatabaseIfNeeded(YES);
            NQR107Timer = [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(__unused NSTimer *timer) {
                NQR107EvaluateDueCard();
            }];
            [NQR107Timer fire];
            NSLog(@"[NextQuickReminder] iOS16 RootHide due live-card monitor loaded");
        });
    }
}
