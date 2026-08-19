#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#import <objc/message.h>

static CFStringRef const NQR104Domain = CFSTR("com.nextsolution.nextquickreminder");
static CFStringRef const NQR104AppDomain = CFSTR("com.nextsolution.nextreminder");
static CFStringRef const NQR104ShowPanelNotification = CFSTR("com.nextsolution.nextquickreminder.showpanel");
static dispatch_queue_t NQR104StorageQueue;
static const void *NQR104LockGestureKey = &NQR104LockGestureKey;
static const void *NQR104SavingKey = &NQR104SavingKey;

@interface NQRQuickPanelController : UIViewController
@property(nonatomic,strong) UITextField *titleField;
@property(nonatomic,strong) UITextView *notesView;
@property(nonatomic,strong) UIDatePicker *datePicker;
@property(nonatomic,strong) UISwitch *notificationSwitch;
@property(nonatomic,strong) UISwitch *emailSwitch;
@property(nonatomic,copy) NSString *repeatMode;
- (void)showStatus:(NSString *)message error:(BOOL)isError;
- (void)cancelTapped;
- (void)scheduleTapped;
@end

static id NQR104Preference(NSString *key) {
    CFPreferencesAppSynchronize(NQR104Domain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, NQR104Domain);
    return CFBridgingRelease(value);
}

static BOOL NQR104LockScreenEnabled(void) {
    id value = NQR104Preference(@"allowLockScreen");
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}

static BOOL NQR104StatusGestureSelected(void) {
    id value = NQR104Preference(@"gesture");
    return [value isKindOfClass:NSString.class] && [value isEqualToString:@"statusbar"];
}

static void NQR104SetPreference(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, value ? (__bridge CFPropertyListRef)value : NULL, NQR104Domain);
    CFPreferencesAppSynchronize(NQR104Domain);
}

static NSString *NQR104AppContainerPath(void) {
    @try {
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        SEL proxySelector = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if (!proxyClass || ![proxyClass respondsToSelector:proxySelector]) return nil;
        id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, proxySelector, @"com.nextsolution.nextreminder");
        SEL containerSelector = NSSelectorFromString(@"dataContainerURL");
        if (!proxy || ![proxy respondsToSelector:containerSelector]) return nil;
        NSURL *url = ((id (*)(id, SEL))objc_msgSend)(proxy, containerSelector);
        return [url isKindOfClass:NSURL.class] ? url.path : nil;
    } @catch (NSException *exception) {
        NSLog(@"[NextQuickReminder104] Container lookup failed: %@", exception.reason ?: exception.name);
        return nil;
    }
}

static NSString *NQR104DatabasePath(void) {
    NSString *container = NQR104AppContainerPath();
    if (!container.length) return nil;
    return [container stringByAppendingPathComponent:@"Library/Application Support/NextReminder/NextReminderDatabase.json"];
}

static NSString *NQR104ISODate(NSDate *date) {
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSISO8601DateFormatter new];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    });
    return [formatter stringFromDate:date ?: NSDate.date];
}

static NSArray *NQR104DefaultCategories(void) {
    return @[
        @{ @"id": @"A1000000-0000-0000-0000-000000000001", @"name": @"Personal", @"icon": @"person.fill", @"colorHex": @"32C76A", @"isProtected": @YES },
        @{ @"id": @"A1000000-0000-0000-0000-000000000002", @"name": @"General", @"icon": @"square.grid.2x2.fill", @"colorHex": @"FF8A00", @"isProtected": @YES },
    ];
}

static NSMutableDictionary *NQR104LoadDatabase(NSString *path, NSError **error) {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data.length) {
        if (error) *error = nil;
        return [@{ @"reminders": [NSMutableArray array], @"categories": [NQR104DefaultCategories() mutableCopy] } mutableCopy];
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:error];
    if (![object isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *database = [object mutableCopy];
    database[@"reminders"] = [database[@"reminders"] isKindOfClass:NSArray.class] ? [database[@"reminders"] mutableCopy] : [NSMutableArray array];
    if (![database[@"categories"] isKindOfClass:NSArray.class] || [database[@"categories"] count] == 0) {
        database[@"categories"] = [NQR104DefaultCategories() mutableCopy];
    }
    return database;
}

static BOOL NQR104WriteDatabase(NSDictionary *database, NSString *path, NSError **error) {
    NSString *directory = [path stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:database options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
    return data.length && [data writeToFile:path options:NSDataWritingAtomic error:error];
}

static NSMutableDictionary *NQR104ReadAppDataMap(NSString *key) {
    CFPreferencesAppSynchronize(NQR104AppDomain);
    CFPropertyListRef raw = CFPreferencesCopyAppValue((__bridge CFStringRef)key, NQR104AppDomain);
    id value = CFBridgingRelease(raw);
    if (![value isKindOfClass:NSData.class]) return [NSMutableDictionary dictionary];
    id object = [NSJSONSerialization JSONObjectWithData:value options:NSJSONReadingMutableContainers error:nil];
    return [object isKindOfClass:NSDictionary.class] ? [object mutableCopy] : [NSMutableDictionary dictionary];
}

static void NQR104WriteAppDataMap(NSDictionary *map, NSString *key) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:map ?: @{} options:0 error:nil];
    if (!data.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFDataRef)data, NQR104AppDomain);
    CFPreferencesAppSynchronize(NQR104AppDomain);
}

static void NQR104SaveRepeatMetadata(NSString *reminderID, NSString *mode) {
    NSString *value = mode.lowercaseString ?: @"never";
    if ([value isEqualToString:@"daily"]) {
        NSMutableDictionary *days = NQR104ReadAppDataMap(@"NextReminder.SelectedDaySchedules.v1");
        days[reminderID] = @[ @1, @2, @3, @4, @5, @6, @7 ];
        NQR104WriteAppDataMap(days, @"NextReminder.SelectedDaySchedules.v1");
    } else if ([value hasPrefix:@"hourly"] && value.length > 6) {
        NSInteger hours = [[value substringFromIndex:6] integerValue];
        if (hours >= 1 && hours <= 4) {
            NSMutableDictionary *hourly = NQR104ReadAppDataMap(@"NextReminder.HourlyRepeatSchedules.v1");
            hourly[reminderID] = @(hours);
            NQR104WriteAppDataMap(hourly, @"NextReminder.HourlyRepeatSchedules.v1");
        }
    }
}

static NSString *NQR104RepeatRule(NSString *mode) {
    NSString *value = mode.lowercaseString ?: @"never";
    return [@[ @"daily", @"weekly", @"monthly", @"yearly" ] containsObject:value] ? value : @"never";
}

static UNUserNotificationCenter *NQR104NotificationCenter(void) {
    Class centerClass = NSClassFromString(@"UNUserNotificationCenter");
    if (!centerClass) return nil;
    for (NSString *name in @[ @"initWithBundleIdentifier:", @"_initWithBundleIdentifier:" ]) {
        SEL selector = NSSelectorFromString(name);
        id object = [centerClass alloc];
        if ([object respondsToSelector:selector]) {
            id center = ((id (*)(id, SEL, id))objc_msgSend)(object, selector, @"com.nextsolution.nextreminder");
            if ([center isKindOfClass:centerClass]) return center;
        }
    }
    for (NSString *name in @[ @"notificationCenterForBundleIdentifier:", @"_notificationCenterForBundleIdentifier:" ]) {
        SEL selector = NSSelectorFromString(name);
        if ([centerClass respondsToSelector:selector]) {
            id center = ((id (*)(id, SEL, id))objc_msgSend)(centerClass, selector, @"com.nextsolution.nextreminder");
            if ([center isKindOfClass:centerClass]) return center;
        }
    }
    return nil;
}

static void NQR104ScheduleNotification(NSDictionary *payload, NSString *reminderID, void (^completion)(NSString *warning)) {
    if (![payload[@"notificationsEnabled"] boolValue]) {
        if (completion) completion(nil);
        return;
    }
    UNUserNotificationCenter *center = NQR104NotificationCenter();
    if (!center) {
        if (completion) completion(@"Reminder saved. Open Next Reminder once to activate its notification.");
        return;
    }
    NSDate *dueDate = [NSDate dateWithTimeIntervalSince1970:[payload[@"dueTimestamp"] doubleValue]];
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = payload[@"title"] ?: @"Reminder";
    content.subtitle = @"Reminder time";
    NSString *notes = payload[@"notes"] ?: @"";
    content.body = notes.length ? notes : @"General • Medium priority";
    content.sound = UNNotificationSound.defaultSound;
    content.categoryIdentifier = @"NEXT_REMINDER_CATEGORY";
    content.threadIdentifier = @"General";
    content.userInfo = @{ @"reminderID": reminderID };
    NSDateComponents *parts = [NSCalendar.currentCalendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond) fromDate:dueDate];
    UNCalendarNotificationTrigger *trigger = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:parts repeats:NO];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[NSString stringWithFormat:@"%@-alert-0", reminderID] content:content trigger:trigger];
    [center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSLog(@"[NextQuickReminder104] Notification scheduling failed: %@", error.localizedDescription);
                if (completion) completion(@"Reminder saved. Its notification will synchronize when Next Reminder is opened.");
            } else if (completion) {
                completion(nil);
            }
        });
    }];
}

static void NQR104SaveReminder(NSDictionary *payload, void (^completion)(BOOL success, NSString *message)) {
    dispatch_async(NQR104StorageQueue ?: dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            NSString *databasePath = NQR104DatabasePath();
            if (!databasePath.length) {
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, @"Next Reminder app container could not be found."); });
                return;
            }
            NSError *error = nil;
            NSMutableDictionary *database = NQR104LoadDatabase(databasePath, &error);
            if (!database || error) {
                NSString *message = [NSString stringWithFormat:@"Could not read reminders: %@", error.localizedDescription ?: @"unknown error"];
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, message); });
                return;
            }
            NSString *reminderID = NSUUID.UUID.UUIDString;
            NSDate *now = NSDate.date;
            NSString *repeatMode = payload[@"repeatMode"] ?: @"never";
            NSDictionary *reminder = @{
                @"id": reminderID,
                @"title": payload[@"title"] ?: @"",
                @"notes": payload[@"notes"] ?: @"",
                @"dueDate": NQR104ISODate([NSDate dateWithTimeIntervalSince1970:[payload[@"dueTimestamp"] doubleValue]]),
                @"priority": @"medium",
                @"categoryID": @"A1000000-0000-0000-0000-000000000002",
                @"repeatRule": NQR104RepeatRule(repeatMode),
                @"alertOffsets": [payload[@"notificationsEnabled"] boolValue] ? @[ @0 ] : @[],
                @"notificationsEnabled": @([payload[@"notificationsEnabled"] boolValue]),
                @"emailWhenDue": @([payload[@"emailWhenDue"] boolValue]),
                @"createdAt": NQR104ISODate(now),
                @"updatedAt": NQR104ISODate(now),
                @"history": @[],
            };
            NSMutableArray *reminders = [database[@"reminders"] mutableCopy] ?: [NSMutableArray array];
            [reminders addObject:reminder];
            database[@"reminders"] = reminders;
            if (!NQR104WriteDatabase(database, databasePath, &error)) {
                NSString *message = [NSString stringWithFormat:@"Could not save reminder: %@", error.localizedDescription ?: @"unknown error"];
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, message); });
                return;
            }
            NQR104SaveRepeatMetadata(reminderID, repeatMode);
            NQR104SetPreference(@"draft", nil);
            NSLog(@"[NextQuickReminder104] Saved reminder %@ directly to %@", reminderID, databasePath);
            dispatch_async(dispatch_get_main_queue(), ^{
                NQR104ScheduleNotification(payload, reminderID, ^(NSString *warning) {
                    if (completion) completion(YES, warning.length ? warning : @"Reminder scheduled in background.");
                });
            });
        }
    });
}

@implementation NQRQuickPanelController (NQR104BackgroundSchedule)
- (void)nqr104_scheduleTapped {
    if ([objc_getAssociatedObject(self, NQR104SavingKey) boolValue]) return;
    NSString *title = [self.titleField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!title.length) {
        [self showStatus:@"Enter a reminder title." error:YES];
        [self.titleField becomeFirstResponder];
        return;
    }
    if ([self.datePicker.date timeIntervalSinceNow] <= 3) {
        [self showStatus:@"Choose a future reminder date and time." error:YES];
        return;
    }
    NSDictionary *payload = @{
        @"title": title,
        @"notes": self.notesView.text ?: @"",
        @"dueTimestamp": @(self.datePicker.date.timeIntervalSince1970),
        @"notificationsEnabled": @(self.notificationSwitch.isOn),
        @"emailWhenDue": @(self.emailSwitch.isOn),
        @"repeatMode": self.repeatMode ?: @"never",
    };
    objc_setAssociatedObject(self, NQR104SavingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self.view endEditing:YES];
    [self showStatus:@"Saving in background…" error:NO];
    __weak typeof(self) weakSelf = self;
    NQR104SaveReminder(payload, ^(BOOL success, NSString *message) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        objc_setAssociatedObject(self, NQR104SavingKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self showStatus:message error:!success];
        UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
        [feedback notificationOccurred:success ? UINotificationFeedbackTypeSuccess : UINotificationFeedbackTypeError];
        if (success) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self cancelTapped]; });
        }
    });
}
@end

@interface UIViewController (NQR104LockAction)
- (void)nqr104_lockClockDoubleTap:(UITapGestureRecognizer *)recognizer;
@end

@implementation UIViewController (NQR104LockAction)
- (void)nqr104_lockClockDoubleTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateRecognized || !NQR104LockScreenEnabled() || !NQR104StatusGestureSelected()) return;
    if ([NSStringFromClass(self.class) isEqualToString:@"CSCoverSheetViewController"]) {
        CGPoint point = [recognizer locationInView:recognizer.view];
        CGFloat width = CGRectGetWidth(recognizer.view.bounds);
        CGFloat maximumY = MIN(300.0, CGRectGetHeight(recognizer.view.bounds) * 0.42);
        if (point.y < 35.0 || point.y > maximumY || point.x < width * 0.12 || point.x > width * 0.88) return;
    }
    NSLog(@"[NextQuickReminder104] Lock Screen clock double-tap recognized");
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), NQR104ShowPanelNotification, NULL, NULL, true);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if ([NSStringFromClass(window.rootViewController.class) isEqualToString:@"NQRQuickPanelController"]) window.windowLevel = UIWindowLevelAlert + 5000;
        }
    });
}
@end

static void NQR104AttachLockGesture(UIViewController *controller) {
    if (!controller.view || objc_getAssociatedObject(controller, NQR104LockGestureKey)) return;
    UITapGestureRecognizer *recognizer = [[UITapGestureRecognizer alloc] initWithTarget:controller action:@selector(nqr104_lockClockDoubleTap:)];
    recognizer.numberOfTapsRequired = 2;
    recognizer.cancelsTouchesInView = NO;
    recognizer.delaysTouchesBegan = NO;
    recognizer.delaysTouchesEnded = NO;
    [controller.view addGestureRecognizer:recognizer];
    objc_setAssociatedObject(controller, NQR104LockGestureKey, recognizer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook SBFLockScreenDateViewController
- (void)viewDidLoad { %orig; NQR104AttachLockGesture((UIViewController *)self); }
- (void)viewDidAppear:(BOOL)animated { %orig(animated); NQR104AttachLockGesture((UIViewController *)self); }
%end

%hook CSCoverSheetViewController
- (void)viewDidLoad { %orig; NQR104AttachLockGesture((UIViewController *)self); }
- (void)viewDidAppear:(BOOL)animated { %orig(animated); NQR104AttachLockGesture((UIViewController *)self); }
%end

__attribute__((constructor))
static void NQR104Initialize(void) {
    @autoreleasepool {
        NSString *process = NSProcessInfo.processInfo.processName;
        if (![process isEqualToString:@"SpringBoard"] && ![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        NQR104StorageQueue = dispatch_queue_create("com.nextsolution.nextquickreminder.background-storage", DISPATCH_QUEUE_SERIAL);
        Class panelClass = NSClassFromString(@"NQRQuickPanelController");
        Method original = class_getInstanceMethod(panelClass, @selector(scheduleTapped));
        Method replacement = class_getInstanceMethod(panelClass, @selector(nqr104_scheduleTapped));
        if (original && replacement) {
            method_exchangeImplementations(original, replacement);
            NSLog(@"[NextQuickReminder104] Background Schedule installed; app will no longer open");
        } else {
            NSLog(@"[NextQuickReminder104] ERROR: Could not install Background Schedule");
        }
    }
}
