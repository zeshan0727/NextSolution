#import "PAConceptDSurfaces.h"
#import "PAConceptDUI.h"
#import "PADataStore.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <sqlite3.h>

#pragma mark - Call model additions

typedef NS_ENUM(NSUInteger, PARecentFilterV47) {
    PARecentFilterV47All = 0,
    PARecentFilterV47Dialed,
    PARecentFilterV47Received,
    PARecentFilterV47Missed
};

static const void *PA47RecordIDKey = &PA47RecordIDKey;
static const void *PA47AnsweredKey = &PA47AnsweredKey;

@interface PARecentCall (PhoneAuraV47)
@property(nonatomic) NSInteger pa47_recordID;
@property(nonatomic) BOOL pa47_answered;
@end

@implementation PARecentCall (PhoneAuraV47)
- (void)setPa47_recordID:(NSInteger)value {
    objc_setAssociatedObject(self, PA47RecordIDKey, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSInteger)pa47_recordID {
    return [objc_getAssociatedObject(self, PA47RecordIDKey) integerValue];
}
- (void)setPa47_answered:(BOOL)value {
    objc_setAssociatedObject(self, PA47AnsweredKey, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)pa47_answered {
    return [objc_getAssociatedObject(self, PA47AnsweredKey) boolValue];
}
@end

#pragma mark - Data store additions

@interface PADataStore (PhoneAuraV47Private)
@property(nonatomic,readonly) dispatch_queue_t workQueue;
- (NSString *)callHistoryDatabasePath;
- (NSDictionary<NSString *, NSString *> *)columnsForTable:(NSString *)table database:(sqlite3 *)database;
- (NSString *)displayNameForNumber:(NSString *)number;
@end

@interface PADataStore (PhoneAuraV47)
- (void)pa47_recentCallsWithFilter:(PARecentFilterV47)filter
                             limit:(NSUInteger)limit
                        completion:(void (^)(NSArray<PARecentCall *> *calls))completion;
- (void)pa47_deleteRecentCall:(PARecentCall *)call
                   completion:(void (^)(BOOL success, NSString *message))completion;
@end

static NSString *PA47StringColumn(sqlite3_stmt *statement, int index) {
    const unsigned char *text = sqlite3_column_text(statement, index);
    return text ? [NSString stringWithUTF8String:(const char *)text] : @"";
}

@implementation PADataStore (PhoneAuraV47)

- (void)pa47_recentCallsWithFilter:(PARecentFilterV47)filter
                             limit:(NSUInteger)limit
                        completion:(void (^)(NSArray<PARecentCall *> *calls))completion {
    dispatch_queue_t queue = self.workQueue ?: dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    dispatch_async(queue, ^{
        @autoreleasepool {
            NSMutableArray<PARecentCall *> *calls = [NSMutableArray array];
            NSString *databasePath = [self callHistoryDatabasePath];
            sqlite3 *database = NULL;

            if (!databasePath ||
                sqlite3_open_v2(databasePath.fileSystemRepresentation,
                                &database,
                                SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
                                NULL) != SQLITE_OK) {
                if (database) sqlite3_close(database);
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(@[]); });
                return;
            }

            sqlite3_busy_timeout(database, 900);
            NSDictionary<NSString *, NSString *> *columns =
                [self columnsForTable:@"ZCALLRECORD" database:database];

            NSString *primaryKey = columns[@"Z_PK"];
            NSString *address = columns[@"ZADDRESS"];
            NSString *date = columns[@"ZDATE"];
            NSString *duration = columns[@"ZDURATION"] ?: @"0";
            NSString *originated = columns[@"ZORIGINATED"] ?: @"0";
            NSString *answered = columns[@"ZANSWERED"] ?: @"0";

            if (!primaryKey || !address || !date) {
                sqlite3_close(database);
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(@[]); });
                return;
            }

            NSString *whereClause = @"";
            switch (filter) {
                case PARecentFilterV47Dialed:
                    whereClause = [NSString stringWithFormat:@" WHERE %@ != 0", originated];
                    break;
                case PARecentFilterV47Received:
                    whereClause = [NSString stringWithFormat:@" WHERE %@ = 0 AND %@ != 0", originated, answered];
                    break;
                case PARecentFilterV47Missed:
                    whereClause = [NSString stringWithFormat:@" WHERE %@ = 0 AND %@ = 0", originated, answered];
                    break;
                default:
                    break;
            }

            NSUInteger safeLimit = MAX((NSUInteger)20, MIN(limit ?: 140, (NSUInteger)300));
            NSString *sql = [NSString stringWithFormat:
                @"SELECT %@, %@, %@, %@, %@, %@ FROM ZCALLRECORD%@ ORDER BY %@ DESC LIMIT %lu",
                primaryKey, address, date, duration, originated, answered,
                whereClause, date, (unsigned long)safeLimit];

            sqlite3_stmt *statement = NULL;
            if (sqlite3_prepare_v2(database, sql.UTF8String, -1, &statement, NULL) == SQLITE_OK) {
                while (sqlite3_step(statement) == SQLITE_ROW) {
                    NSInteger recordID = sqlite3_column_int64(statement, 0);
                    NSString *number = PA47StringColumn(statement, 1);
                    NSTimeInterval rawDate = sqlite3_column_double(statement, 2);
                    NSTimeInterval callDuration = sqlite3_column_double(statement, 3);
                    BOOL callOriginated = sqlite3_column_int(statement, 4) != 0;
                    BOOL callAnswered = sqlite3_column_int(statement, 5) != 0;
                    BOOL callMissed = !callOriginated && !callAnswered;
                    NSTimeInterval unixDate = rawDate < 1200000000.0 ? rawDate + 978307200.0 : rawDate;

                    PARecentCall *call = [[PARecentCall alloc] init];
                    call.pa47_recordID = recordID;
                    call.pa47_answered = callAnswered;
                    call.number = number.length ? number : @"Unknown";
                    call.displayName = [self displayNameForNumber:number];
                    call.date = [NSDate dateWithTimeIntervalSince1970:unixDate];
                    call.duration = callDuration;
                    call.missed = callMissed;
                    call.outgoing = callOriginated;
                    [calls addObject:call];
                }
            }

            if (statement) sqlite3_finalize(statement);
            sqlite3_close(database);
            NSArray<PARecentCall *> *snapshot = [calls copy];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(snapshot); });
        }
    });
}

- (void)pa47_deleteRecentCall:(PARecentCall *)call
                   completion:(void (^)(BOOL success, NSString *message))completion {
    if (!call || call.pa47_recordID <= 0) {
        if (completion) completion(NO, @"This call record cannot be identified.");
        return;
    }

    dispatch_queue_t queue = self.workQueue ?: dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    dispatch_async(queue, ^{
        @autoreleasepool {
            BOOL success = NO;
            NSString *message = @"Unable to delete the call record.";
            NSString *databasePath = [self callHistoryDatabasePath];
            sqlite3 *database = NULL;

            if (databasePath &&
                sqlite3_open_v2(databasePath.fileSystemRepresentation,
                                &database,
                                SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX,
                                NULL) == SQLITE_OK) {
                sqlite3_busy_timeout(database, 1600);
                NSDictionary<NSString *, NSString *> *columns =
                    [self columnsForTable:@"ZCALLRECORD" database:database];
                NSString *primaryKey = columns[@"Z_PK"];

                if (primaryKey.length) {
                    sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION", NULL, NULL, NULL);
                    NSString *sql = [NSString stringWithFormat:@"DELETE FROM ZCALLRECORD WHERE %@ = ?", primaryKey];
                    sqlite3_stmt *statement = NULL;
                    if (sqlite3_prepare_v2(database, sql.UTF8String, -1, &statement, NULL) == SQLITE_OK) {
                        sqlite3_bind_int64(statement, 1, (sqlite3_int64)call.pa47_recordID);
                        int result = sqlite3_step(statement);
                        success = result == SQLITE_DONE && sqlite3_changes(database) > 0;
                    }
                    if (statement) sqlite3_finalize(statement);
                    sqlite3_exec(database, success ? "COMMIT" : "ROLLBACK", NULL, NULL, NULL);
                    if (success) {
                        sqlite3_wal_checkpoint_v2(database, NULL, SQLITE_CHECKPOINT_PASSIVE, NULL, NULL);
                        message = @"Call record deleted.";
                    }
                }
                sqlite3_close(database);
            }

            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(success, message); });
        }
    });
}

@end

#pragma mark - Recents visual helpers

static NSString *PA47DirectionTitle(PARecentCall *call) {
    if (call.outgoing) return @"Dialed";
    if (call.missed) return @"Missed";
    return @"Received";
}

static UIColor *PA47DirectionColor(PARecentCall *call) {
    if (call.missed) return PAColorHex(0xFF5B61, 1.0);
    if (call.outgoing) return PAColorHex(0x6F63FF, 1.0);
    return PAColorHex(0x18C8B7, 1.0);
}

static NSString *PA47DurationText(PARecentCall *call) {
    if (call.missed || !call.pa47_answered) return @"Not answered";
    NSInteger total = MAX(0, (NSInteger)llround(call.duration));
    NSInteger hours = total / 3600;
    NSInteger minutes = (total % 3600) / 60;
    NSInteger seconds = total % 60;
    if (hours > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)seconds];
}

static UIViewController *PA47TopController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
        if (window) break;
    }
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    if ([controller isKindOfClass:[UINavigationController class]]) controller = ((UINavigationController *)controller).topViewController;
    if ([controller isKindOfClass:[UITabBarController class]]) controller = ((UITabBarController *)controller).selectedViewController;
    return controller;
}

static void PA47Toast(UIView *host, NSString *text, BOOL error) {
    if (!host || !text.length) return;
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 2;
    label.backgroundColor = error ? PAColorHex(0xB91C1C, 0.96) : PAColorHex(0x166534, 0.96);
    label.layer.cornerRadius = 14;
    label.layer.cornerCurve = kCACornerCurveContinuous;
    label.layer.masksToBounds = YES;
    CGFloat width = MIN(CGRectGetWidth(host.bounds) - 40, 300);
    label.frame = CGRectMake((CGRectGetWidth(host.bounds) - width) / 2.0,
                             CGRectGetHeight(host.bounds) - 82,
                             width,
                             48);
    label.alpha = 0;
    [host addSubview:label];
    [UIView animateWithDuration:0.18 animations:^{ label.alpha = 1; } completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.2 delay:1.2 options:0 animations:^{ label.alpha = 0; } completion:^(__unused BOOL done) { [label removeFromSuperview]; }];
    }];
}

@interface PARecentCellV47 : UITableViewCell
@property(nonatomic,strong) UIView *card;
@property(nonatomic,strong) UIView *strip;
@property(nonatomic,strong) UIImageView *avatar;
@property(nonatomic,strong) UILabel *nameLabel;
@property(nonatomic,strong) UILabel *detailLabel;
@property(nonatomic,strong) UILabel *timeLabel;
@property(nonatomic,strong) UIButton *infoButton;
@property(nonatomic,strong) PARecentCall *call;
@property(nonatomic,copy) void (^infoHandler)(PARecentCall *call);
- (void)configureCall:(PARecentCall *)call;
@end

@implementation PARecentCellV47

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _card = [[UIView alloc] init];
        _card.backgroundColor = PAColorHex(0x17213D, 0.98);
        _card.layer.cornerRadius = 16;
        _card.layer.cornerCurve = kCACornerCurveContinuous;
        _card.layer.borderWidth = 0.7;
        _card.layer.borderColor = PAColorHex(0x63708E, 0.20).CGColor;
        [self.contentView addSubview:_card];
        _strip = [[UIView alloc] init];
        [_card addSubview:_strip];
        _avatar = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
        _avatar.tintColor = PAColorHex(0xA7B2CA, 1.0);
        _avatar.contentMode = UIViewContentModeScaleAspectFit;
        [_card addSubview:_avatar];
        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
        _nameLabel.textColor = UIColor.whiteColor;
        [_card addSubview:_nameLabel];
        _detailLabel = [[UILabel alloc] init];
        _detailLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _detailLabel.textColor = PAColorHex(0xA7B2CA, 1.0);
        [_card addSubview:_detailLabel];
        _timeLabel = [[UILabel alloc] init];
        _timeLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _timeLabel.textColor = PAColorHex(0xA7B2CA, 1.0);
        _timeLabel.textAlignment = NSTextAlignmentRight;
        [_card addSubview:_timeLabel];
        _infoButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_infoButton setImage:[UIImage systemImageNamed:@"info.circle.fill"] forState:UIControlStateNormal];
        [_infoButton addTarget:self action:@selector(infoTapped) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:_infoButton];
    }
    return self;
}

- (void)configureCall:(PARecentCall *)call {
    self.call = call;
    UIColor *color = PA47DirectionColor(call);
    self.strip.backgroundColor = color;
    self.infoButton.tintColor = color;
    self.nameLabel.text = call.displayName.length ? call.displayName : call.number;
    self.nameLabel.textColor = call.missed ? PAColorHex(0xFF6B70, 1.0) : UIColor.whiteColor;
    self.detailLabel.text = [NSString stringWithFormat:@"%@ · %@", PA47DirectionTitle(call), PA47DurationText(call)];

    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.doesRelativeDateFormatting = YES;
        formatter.dateStyle = NSDateFormatterShortStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
    });
    @synchronized (formatter) { self.timeLabel.text = [formatter stringFromDate:call.date]; }
}

- (void)infoTapped {
    if (self.infoHandler && self.call) self.infoHandler(self.call);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.card.frame = CGRectInset(self.contentView.bounds, 14, 5);
    self.strip.frame = CGRectMake(0, 0, 5, CGRectGetHeight(self.card.bounds));
    self.strip.layer.cornerRadius = 2.5;
    self.avatar.frame = CGRectMake(16, 15, 38, 38);
    CGFloat right = CGRectGetWidth(self.card.bounds) - 12;
    self.infoButton.frame = CGRectMake(right - 31, 18, 30, 30);
    self.timeLabel.frame = CGRectMake(right - 130, 10, 92, 20);
    CGFloat textX = CGRectGetMaxX(self.avatar.frame) + 12;
    self.nameLabel.frame = CGRectMake(textX, 11, CGRectGetMinX(self.timeLabel.frame) - textX - 6, 23);
    self.detailLabel.frame = CGRectMake(textX, 36, CGRectGetMinX(self.infoButton.frame) - textX - 6, 18);
}

@end

@interface PARecentDetailOverlayV47 : UIView
@property(nonatomic,strong) UIView *backdrop;
@property(nonatomic,strong) UIView *card;
@property(nonatomic,strong) UIButton *closeButton;
@property(nonatomic,strong) UILabel *nameLabel;
@property(nonatomic,strong) UILabel *numberLabel;
@property(nonatomic,strong) UIStackView *detailsStack;
@property(nonatomic,strong) UIButton *callButton;
@property(nonatomic,strong) UIButton *deleteButton;
@property(nonatomic,strong) PARecentCall *call;
@property(nonatomic,copy) void (^callHandler)(NSString *number);
@property(nonatomic,copy) void (^deleteHandler)(PARecentCall *call);
- (void)configureCall:(PARecentCall *)call;
@end

@implementation PARecentDetailOverlayV47

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        _backdrop = [[UIView alloc] init];
        _backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:0.56];
        [self addSubview:_backdrop];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeTapped)];
        [_backdrop addGestureRecognizer:tap];

        _card = [[UIView alloc] init];
        _card.backgroundColor = PAColorHex(0x101A32, 1.0);
        _card.layer.cornerRadius = 25;
        _card.layer.cornerCurve = kCACornerCurveContinuous;
        _card.layer.borderWidth = 0.8;
        _card.layer.borderColor = PAColorHex(0x63708E, 0.30).CGColor;
        [self addSubview:_card];

        _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _closeButton.tintColor = PAColorHex(0xA7B2CA, 1.0);
        [_closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
        [_closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:_closeButton];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.textColor = UIColor.whiteColor;
        _nameLabel.font = [UIFont systemFontOfSize:23 weight:UIFontWeightBold];
        _nameLabel.textAlignment = NSTextAlignmentCenter;
        _nameLabel.adjustsFontSizeToFitWidth = YES;
        _nameLabel.minimumScaleFactor = 0.65;
        [_card addSubview:_nameLabel];

        _numberLabel = [[UILabel alloc] init];
        _numberLabel.textColor = PAColorHex(0xA7B2CA, 1.0);
        _numberLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _numberLabel.textAlignment = NSTextAlignmentCenter;
        [_card addSubview:_numberLabel];

        _detailsStack = [[UIStackView alloc] init];
        _detailsStack.axis = UILayoutConstraintAxisVertical;
        _detailsStack.spacing = 8;
        _detailsStack.distribution = UIStackViewDistributionFillEqually;
        [_card addSubview:_detailsStack];

        _callButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_callButton setTitle:@"Call Again" forState:UIControlStateNormal];
        [_callButton setImage:[UIImage systemImageNamed:@"phone.fill"] forState:UIControlStateNormal];
        _callButton.tintColor = UIColor.whiteColor;
        _callButton.backgroundColor = PAColorHex(0x22C55E, 1.0);
        _callButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        _callButton.layer.cornerRadius = 16;
        [_callButton addTarget:self action:@selector(callTapped) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:_callButton];

        _deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_deleteButton setTitle:@"Delete Call Record" forState:UIControlStateNormal];
        [_deleteButton setImage:[UIImage systemImageNamed:@"trash.fill"] forState:UIControlStateNormal];
        _deleteButton.tintColor = UIColor.whiteColor;
        _deleteButton.backgroundColor = PAColorHex(0xB91C1C, 1.0);
        _deleteButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        _deleteButton.layer.cornerRadius = 16;
        [_deleteButton addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:_deleteButton];
    }
    return self;
}

- (UILabel *)detailRow:(NSString *)title value:(NSString *)value color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.numberOfLines = 1;
    NSString *text = [NSString stringWithFormat:@"%@   %@", title, value ?: @""];
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName:[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName:UIColor.whiteColor
    }];
    [attributed addAttribute:NSForegroundColorAttributeName value:PAColorHex(0xA7B2CA,1.0) range:NSMakeRange(0, title.length)];
    if (value.length) [attributed addAttribute:NSForegroundColorAttributeName value:color ?: UIColor.whiteColor range:[text rangeOfString:value options:NSBackwardsSearch]];
    label.attributedText = attributed;
    return label;
}

- (void)configureCall:(PARecentCall *)call {
    self.call = call;
    self.nameLabel.text = call.displayName.length ? call.displayName : call.number;
    self.numberLabel.text = call.number.length ? call.number : @"Unknown number";
    for (UIView *view in self.detailsStack.arrangedSubviews) {
        [self.detailsStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    static NSDateFormatter *dateFormatter;
    static NSDateFormatter *timeFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateStyle = NSDateFormatterFullStyle;
        dateFormatter.timeStyle = NSDateFormatterNoStyle;
        timeFormatter = [[NSDateFormatter alloc] init];
        timeFormatter.dateStyle = NSDateFormatterNoStyle;
        timeFormatter.timeStyle = NSDateFormatterMediumStyle;
    });

    NSString *dateText;
    NSString *timeText;
    @synchronized (dateFormatter) { dateText = [dateFormatter stringFromDate:call.date]; }
    @synchronized (timeFormatter) { timeText = [timeFormatter stringFromDate:call.date]; }
    UIColor *directionColor = PA47DirectionColor(call);
    [self.detailsStack addArrangedSubview:[self detailRow:@"Direction" value:PA47DirectionTitle(call) color:directionColor]];
    [self.detailsStack addArrangedSubview:[self detailRow:@"Date" value:dateText color:UIColor.whiteColor]];
    [self.detailsStack addArrangedSubview:[self detailRow:@"Time" value:timeText color:UIColor.whiteColor]];
    [self.detailsStack addArrangedSubview:[self detailRow:@"Duration" value:PA47DurationText(call) color:UIColor.whiteColor]];
    [self.detailsStack addArrangedSubview:[self detailRow:@"Type" value:@"Phone call" color:UIColor.whiteColor]];
    self.card.layer.borderColor = [directionColor colorWithAlphaComponent:0.40].CGColor;
    self.callButton.enabled = call.number.length && ![call.number isEqualToString:@"Unknown"];
    self.callButton.alpha = self.callButton.enabled ? 1 : 0.45;
}

- (void)closeTapped {
    [UIView animateWithDuration:0.18 animations:^{ self.alpha = 0; } completion:^(__unused BOOL finished) { [self removeFromSuperview]; }];
}

- (void)callTapped {
    if (self.callHandler && self.call.number.length) self.callHandler(self.call.number);
}

- (void)deleteTapped {
    UIViewController *controller = PA47TopController();
    if (!controller) { if (self.deleteHandler) self.deleteHandler(self.call); return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Call Record?"
                                                                   message:@"This removes this entry from your call history."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        if (weakSelf.deleteHandler) weakSelf.deleteHandler(weakSelf.call);
    }]];
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.deleteButton;
        alert.popoverPresentationController.sourceRect = self.deleteButton.bounds;
    }
    [controller presentViewController:alert animated:YES completion:nil];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.backdrop.frame = self.bounds;
    CGFloat width = MIN(CGRectGetWidth(self.bounds) - 32, 390);
    CGFloat height = 410;
    self.card.frame = CGRectMake((CGRectGetWidth(self.bounds)-width)/2.0,
                                 MAX(16, (CGRectGetHeight(self.bounds)-height)/2.0),
                                 width,
                                 height);
    self.closeButton.frame = CGRectMake(width-48, 14, 34, 34);
    self.nameLabel.frame = CGRectMake(38, 34, width-76, 34);
    self.numberLabel.frame = CGRectMake(30, 70, width-60, 24);
    self.detailsStack.frame = CGRectMake(24, 112, width-48, 178);
    self.callButton.frame = CGRectMake(20, height-100, (width-50)/2.0, 54);
    self.deleteButton.frame = CGRectMake(CGRectGetMaxX(self.callButton.frame)+10, height-100, (width-50)/2.0, 54);
}

@end

#pragma mark - Recents dashboard replacement by method swizzling

static const void *PA47FilterKey = &PA47FilterKey;
static const void *PA47TableKey = &PA47TableKey;
static const void *PA47EmptyKey = &PA47EmptyKey;
static const void *PA47CallsKey = &PA47CallsKey;
static const void *PA47RequestKey = &PA47RequestKey;

@interface PARecentsDashboardView (PhoneAuraV47) <UITableViewDataSource, UITableViewDelegate>
- (instancetype)pa47_initWithFrame:(CGRect)frame;
- (void)pa47_layoutSubviews;
- (void)pa47_refresh;
- (void)pa47_filterChanged;
- (NSInteger)pa47_tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
- (UITableViewCell *)pa47_tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)pa47_tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
@end

@implementation PARecentsDashboardView (PhoneAuraV47)

- (instancetype)pa47_initWithFrame:(CGRect)frame {
    self = [self pa47_initWithFrame:frame];
    if (!self) return nil;

    for (UIView *view in self.subviews.copy) [view removeFromSuperview];
    self.backgroundColor = PAColorHex(0x040817, 1.0);

    UISegmentedControl *filter = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Dialed", @"Received", @"Missed"]];
    filter.selectedSegmentIndex = 0;
    filter.selectedSegmentTintColor = PAColorHex(0x6F63FF, 1.0);
    [filter setTitleTextAttributes:@{
        NSForegroundColorAttributeName:UIColor.whiteColor,
        NSFontAttributeName:[UIFont systemFontOfSize:11 weight:UIFontWeightBold]
    } forState:UIControlStateNormal];
    [filter addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
    [self addSubview:filter];
    objc_setAssociatedObject(self, PA47FilterKey, filter, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    table.backgroundColor = UIColor.clearColor;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.rowHeight = 72;
    table.dataSource = self;
    table.delegate = self;
    table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [table registerClass:[PARecentCellV47 class] forCellReuseIdentifier:@"recent47"];
    [self addSubview:table];
    objc_setAssociatedObject(self, PA47TableKey, table, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILabel *empty = [[UILabel alloc] init];
    empty.text = @"No calls in this category.";
    empty.textColor = PAColorHex(0xA7B2CA, 1.0);
    empty.textAlignment = NSTextAlignmentCenter;
    empty.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    empty.hidden = YES;
    [self addSubview:empty];
    objc_setAssociatedObject(self, PA47EmptyKey, empty, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    objc_setAssociatedObject(self, PA47CallsKey, @[], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self refresh];
    return self;
}

- (void)pa47_layoutSubviews {
    [self pa47_layoutSubviews];
    UISegmentedControl *filter = objc_getAssociatedObject(self, PA47FilterKey);
    UITableView *table = objc_getAssociatedObject(self, PA47TableKey);
    UILabel *empty = objc_getAssociatedObject(self, PA47EmptyKey);
    if (!filter || !table) return;
    CGFloat top = self.safeAreaInsets.top + 7;
    filter.frame = CGRectMake(16, top, CGRectGetWidth(self.bounds)-32, 36);
    CGFloat tableTop = CGRectGetMaxY(filter.frame)+7;
    table.frame = CGRectMake(0, tableTop, CGRectGetWidth(self.bounds), MAX(0, CGRectGetHeight(self.bounds)-tableTop));
    empty.frame = CGRectMake(30, CGRectGetMidY(self.bounds)-35, CGRectGetWidth(self.bounds)-60, 70);
}

- (void)pa47_filterChanged {
    if ([self respondsToSelector:@selector(hapticsEnabled)] && [(id)self hapticsEnabled]) {
        UISelectionFeedbackGenerator *generator = [[UISelectionFeedbackGenerator alloc] init];
        [generator selectionChanged];
    }
    [self refresh];
}

- (void)pa47_refresh {
    UISegmentedControl *filter = objc_getAssociatedObject(self, PA47FilterKey);
    UITableView *table = objc_getAssociatedObject(self, PA47TableKey);
    if (!filter || !table) return;

    NSUInteger request = [objc_getAssociatedObject(self, PA47RequestKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(self, PA47RequestKey, @(request), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    table.alpha = 0.62;
    PARecentFilterV47 selected = (PARecentFilterV47)MAX(0, filter.selectedSegmentIndex);

    __weak typeof(self) weakSelf = self;
    [[PADataStore sharedStore] pa47_recentCallsWithFilter:selected limit:180 completion:^(NSArray<PARecentCall *> *calls) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSUInteger current = [objc_getAssociatedObject(strongSelf, PA47RequestKey) unsignedIntegerValue];
        if (current != request) return;
        objc_setAssociatedObject(strongSelf, PA47CallsKey, calls ?: @[], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UILabel *empty = objc_getAssociatedObject(strongSelf, PA47EmptyKey);
        empty.hidden = calls.count > 0;
        table.alpha = 1;
        [table reloadData];
    }];
}

- (NSInteger)pa47_tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [objc_getAssociatedObject(self, PA47CallsKey) count];
}

- (UITableViewCell *)pa47_tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PARecentCellV47 *cell = [tableView dequeueReusableCellWithIdentifier:@"recent47" forIndexPath:indexPath];
    NSArray<PARecentCall *> *calls = objc_getAssociatedObject(self, PA47CallsKey);
    if (indexPath.row < calls.count) {
        PARecentCall *call = calls[indexPath.row];
        [cell configureCall:call];
        __weak typeof(self) weakSelf = self;
        cell.infoHandler = ^(PARecentCall *selectedCall) { [weakSelf pa47_showCallDetails:selectedCall]; };
    }
    return cell;
}

- (void)pa47_tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<PARecentCall *> *calls = objc_getAssociatedObject(self, PA47CallsKey);
    if (indexPath.row >= calls.count) return;
    PARecentCall *call = calls[indexPath.row];
    if ([self respondsToSelector:@selector(hapticsEnabled)] && [(id)self hapticsEnabled]) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator impactOccurred];
    }
    if (call.number.length && [self respondsToSelector:@selector(callHandler)]) {
        void (^handler)(NSString *) = [(id)self callHandler];
        if (handler) handler(call.number);
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
 trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<PARecentCall *> *calls = objc_getAssociatedObject(self, PA47CallsKey);
    if (indexPath.row >= calls.count) return nil;
    PARecentCall *call = calls[indexPath.row];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                                title:@"Delete"
                                                                              handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        [weakSelf pa47_deleteCall:call indexPath:indexPath completion:completionHandler closeOverlay:NO];
    }];
    deleteAction.image = [UIImage systemImageNamed:@"trash.fill"];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
    configuration.performsFirstActionWithFullSwipe = YES;
    return configuration;
}

- (void)pa47_showCallDetails:(PARecentCall *)call {
    if (!call) return;
    PARecentDetailOverlayV47 *overlay = [[PARecentDetailOverlayV47 alloc] initWithFrame:self.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [overlay configureCall:call];
    __weak typeof(self) weakSelf = self;
    __weak PARecentDetailOverlayV47 *weakOverlay = overlay;
    overlay.callHandler = ^(NSString *number) {
        if ([weakSelf respondsToSelector:@selector(callHandler)]) {
            void (^handler)(NSString *) = [(id)weakSelf callHandler];
            if (handler) handler(number);
        }
    };
    overlay.deleteHandler = ^(PARecentCall *selectedCall) {
        NSArray<PARecentCall *> *calls = objc_getAssociatedObject(weakSelf, PA47CallsKey);
        NSUInteger index = [calls indexOfObjectIdenticalTo:selectedCall];
        NSIndexPath *path = index == NSNotFound ? nil : [NSIndexPath indexPathForRow:index inSection:0];
        [weakSelf pa47_deleteCall:selectedCall indexPath:path completion:nil closeOverlay:YES];
        weakOverlay.userInteractionEnabled = NO;
    };
    overlay.alpha = 0;
    [self addSubview:overlay];
    [UIView animateWithDuration:0.2 animations:^{ overlay.alpha = 1; }];
}

- (void)pa47_deleteCall:(PARecentCall *)call
              indexPath:(NSIndexPath *)indexPath
             completion:(void (^)(BOOL))completion
           closeOverlay:(BOOL)closeOverlay {
    __weak typeof(self) weakSelf = self;
    [[PADataStore sharedStore] pa47_deleteRecentCall:call completion:^(BOOL success, NSString *message) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { if (completion) completion(NO); return; }
        if (!success) {
            PA47Toast(strongSelf, message, YES);
            if (completion) completion(NO);
            return;
        }

        NSMutableArray<PARecentCall *> *updated = [objc_getAssociatedObject(strongSelf, PA47CallsKey) mutableCopy] ?: [NSMutableArray array];
        NSUInteger index = [updated indexOfObjectIdenticalTo:call];
        if (index != NSNotFound) [updated removeObjectAtIndex:index];
        objc_setAssociatedObject(strongSelf, PA47CallsKey, [updated copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UITableView *table = objc_getAssociatedObject(strongSelf, PA47TableKey);
        UILabel *empty = objc_getAssociatedObject(strongSelf, PA47EmptyKey);
        empty.hidden = updated.count > 0;
        if (indexPath && indexPath.row < [table numberOfRowsInSection:0]) [table deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        else [table reloadData];
        PA47Toast(strongSelf, message, NO);
        if (closeOverlay) {
            for (UIView *view in strongSelf.subviews.copy) if ([view isKindOfClass:[PARecentDetailOverlayV47 class]]) [view removeFromSuperview];
        }
        if (completion) completion(YES);
    }];
}

@end

static void PA47Exchange(Class cls, SEL original, SEL replacement) {
    Method first = class_getInstanceMethod(cls, original);
    Method second = class_getInstanceMethod(cls, replacement);
    if (first && second) method_exchangeImplementations(first, second);
}

__attribute__((constructor)) static void PA47InstallRecents(void) {
    Class cls = NSClassFromString(@"PARecentsDashboardView");
    if (!cls) return;
    PA47Exchange(cls, @selector(initWithFrame:), @selector(pa47_initWithFrame:));
    PA47Exchange(cls, @selector(layoutSubviews), @selector(pa47_layoutSubviews));
    PA47Exchange(cls, @selector(refresh), @selector(pa47_refresh));
    PA47Exchange(cls, @selector(filterChanged), @selector(pa47_filterChanged));
    PA47Exchange(cls, @selector(tableView:numberOfRowsInSection:), @selector(pa47_tableView:numberOfRowsInSection:));
    PA47Exchange(cls, @selector(tableView:cellForRowAtIndexPath:), @selector(pa47_tableView:cellForRowAtIndexPath:));
    PA47Exchange(cls, @selector(tableView:didSelectRowAtIndexPath:), @selector(pa47_tableView:didSelectRowAtIndexPath:));
}
