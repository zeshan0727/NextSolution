#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

// iOS 16.0 has Apple's System Aperture / Dynamic Island UI, but the public
// ActivityKit API for third-party apps starts at iOS 16.1. This RootHide module
// therefore renders the due reminder inside SpringBoard's real
// SBSystemApertureWindow instead of creating a separate UIWindow.

@interface SBSystemApertureWindow : UIWindow
@end

static __weak SBSystemApertureWindow *NQR108SystemApertureWindow = nil;
static UIView *NQR108IslandView = nil;
static NSDictionary *NQR108CurrentReminder = nil;
static NSString *NQR108DatabasePath = nil;
static NSDate *NQR108DatabaseModifiedAt = nil;
static NSArray *NQR108Reminders = nil;
static NSArray *NQR108Categories = nil;
static NSTimer *NQR108Timer = nil;
static BOOL NQR108Expanded = YES;
static dispatch_block_t NQR108CollapseBlock = nil;

static BOOL NQR108IsLocked(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    if (cls) {
        id manager = nil;
        SEL shared = NSSelectorFromString(@"sharedInstance");
        SEL sharedAlt = NSSelectorFromString(@"_sharedInstance");
        if ([cls respondsToSelector:shared]) manager = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
        else if ([cls respondsToSelector:sharedAlt]) manager = ((id (*)(id, SEL))objc_msgSend)(cls, sharedAlt);
        SEL locked = NSSelectorFromString(@"isUILocked");
        if (manager && [manager respondsToSelector:locked]) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(manager, locked);
        }
    }
    return !UIApplication.sharedApplication.isProtectedDataAvailable;
}

static NSDate *NQR108DateFromJSON(id value) {
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
    return nil;
}

static NSString *NQR108JSONStringFromDate(NSDate *date) {
    NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
    iso.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    return [iso stringFromDate:date];
}

static NSString *NQR108ActiveContainerPath(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *roots = @[@"/var/mobile/Containers/Data/Application", @"/private/var/mobile/Containers/Data/Application"];
    NSString *fallback = nil;
    NSDate *fallbackDate = nil;

    for (NSString *root in roots) {
        for (NSString *container in [fm contentsOfDirectoryAtPath:root error:nil] ?: @[]) {
            NSString *containerPath = [root stringByAppendingPathComponent:container];
            NSString *metadataPath = [containerPath stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
            NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
            NSString *identifier = [metadata[@"MCMMetadataIdentifier"] isKindOfClass:NSString.class] ? metadata[@"MCMMetadataIdentifier"] : nil;
            NSString *db = [containerPath stringByAppendingPathComponent:@"Library/Application Support/NextReminder/NextReminderDatabase.json"];
            if (![fm fileExistsAtPath:db]) continue;

            if ([identifier isEqualToString:@"com.nextsolution.nextreminder"]) {
                return db;
            }

            NSDictionary *attrs = [fm attributesOfItemAtPath:db error:nil];
            NSDate *modified = attrs[NSFileModificationDate];
            if (!fallbackDate || [modified compare:fallbackDate] == NSOrderedDescending) {
                fallbackDate = modified;
                fallback = db;
            }
        }
    }
    return fallback;
}

static BOOL NQR108ReloadDatabase(BOOL force) {
    NSString *path = NQR108ActiveContainerPath();
    if (!path.length) {
        NQR108DatabasePath = nil;
        NQR108Reminders = @[];
        NQR108Categories = @[];
        return YES;
    }

    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    NSDate *modified = attrs[NSFileModificationDate];
    BOOL pathChanged = ![NQR108DatabasePath isEqualToString:path];
    BOOL modifiedChanged = !NQR108DatabaseModifiedAt || ![NQR108DatabaseModifiedAt isEqualToDate:modified];
    if (!force && !pathChanged && !modifiedChanged) return NO;

    NSData *data = [NSData dataWithContentsOfFile:path];
    NSDictionary *database = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![database isKindOfClass:NSDictionary.class]) return NO;

    NQR108DatabasePath = path;
    NQR108DatabaseModifiedAt = modified;
    NQR108Reminders = [database[@"reminders"] isKindOfClass:NSArray.class] ? database[@"reminders"] : @[];
    NQR108Categories = [database[@"categories"] isKindOfClass:NSArray.class] ? database[@"categories"] : @[];
    return YES;
}

static NSString *NQR108CategoryName(id categoryID) {
    if (![categoryID isKindOfClass:NSString.class]) return @"Reminder";
    for (NSDictionary *category in NQR108Categories) {
        if (![category isKindOfClass:NSDictionary.class]) continue;
        if ([category[@"id"] isEqual:categoryID]) {
            NSString *name = [category[@"name"] isKindOfClass:NSString.class] ? category[@"name"] : nil;
            if (name.length) return name;
        }
    }
    return @"Reminder";
}

static NSDictionary *NQR108DueReminder(void) {
    NSDate *now = [NSDate date];
    NSDictionary *best = nil;
    NSDate *bestDate = nil;
    for (NSDictionary *item in NQR108Reminders) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        id completedAt = item[@"completedAt"];
        if (completedAt && completedAt != NSNull.null) continue;
        NSNumber *enabled = [item[@"notificationsEnabled"] isKindOfClass:NSNumber.class] ? item[@"notificationsEnabled"] : nil;
        if (enabled && !enabled.boolValue) continue;
        NSDate *due = NQR108DateFromJSON(item[@"dueDate"]);
        if (!due || [due compare:now] == NSOrderedDescending) continue;
        if (!bestDate || [due compare:bestDate] == NSOrderedAscending) {
            best = item;
            bestDate = due;
        }
    }
    return best;
}

static NSMutableDictionary *NQR108MutableDatabase(void) {
    if (!NQR108DatabasePath.length) NQR108ReloadDatabase(YES);
    NSData *data = NQR108DatabasePath.length ? [NSData dataWithContentsOfFile:NQR108DatabasePath] : nil;
    if (!data.length) return nil;
    id decoded = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    return [decoded isKindOfClass:NSDictionary.class] ? [decoded mutableCopy] : nil;
}

static BOOL NQR108WriteDatabase(NSMutableDictionary *database) {
    if (!database || !NQR108DatabasePath.length) return NO;
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:database options:0 error:&error];
    if (!data || error) return NO;
    BOOL ok = [data writeToFile:NQR108DatabasePath options:NSDataWritingAtomic error:&error];
    if (ok) {
        NQR108DatabaseModifiedAt = nil;
        NQR108ReloadDatabase(YES);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.nextsolution.nextreminder.database.changed"), NULL, NULL, true);
    }
    return ok;
}

static NSDate *NQR108NextRepeatDate(NSString *rule, NSDate *date) {
    if (![rule isKindOfClass:NSString.class] || [rule isEqualToString:@"never"]) return nil;
    NSDateComponents *c = [NSDateComponents new];
    if ([rule isEqualToString:@"daily"]) c.day = 1;
    else if ([rule isEqualToString:@"weekly"]) c.weekOfYear = 1;
    else if ([rule isEqualToString:@"monthly"]) c.month = 1;
    else if ([rule isEqualToString:@"yearly"]) c.year = 1;
    else return nil;
    return [NSCalendar.currentCalendar dateByAddingComponents:c toDate:date options:0];
}

static BOOL NQR108ApplyAction(NSString *reminderID, BOOL completed, NSTimeInterval extendSeconds) {
    NSMutableDictionary *database = NQR108MutableDatabase();
    NSMutableArray *reminders = [database[@"reminders"] mutableCopy];
    if (!database || !reminders || !reminderID.length) return NO;

    NSDate *now = [NSDate date];
    BOOL changed = NO;
    for (NSUInteger i = 0; i < reminders.count; i++) {
        NSDictionary *raw = reminders[i];
        if (![raw isKindOfClass:NSDictionary.class] || ![raw[@"id"] isEqual:reminderID]) continue;
        NSMutableDictionary *item = [raw mutableCopy];

        if (completed) {
            NSDate *due = NQR108DateFromJSON(item[@"dueDate"]) ?: now;
            NSString *rule = [item[@"repeatRule"] isKindOfClass:NSString.class] ? item[@"repeatRule"] : @"never";
            NSDate *next = NQR108NextRepeatDate(rule, due);
            if (next) {
                while ([next compare:now] != NSOrderedDescending) {
                    NSDate *later = NQR108NextRepeatDate(rule, next);
                    if (!later) break;
                    next = later;
                }
                item[@"dueDate"] = NQR108JSONStringFromDate(next);
                item[@"completedAt"] = NSNull.null;
            } else {
                item[@"completedAt"] = NQR108JSONStringFromDate(now);
            }
            item[@"completionComment"] = @"Completed from Dynamic Island";
        } else if (extendSeconds > 0) {
            NSDate *newDue = [now dateByAddingTimeInterval:extendSeconds];
            NSDate *oldDue = NQR108DateFromJSON(item[@"dueDate"]);
            item[@"dueDate"] = NQR108JSONStringFromDate(newDue);
            if (oldDue) {
                NSDate *deadline = NQR108DateFromJSON(item[@"deadlineDate"]);
                if (deadline) item[@"deadlineDate"] = NQR108JSONStringFromDate([deadline dateByAddingTimeInterval:[newDue timeIntervalSinceDate:oldDue]]);
            }
            item[@"completedAt"] = NSNull.null;
            item[@"completionComment"] = NSNull.null;
        }
        item[@"updatedAt"] = NQR108JSONStringFromDate(now);
        reminders[i] = item;
        changed = YES;
        break;
    }

    if (!changed) return NO;
    database[@"reminders"] = reminders;
    return NQR108WriteDatabase(database);
}

@interface NQR108ApertureCard : UIControl
@property(nonatomic, strong) UILabel *iconLabel;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *metaLabel;
@property(nonatomic, strong) UIButton *completeButton;
@property(nonatomic, strong) UIButton *extendButton;
@property(nonatomic, copy) NSString *reminderID;
- (void)applyReminder:(NSDictionary *)reminder;
- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated;
@end

@implementation NQR108ApertureCard
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = UIColor.blackColor;
    self.layer.cornerRadius = 28.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;
    self.accessibilityLabel = @"Next Reminder due";

    _iconLabel = [UILabel new];
    _iconLabel.text = @"●";
    _iconLabel.textColor = UIColor.systemOrangeColor;
    _iconLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];

    _titleLabel = [UILabel new];
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _titleLabel.numberOfLines = 2;

    _metaLabel = [UILabel new];
    _metaLabel.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.65];
    _metaLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _metaLabel.numberOfLines = 1;

    _completeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_completeButton setTitle:@"✓ Completed" forState:UIControlStateNormal];
    [_completeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _completeButton.backgroundColor = UIColor.systemGreenColor;
    _completeButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    _completeButton.layer.cornerRadius = 13;
    [_completeButton addTarget:self action:@selector(completeTapped) forControlEvents:UIControlEventTouchUpInside];

    _extendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_extendButton setTitle:@"↻ Extend 10m" forState:UIControlStateNormal];
    [_extendButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _extendButton.backgroundColor = UIColor.systemOrangeColor;
    _extendButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    _extendButton.layer.cornerRadius = 13;
    [_extendButton addTarget:self action:@selector(extendTapped) forControlEvents:UIControlEventTouchUpInside];

    for (UIView *v in @[_iconLabel, _titleLabel, _metaLabel, _completeButton, _extendButton]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:v];
    }

    [NSLayoutConstraint activateConstraints:@[
        [_iconLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_iconLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:13],
        [_iconLabel.widthAnchor constraintEqualToConstant:20],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconLabel.trailingAnchor constant:8],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [_metaLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_metaLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_metaLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
        [_completeButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_completeButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
        [_completeButton.heightAnchor constraintEqualToConstant:42],
        [_extendButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [_extendButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
        [_extendButton.heightAnchor constraintEqualToConstant:42],
        [_extendButton.leadingAnchor constraintEqualToAnchor:_completeButton.trailingAnchor constant:8],
        [_completeButton.widthAnchor constraintEqualToAnchor:_extendButton.widthAnchor],
    ]];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    longPress.minimumPressDuration = 0.35;
    [self addGestureRecognizer:longPress];
    [self addTarget:self action:@selector(cardTapped) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)applyReminder:(NSDictionary *)reminder {
    self.reminderID = [reminder[@"id"] isKindOfClass:NSString.class] ? reminder[@"id"] : @"";
    NSString *title = [reminder[@"title"] isKindOfClass:NSString.class] ? reminder[@"title"] : @"Reminder due";
    NSString *category = NQR108CategoryName(reminder[@"categoryID"]);
    NSString *priority = [reminder[@"priority"] isKindOfClass:NSString.class] ? [reminder[@"priority"] capitalizedString] : @"Medium";
    self.titleLabel.text = title;
    self.metaLabel.text = [NSString stringWithFormat:@"%@ • %@ priority", category, priority];
}

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated {
    NQR108Expanded = expanded;
    self.completeButton.hidden = !expanded;
    self.extendButton.hidden = !expanded;
    self.metaLabel.hidden = !expanded;
    CGFloat width = expanded ? MIN(UIScreen.mainScreen.bounds.size.width - 28.0, 402.0) : 250.0;
    CGFloat height = expanded ? 124.0 : 54.0;
    CGFloat y = expanded ? 84.0 : 8.0;
    CGFloat x = (UIScreen.mainScreen.bounds.size.width - width) / 2.0;
    void (^changes)(void) = ^{
        self.frame = CGRectMake(x, y, width, height);
        self.layer.cornerRadius = expanded ? 30.0 : 27.0;
        [self layoutIfNeeded];
    };
    if (animated) [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.15 options:UIViewAnimationOptionCurveEaseInOut animations:changes completion:nil];
    else changes();
}

- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) [self setExpanded:!NQR108Expanded animated:YES];
}
- (void)cardTapped { if (!NQR108Expanded) [self setExpanded:YES animated:YES]; }
- (void)completeTapped {
    if (self.reminderID.length) NQR108ApplyAction(self.reminderID, YES, 0);
    UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
    [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
}
- (void)extendTapped {
    if (self.reminderID.length) NQR108ApplyAction(self.reminderID, NO, 10 * 60);
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
}
@end

static void NQR108RemoveIsland(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NQR108IslandView removeFromSuperview];
        NQR108IslandView = nil;
        NQR108CurrentReminder = nil;
        NQR108Expanded = YES;
    });
}

static void NQR108PresentReminder(NSDictionary *reminder) {
    SBSystemApertureWindow *window = NQR108SystemApertureWindow;
    if (!window || !reminder) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *reminderID = [reminder[@"id"] isKindOfClass:NSString.class] ? reminder[@"id"] : nil;
        if ([NQR108CurrentReminder[@"id"] isEqual:reminderID] && NQR108IslandView.superview == window) return;
        NQR108RemoveIsland();
        NQR108CurrentReminder = reminder;
        NQR108ApertureCard *card = [[NQR108ApertureCard alloc] initWithFrame:CGRectZero];
        [card applyReminder:reminder];
        [window addSubview:card];
        NQR108IslandView = card;
        [card setExpanded:YES animated:NO];
        window.userInteractionEnabled = YES;
        [window bringSubviewToFront:card];

        if (NQR108CollapseBlock) dispatch_block_cancel(NQR108CollapseBlock);
        NQR108CollapseBlock = dispatch_block_create(0, ^{
            if ([NQR108IslandView isKindOfClass:NQR108ApertureCard.class]) {
                [(NQR108ApertureCard *)NQR108IslandView setExpanded:NO animated:YES];
            }
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), NQR108CollapseBlock);
        NSLog(@"[NextQuickReminder] Reminder presented inside Apple's SBSystemApertureWindow: %@", reminder[@"title"]);
    });
}

static void NQR108Evaluate(void) {
    if (!NQR108IsLocked()) {
        NQR108RemoveIsland();
        return;
    }
    NQR108ReloadDatabase(NO);
    NSDictionary *due = NQR108DueReminder();
    if (!due) {
        NQR108RemoveIsland();
        return;
    }
    NQR108PresentReminder(due);
}

static void NQR108DatabaseChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NQR108DatabaseModifiedAt = nil;
        NQR108ReloadDatabase(YES);
        NQR108Evaluate();
    });
}

%hook SBSystemApertureWindow
- (void)didMoveToScreen:(UIScreen *)screen {
    %orig;
    NQR108SystemApertureWindow = self;
    dispatch_async(dispatch_get_main_queue(), ^{ NQR108Evaluate(); });
}
- (void)layoutSubviews {
    %orig;
    NQR108SystemApertureWindow = self;
    if (NQR108IslandView.superview == self) [self bringSubviewToFront:NQR108IslandView];
}
%end

__attribute__((constructor)) static void NQR108SystemApertureInit(void) {
    @autoreleasepool {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            NQR108DatabaseChanged,
            CFSTR("com.nextsolution.nextreminder.database.changed"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        dispatch_async(dispatch_get_main_queue(), ^{
            NQR108ReloadDatabase(YES);
            NQR108Timer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(__unused NSTimer *timer) {
                NQR108Evaluate();
            }];
            [NQR108Timer fire];
            NSLog(@"[NextQuickReminder] 1.0.8 Apple System Aperture reminder integration loaded; no separate due-reminder UIWindow");
        });
    }
}
