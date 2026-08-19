#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

// iOS 16.0 predates public third-party ActivityKit Live Activities. This tweak
// therefore integrates with SpringBoard's existing System Aperture window. In
// 1.0.9 the reminder no longer renders as a detached Lock Screen card: the
// compact and expanded states stay attached to the Dynamic Island area.
@interface SBSystemApertureWindow : UIWindow
@end

static __weak SBSystemApertureWindow *NQR109SystemApertureWindow = nil;
static UIView *NQR109IslandView = nil;
static NSDictionary *NQR109CurrentReminder = nil;
static NSString *NQR109DatabasePath = nil;
static NSDate *NQR109DatabaseModifiedAt = nil;
static NSArray *NQR109Reminders = nil;
static NSArray *NQR109Categories = nil;
static NSTimer *NQR109Timer = nil;
static BOOL NQR109Expanded = NO;

static NSString * const NQR109PrefsDomain = @"com.nextsolution.nextquickreminder";
static NSString * const NQR109DismissedKey = @"DismissedReminderOccurrences";

static NSDate *NQR109DateFromJSON(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text = (NSString *)value;
    NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
    NSDate *date = [iso dateFromString:text];
    if (date) return date;
    iso.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    return [iso dateFromString:text];
}

static NSString *NQR109JSONStringFromDate(NSDate *date) {
    NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
    iso.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    return [iso stringFromDate:date];
}

static NSString *NQR109ReminderID(NSDictionary *reminder) {
    id value = reminder[@"id"];
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSString *NQR109OccurrenceFingerprint(NSDictionary *reminder) {
    NSString *reminderID = NQR109ReminderID(reminder) ?: @"";
    NSString *due = [reminder[@"dueDate"] isKindOfClass:NSString.class] ? reminder[@"dueDate"] : @"";
    return [NSString stringWithFormat:@"%@|%@", reminderID, due];
}

static NSDictionary *NQR109DismissedOccurrences(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((CFStringRef)NQR109DismissedKey, (CFStringRef)NQR109PrefsDomain);
    NSDictionary *result = nil;
    if (value && CFGetTypeID(value) == CFDictionaryGetTypeID()) {
        result = [(NSDictionary *)value copy];
    }
    if (value) CFRelease(value);
    return result ?: @{};
}

static BOOL NQR109IsDismissed(NSDictionary *reminder) {
    NSString *reminderID = NQR109ReminderID(reminder);
    if (!reminderID.length) return NO;
    NSString *saved = NQR109DismissedOccurrences()[reminderID];
    return [saved isKindOfClass:NSString.class] && [saved isEqualToString:NQR109OccurrenceFingerprint(reminder)];
}

static void NQR109MarkDismissed(NSDictionary *reminder) {
    NSString *reminderID = NQR109ReminderID(reminder);
    if (!reminderID.length) return;

    NSMutableDictionary *dismissed = [NQR109DismissedOccurrences() mutableCopy];
    dismissed[reminderID] = NQR109OccurrenceFingerprint(reminder);

    // Keep the preference lightweight if many historical reminders are dismissed.
    if (dismissed.count > 250) {
        NSArray *keys = dismissed.allKeys;
        NSUInteger removeCount = dismissed.count - 200;
        for (NSUInteger i = 0; i < removeCount && i < keys.count; i++) {
            [dismissed removeObjectForKey:keys[i]];
        }
    }

    CFPreferencesSetAppValue((CFStringRef)NQR109DismissedKey, (CFPropertyListRef)dismissed, (CFStringRef)NQR109PrefsDomain);
    CFPreferencesAppSynchronize((CFStringRef)NQR109PrefsDomain);
    NSLog(@"[NextQuickReminder] Dismissed occurrence %@", NQR109OccurrenceFingerprint(reminder));
}

static NSString *NQR109ActiveDatabasePath(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *roots = @[@"/var/mobile/Containers/Data/Application", @"/private/var/mobile/Containers/Data/Application"];
    NSString *fallback = nil;
    NSDate *fallbackDate = nil;

    for (NSString *root in roots) {
        NSArray *containers = [fm contentsOfDirectoryAtPath:root error:nil] ?: @[];
        for (NSString *container in containers) {
            NSString *containerPath = [root stringByAppendingPathComponent:container];
            NSString *metadataPath = [containerPath stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
            NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
            NSString *identifier = [metadata[@"MCMMetadataIdentifier"] isKindOfClass:NSString.class] ? metadata[@"MCMMetadataIdentifier"] : nil;
            NSString *db = [containerPath stringByAppendingPathComponent:@"Library/Application Support/NextReminder/NextReminderDatabase.json"];
            if (![fm fileExistsAtPath:db]) continue;

            if ([identifier isEqualToString:@"com.nextsolution.nextreminder"]) return db;

            NSDate *modified = [fm attributesOfItemAtPath:db error:nil][NSFileModificationDate];
            if (!fallbackDate || (modified && [modified compare:fallbackDate] == NSOrderedDescending)) {
                fallback = db;
                fallbackDate = modified;
            }
        }
    }
    return fallback;
}

static BOOL NQR109ReloadDatabase(BOOL force) {
    NSString *path = NQR109ActiveDatabasePath();
    if (!path.length) {
        NQR109DatabasePath = nil;
        NQR109DatabaseModifiedAt = nil;
        NQR109Reminders = @[];
        NQR109Categories = @[];
        return YES;
    }

    NSDate *modified = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileModificationDate];
    BOOL pathChanged = ![NQR109DatabasePath isEqualToString:path];
    BOOL modificationChanged = !NQR109DatabaseModifiedAt || ![NQR109DatabaseModifiedAt isEqualToDate:modified];
    if (!force && !pathChanged && !modificationChanged) return NO;

    NSData *data = [NSData dataWithContentsOfFile:path];
    NSDictionary *database = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![database isKindOfClass:NSDictionary.class]) return NO;

    NQR109DatabasePath = path;
    NQR109DatabaseModifiedAt = modified;
    NQR109Reminders = [database[@"reminders"] isKindOfClass:NSArray.class] ? database[@"reminders"] : @[];
    NQR109Categories = [database[@"categories"] isKindOfClass:NSArray.class] ? database[@"categories"] : @[];
    return YES;
}

static NSString *NQR109CategoryName(id categoryID) {
    if (![categoryID isKindOfClass:NSString.class]) return @"Reminder";
    for (NSDictionary *category in NQR109Categories) {
        if (![category isKindOfClass:NSDictionary.class]) continue;
        if ([category[@"id"] isEqual:categoryID]) {
            NSString *name = [category[@"name"] isKindOfClass:NSString.class] ? category[@"name"] : nil;
            if (name.length) return name;
        }
    }
    return @"Reminder";
}

static NSDictionary *NQR109DueReminder(void) {
    NSDate *now = [NSDate date];
    NSDictionary *best = nil;
    NSDate *bestDate = nil;
    for (NSDictionary *item in NQR109Reminders) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        id completedAt = item[@"completedAt"];
        if (completedAt && completedAt != NSNull.null) continue;
        NSNumber *enabled = [item[@"notificationsEnabled"] isKindOfClass:NSNumber.class] ? item[@"notificationsEnabled"] : nil;
        if (enabled && !enabled.boolValue) continue;
        if (NQR109IsDismissed(item)) continue;

        NSDate *due = NQR109DateFromJSON(item[@"dueDate"]);
        if (!due || [due compare:now] == NSOrderedDescending) continue;
        if (!bestDate || [due compare:bestDate] == NSOrderedAscending) {
            best = item;
            bestDate = due;
        }
    }
    return best;
}

static NSMutableDictionary *NQR109MutableDatabase(void) {
    if (!NQR109DatabasePath.length) NQR109ReloadDatabase(YES);
    NSData *data = NQR109DatabasePath.length ? [NSData dataWithContentsOfFile:NQR109DatabasePath] : nil;
    if (!data.length) return nil;
    id decoded = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    return [decoded isKindOfClass:NSDictionary.class] ? [decoded mutableCopy] : nil;
}

static BOOL NQR109WriteDatabase(NSMutableDictionary *database) {
    if (!database || !NQR109DatabasePath.length) return NO;
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:database options:0 error:&error];
    if (!data || error) return NO;
    BOOL ok = [data writeToFile:NQR109DatabasePath options:NSDataWritingAtomic error:&error];
    if (ok) {
        NQR109DatabaseModifiedAt = nil;
        NQR109ReloadDatabase(YES);
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

static NSDate *NQR109NextRepeatDate(NSString *rule, NSDate *date) {
    if (![rule isKindOfClass:NSString.class] || [rule isEqualToString:@"never"]) return nil;
    NSDateComponents *c = [NSDateComponents new];
    if ([rule isEqualToString:@"daily"]) c.day = 1;
    else if ([rule isEqualToString:@"weekly"]) c.weekOfYear = 1;
    else if ([rule isEqualToString:@"monthly"]) c.month = 1;
    else if ([rule isEqualToString:@"yearly"]) c.year = 1;
    else return nil;
    return [NSCalendar.currentCalendar dateByAddingComponents:c toDate:date options:0];
}

static BOOL NQR109ApplyAction(NSString *reminderID, BOOL completed, NSTimeInterval extendSeconds) {
    NSMutableDictionary *database = NQR109MutableDatabase();
    NSMutableArray *reminders = [database[@"reminders"] mutableCopy];
    if (!database || !reminders || !reminderID.length) return NO;

    NSDate *now = [NSDate date];
    BOOL changed = NO;
    for (NSUInteger i = 0; i < reminders.count; i++) {
        NSDictionary *raw = reminders[i];
        if (![raw isKindOfClass:NSDictionary.class] || ![raw[@"id"] isEqual:reminderID]) continue;
        NSMutableDictionary *item = [raw mutableCopy];

        if (completed) {
            NSDate *due = NQR109DateFromJSON(item[@"dueDate"]) ?: now;
            NSString *rule = [item[@"repeatRule"] isKindOfClass:NSString.class] ? item[@"repeatRule"] : @"never";
            NSDate *next = NQR109NextRepeatDate(rule, due);
            if (next) {
                while ([next compare:now] != NSOrderedDescending) {
                    NSDate *later = NQR109NextRepeatDate(rule, next);
                    if (!later) break;
                    next = later;
                }
                item[@"dueDate"] = NQR109JSONStringFromDate(next);
                item[@"completedAt"] = NSNull.null;
            } else {
                item[@"completedAt"] = NQR109JSONStringFromDate(now);
            }
            item[@"completionComment"] = @"Completed from Dynamic Island";
        } else if (extendSeconds > 0) {
            NSDate *newDue = [now dateByAddingTimeInterval:extendSeconds];
            NSDate *oldDue = NQR109DateFromJSON(item[@"dueDate"]);
            item[@"dueDate"] = NQR109JSONStringFromDate(newDue);
            if (oldDue) {
                NSDate *deadline = NQR109DateFromJSON(item[@"deadlineDate"]);
                if (deadline) item[@"deadlineDate"] = NQR109JSONStringFromDate([deadline dateByAddingTimeInterval:[newDue timeIntervalSinceDate:oldDue]]);
            }
            item[@"completedAt"] = NSNull.null;
            item[@"completionComment"] = NSNull.null;
        }
        item[@"updatedAt"] = NQR109JSONStringFromDate(now);
        reminders[i] = item;
        changed = YES;
        break;
    }

    if (!changed) return NO;
    database[@"reminders"] = reminders;
    return NQR109WriteDatabase(database);
}

static void NQR109RemoveIsland(void);

@interface NQR109ApertureCard : UIControl
@property(nonatomic, strong) UILabel *iconLabel;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *metaLabel;
@property(nonatomic, strong) UIButton *completeButton;
@property(nonatomic, strong) UIButton *extendButton;
@property(nonatomic, strong) UIButton *dismissButton;
@property(nonatomic, copy) NSString *reminderID;
- (void)applyReminder:(NSDictionary *)reminder;
- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated;
@end

@implementation NQR109ApertureCard
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor = UIColor.blackColor;
    self.layer.cornerRadius = 27.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;
    self.accessibilityLabel = @"Next Reminder due";

    _iconLabel = [UILabel new];
    _iconLabel.text = @"●";
    _iconLabel.textColor = UIColor.systemOrangeColor;
    _iconLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];

    _titleLabel = [UILabel new];
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _titleLabel.numberOfLines = 2;

    _metaLabel = [UILabel new];
    _metaLabel.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.65];
    _metaLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    _metaLabel.numberOfLines = 1;

    _completeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_completeButton setTitle:@"✓ Done" forState:UIControlStateNormal];
    [_completeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _completeButton.backgroundColor = UIColor.systemGreenColor;
    _completeButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    _completeButton.layer.cornerRadius = 11;
    [_completeButton addTarget:self action:@selector(completeTapped) forControlEvents:UIControlEventTouchUpInside];

    _extendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_extendButton setTitle:@"↻ +10m" forState:UIControlStateNormal];
    [_extendButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _extendButton.backgroundColor = UIColor.systemOrangeColor;
    _extendButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    _extendButton.layer.cornerRadius = 11;
    [_extendButton addTarget:self action:@selector(extendTapped) forControlEvents:UIControlEventTouchUpInside];

    _dismissButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_dismissButton setTitle:@"Dismiss" forState:UIControlStateNormal];
    [_dismissButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _dismissButton.backgroundColor = [UIColor colorWithWhite:0.24 alpha:1.0];
    _dismissButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    _dismissButton.layer.cornerRadius = 11;
    [_dismissButton addTarget:self action:@selector(dismissTapped) forControlEvents:UIControlEventTouchUpInside];

    for (UIView *view in @[_iconLabel, _titleLabel, _metaLabel, _completeButton, _extendButton, _dismissButton]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:view];
    }

    [NSLayoutConstraint activateConstraints:@[
        [_iconLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [_iconLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:11],
        [_iconLabel.widthAnchor constraintEqualToConstant:18],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconLabel.trailingAnchor constant:7],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:9],
        [_metaLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_metaLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_metaLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:1],

        [_completeButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [_completeButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-9],
        [_completeButton.heightAnchor constraintEqualToConstant:36],
        [_extendButton.leadingAnchor constraintEqualToAnchor:_completeButton.trailingAnchor constant:6],
        [_extendButton.bottomAnchor constraintEqualToAnchor:_completeButton.bottomAnchor],
        [_extendButton.heightAnchor constraintEqualToAnchor:_completeButton.heightAnchor],
        [_dismissButton.leadingAnchor constraintEqualToAnchor:_extendButton.trailingAnchor constant:6],
        [_dismissButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [_dismissButton.bottomAnchor constraintEqualToAnchor:_completeButton.bottomAnchor],
        [_dismissButton.heightAnchor constraintEqualToAnchor:_completeButton.heightAnchor],
        [_completeButton.widthAnchor constraintEqualToAnchor:_extendButton.widthAnchor],
        [_extendButton.widthAnchor constraintEqualToAnchor:_dismissButton.widthAnchor]
    ]];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    longPress.minimumPressDuration = 0.35;
    [self addGestureRecognizer:longPress];
    [self addTarget:self action:@selector(cardTapped) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)applyReminder:(NSDictionary *)reminder {
    self.reminderID = NQR109ReminderID(reminder) ?: @"";
    self.titleLabel.text = [reminder[@"title"] isKindOfClass:NSString.class] ? reminder[@"title"] : @"Reminder due";
    NSString *category = NQR109CategoryName(reminder[@"categoryID"]);
    NSString *priority = [reminder[@"priority"] isKindOfClass:NSString.class] ? [reminder[@"priority"] capitalizedString] : @"Medium";
    self.metaLabel.text = [NSString stringWithFormat:@"%@ • %@ priority", category, priority];
}

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated {
    NQR109Expanded = expanded;
    self.completeButton.hidden = !expanded;
    self.extendButton.hidden = !expanded;
    self.dismissButton.hidden = !expanded;
    self.metaLabel.hidden = !expanded;

    // Both states stay attached to the top System Aperture region. 1.0.8 used
    // y=84 for its expanded state, which looked like a separate Lock Screen card.
    CGFloat width = expanded ? MIN(UIScreen.mainScreen.bounds.size.width - 18.0, 412.0) : 250.0;
    CGFloat height = expanded ? 108.0 : 54.0;
    CGFloat y = 4.0;
    CGFloat x = (UIScreen.mainScreen.bounds.size.width - width) / 2.0;
    void (^changes)(void) = ^{
        self.frame = CGRectMake(x, y, width, height);
        self.layer.cornerRadius = expanded ? 29.0 : 27.0;
        [self layoutIfNeeded];
    };
    if (animated) {
        [UIView animateWithDuration:0.30
                              delay:0
             usingSpringWithDamping:0.88
              initialSpringVelocity:0.12
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:changes
                         completion:nil];
    } else {
        changes();
    }
}

- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) [self setExpanded:!NQR109Expanded animated:YES];
}

- (void)cardTapped {
    if (!NQR109Expanded) [self setExpanded:YES animated:YES];
}

- (void)completeTapped {
    if (self.reminderID.length) NQR109ApplyAction(self.reminderID, YES, 0);
    UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
    [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
    NQR109RemoveIsland();
}

- (void)extendTapped {
    if (self.reminderID.length) NQR109ApplyAction(self.reminderID, NO, 10 * 60);
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    NQR109RemoveIsland();
}

- (void)dismissTapped {
    NSDictionary *current = NQR109CurrentReminder;
    if (current && [NQR109ReminderID(current) isEqualToString:self.reminderID]) {
        NQR109MarkDismissed(current);
    }
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
    NQR109RemoveIsland();
}
@end

static void NQR109RemoveIslandOnMain(void) {
    [NQR109IslandView removeFromSuperview];
    NQR109IslandView = nil;
    NQR109CurrentReminder = nil;
    NQR109Expanded = NO;
}

static void NQR109RemoveIsland(void) {
    if (NSThread.isMainThread) {
        NQR109RemoveIslandOnMain();
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ NQR109RemoveIslandOnMain(); });
    }
}

static void NQR109PresentReminder(NSDictionary *reminder) {
    SBSystemApertureWindow *window = NQR109SystemApertureWindow;
    if (!window || !reminder || NQR109IsDismissed(reminder)) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *reminderID = NQR109ReminderID(reminder);
        NSString *currentFingerprint = NQR109CurrentReminder ? NQR109OccurrenceFingerprint(NQR109CurrentReminder) : nil;
        NSString *newFingerprint = NQR109OccurrenceFingerprint(reminder);
        if ([currentFingerprint isEqualToString:newFingerprint] && NQR109IslandView.superview == window) return;

        NQR109RemoveIslandOnMain();
        NQR109CurrentReminder = reminder;

        NQR109ApertureCard *card = [[NQR109ApertureCard alloc] initWithFrame:CGRectZero];
        [card applyReminder:reminder];
        [window addSubview:card];
        NQR109IslandView = card;
        // Start in the compact island state. Expand only when the user taps it.
        [card setExpanded:NO animated:NO];
        window.userInteractionEnabled = YES;
        [window bringSubviewToFront:card];

        NSLog(@"[NextQuickReminder] Reminder attached to System Aperture island: %@ (%@)", reminder[@"title"], reminderID);
    });
}

static void NQR109Evaluate(void) {
    NQR109ReloadDatabase(NO);
    NSDictionary *due = NQR109DueReminder();
    if (!due) {
        NQR109RemoveIsland();
        return;
    }

    // Unlike 1.0.8, do not remove/recreate the activity merely because the
    // phone is unlocked. This prevents lock/unlock cycles from feeling like a
    // new alert and keeps the current island item stable until acted upon.
    NQR109PresentReminder(due);
}

static void NQR109DatabaseChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NQR109DatabaseModifiedAt = nil;
        NQR109ReloadDatabase(YES);
        NQR109Evaluate();
    });
}

%hook SBSystemApertureWindow
- (void)didMoveToScreen:(UIScreen *)screen {
    %orig;
    NQR109SystemApertureWindow = self;
    dispatch_async(dispatch_get_main_queue(), ^{ NQR109Evaluate(); });
}

- (void)layoutSubviews {
    %orig;
    NQR109SystemApertureWindow = self;
    if (NQR109IslandView.superview == self) [self bringSubviewToFront:NQR109IslandView];
}
%end

__attribute__((constructor)) static void NQR109SystemApertureInit(void) {
    @autoreleasepool {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            NQR109DatabaseChanged,
            CFSTR("com.nextsolution.nextreminder.database.changed"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        dispatch_async(dispatch_get_main_queue(), ^{
            NQR109ReloadDatabase(YES);
            NQR109Timer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(__unused NSTimer *timer) {
                NQR109Evaluate();
            }];
            [NQR109Timer fire];
            NSLog(@"[NextQuickReminder] 1.0.9 island-only System Aperture reminder loaded with persistent dismiss state");
        });
    }
}
