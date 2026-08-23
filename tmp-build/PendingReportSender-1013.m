#import "PendingReportSender.h"
#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import <Security/Security.h>
#import <objc/message.h>

static CFStringRef const NQRReportAppDomain = CFSTR("com.nextsolution.nextreminder");
static NSString * const NQRReportSettingsKey = @"NextReminder.EmailAutomationSettings.v1";
static NSString * const NQRReportEndpointKey = @"NextReminder.AutomationCloudEndpoint";
static NSString * const NQRReportBridgeAPIKeyKey = @"NextReminder.QuickReportBridgeAPIKey.v1";
static NSString * const NQRReportKeychainService = @"com.nextsolution.nextreminder.automations";
static NSString * const NQRReportKeychainAccount = @"scheduler-api-key";
static BOOL NQRReportSendInFlight = NO;

static id NQRReportCopyAppPreference(NSString *key) {
    CFPreferencesAppSynchronize(NQRReportAppDomain);
    CFPropertyListRef raw = CFPreferencesCopyAppValue((__bridge CFStringRef)key, NQRReportAppDomain);
    return CFBridgingRelease(raw);
}

static NSString *NQRReportAppContainerPath(void) {
    @try {
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        SEL proxySelector = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if (!proxyClass || ![proxyClass respondsToSelector:proxySelector]) return nil;
        id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, proxySelector, @"com.nextsolution.nextreminder");
        SEL containerSelector = NSSelectorFromString(@"dataContainerURL");
        if (!proxy || ![proxy respondsToSelector:containerSelector]) return nil;
        NSURL *url = ((id (*)(id, SEL))objc_msgSend)(proxy, containerSelector);
        return [url isKindOfClass:NSURL.class] ? url.path : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *NQRReportDatabasePath(void) {
    NSString *container = NQRReportAppContainerPath();
    if (!container.length) return nil;
    return [container stringByAppendingPathComponent:@"Library/Application Support/NextReminder/NextReminderDatabase.json"];
}

static UNUserNotificationCenter *NQRReportNotificationCenter(void) {
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

static void NQRReportNotify(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UNUserNotificationCenter *center = NQRReportNotificationCenter();
        if (!center) {
            NSLog(@"[NextQuickReminder] Report notification unavailable: %@ — %@", title, message);
            return;
        }
        UNMutableNotificationContent *content = [UNMutableNotificationContent new];
        content.title = title ?: @"Next Reminder";
        content.body = message ?: @"";
        content.sound = UNNotificationSound.defaultSound;
        content.threadIdentifier = @"next-reminder-report";
        NSString *identifier = [NSString stringWithFormat:@"next-report-%@", NSUUID.UUID.UUIDString];
        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:nil];
        [center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
            if (error) NSLog(@"[NextQuickReminder] Could not post report notification: %@", error.localizedDescription);
        }];
    });
}

static NSDictionary *NQRReportEmailSettings(void) {
    id raw = NQRReportCopyAppPreference(NQRReportSettingsKey);
    if (![raw isKindOfClass:NSData.class]) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil];
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

static NSString *NQRReportSchedulerAPIKey(void) {
    id bridged = NQRReportCopyAppPreference(NQRReportBridgeAPIKeyKey);
    if ([bridged isKindOfClass:NSString.class] && [bridged length] > 0) return bridged;

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: NQRReportKeychainService,
        (__bridge id)kSecAttrAccount: NQRReportKeychainAccount,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) return nil;
    NSData *data = CFBridgingRelease(result);
    if (![data isKindOfClass:NSData.class]) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static NSDate *NQRReportParseISODate(id value) {
    if (![value isKindOfClass:NSString.class] || ![value length]) return nil;
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSISO8601DateFormatter new];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    });
    NSDate *date = [formatter dateFromString:value];
    if (date) return date;
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    return [formatter dateFromString:value];
}

static NSString *NQRReportISODate(NSDate *date) {
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSISO8601DateFormatter new];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    });
    return [formatter stringFromDate:date ?: NSDate.date];
}

static NSArray<NSDictionary *> *NQRReportPendingReminders(NSError **error) {
    NSString *path = NQRReportDatabasePath();
    if (!path.length) {
        if (error) *error = [NSError errorWithDomain:@"NextQuickReminder.Report" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Next Reminder data container could not be found."}];
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data.length) return @[];
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![object isKindOfClass:NSDictionary.class]) return nil;
    NSArray *all = [object[@"reminders"] isKindOfClass:NSArray.class] ? object[@"reminders"] : @[];
    NSMutableArray *pending = [NSMutableArray array];
    for (id candidate in all) {
        if (![candidate isKindOfClass:NSDictionary.class]) continue;
        id completed = candidate[@"completedAt"];
        if (completed && completed != NSNull.null) continue;
        [pending addObject:candidate];
    }
    [pending sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *ad = [a[@"deadlineDate"] isKindOfClass:NSString.class] ? a[@"deadlineDate"] : a[@"dueDate"];
        NSString *bd = [b[@"deadlineDate"] isKindOfClass:NSString.class] ? b[@"deadlineDate"] : b[@"dueDate"];
        return [(ad ?: @"") compare:(bd ?: @"")];
    }];
    return pending;
}

static NSString *NQRReportBody(NSArray<NSDictionary *> *reminders) {
    NSDate *now = NSDate.date;
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;

    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithArray:@[
        @"Next Reminder — Pending Reminders Report",
        [NSString stringWithFormat:@"Generated: %@", [formatter stringFromDate:now]],
        [NSString stringWithFormat:@"Total pending: %lu", (unsigned long)reminders.count],
        @""
    ]];

    [reminders enumerateObjectsUsingBlock:^(NSDictionary *reminder, NSUInteger index, BOOL *stop) {
        NSString *title = [reminder[@"title"] isKindOfClass:NSString.class] ? reminder[@"title"] : @"Untitled Reminder";
        NSString *notes = [reminder[@"notes"] isKindOfClass:NSString.class] ? reminder[@"notes"] : @"";
        NSString *priority = [reminder[@"priority"] isKindOfClass:NSString.class] ? reminder[@"priority"] : @"medium";
        NSDate *due = NQRReportParseISODate(reminder[@"dueDate"]);
        NSDate *deadline = NQRReportParseISODate(reminder[@"deadlineDate"]);
        BOOL overdue = due && [due compare:now] != NSOrderedDescending;
        [lines addObject:[NSString stringWithFormat:@"%lu. %@%@", (unsigned long)(index + 1), title, overdue ? @" • OVERDUE" : @""]];
        [lines addObject:[NSString stringWithFormat:@"   Due: %@", due ? [formatter stringFromDate:due] : @"Not set"]];
        if (deadline) [lines addObject:[NSString stringWithFormat:@"   Deadline: %@", [formatter stringFromDate:deadline]]];
        [lines addObject:[NSString stringWithFormat:@"   Priority: %@", priority.capitalizedString]];
        NSString *trimmed = [notes stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length) [lines addObject:[NSString stringWithFormat:@"   Notes: %@", trimmed]];
        [lines addObject:@""];
    }];
    [lines addObject:@"Sent from Next Reminder"];
    return [lines componentsJoinedByString:@"\n"];
}

static NSString *NQRReportProviderForMethod(NSString *method) {
    if ([method isEqualToString:@"gmailAutomatic"]) return @"gmail";
    if ([method isEqualToString:@"iCloudAutomatic"]) return @"icloud";
    if ([method isEqualToString:@"smtpAutomatic"]) return @"smtp";
    return nil;
}

static NSString *NQRReportServerMessage(NSData *data, NSInteger statusCode) {
    id object = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSString *message = [object isKindOfClass:NSDictionary.class] && [object[@"message"] isKindOfClass:NSString.class] ? object[@"message"] : nil;
    if (!message.length && data.length) {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        message = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    return message.length ? message : [NSString stringWithFormat:@"Email scheduler request failed (%ld).", (long)statusCode];
}

void NQRSendPendingReportInBackground(void) {
    @synchronized (NSProcessInfo.processInfo) {
        if (NQRReportSendInFlight) {
            NQRReportNotify(@"Report already sending", @"Please wait for the current send result.");
            return;
        }
        NQRReportSendInFlight = YES;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        void (^finish)(BOOL, NSString *, NSString *) = ^(BOOL success, NSString *title, NSString *message) {
            @synchronized (NSProcessInfo.processInfo) { NQRReportSendInFlight = NO; }
            NQRReportNotify(title, message);
            NSLog(@"[NextQuickReminder] Background report %@: %@", success ? @"success" : @"failure", message);
        };

        NSDictionary *settings = NQRReportEmailSettings();
        if (!settings) {
            finish(NO, @"Report failed", @"Email Reminder Automation settings were not found. Open Next Reminder and save Email Automation settings once.");
            return;
        }
        if (![settings[@"enabled"] boolValue]) {
            finish(NO, @"Report failed", @"Email Reminder Automations are disabled in Next Reminder.");
            return;
        }

        NSString *recipient = [settings[@"recipient"] isKindOfClass:NSString.class] ? [settings[@"recipient"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
        if (!recipient.length || [recipient rangeOfString:@"@"].location == NSNotFound) {
            finish(NO, @"Report failed", @"A valid fixed recipient email is not configured in Next Reminder.");
            return;
        }

        NSString *method = [settings[@"deliveryMethod"] isKindOfClass:NSString.class] ? settings[@"deliveryMethod"] : @"";
        NSString *provider = NQRReportProviderForMethod(method);
        if (!provider) {
            finish(NO, @"Report failed", @"Background Send requires Gmail, iCloud Mail, or SMTP Automatic. Apple Mail Assisted cannot send while the app stays closed.");
            return;
        }

        NSString *connectorID = [settings[@"remoteConnectorID"] isKindOfClass:NSString.class] ? settings[@"remoteConnectorID"] : @"";
        if (!connectorID.length) {
            finish(NO, @"Report failed", @"The automatic email connector is not configured. Reconnect the sender in Next Reminder.");
            return;
        }

        id endpointValue = NQRReportCopyAppPreference(NQRReportEndpointKey);
        NSString *endpoint = [endpointValue isKindOfClass:NSString.class] ? endpointValue : nil;
        NSString *apiKey = NQRReportSchedulerAPIKey();
        if (!endpoint.length || !apiKey.length) {
            finish(NO, @"Report failed", @"Background sender is not initialized. Open Next Reminder once after this update, then Send Report will work without opening the app.");
            return;
        }

        NSError *loadError = nil;
        NSArray<NSDictionary *> *pending = NQRReportPendingReminders(&loadError);
        if (!pending) {
            finish(NO, @"Report failed", loadError.localizedDescription ?: @"Pending reminders could not be loaded.");
            return;
        }
        if (pending.count == 0) {
            finish(NO, @"Nothing to send", @"There are no pending reminders.");
            return;
        }

        NSString *subject = [NSString stringWithFormat:@"Pending Reminders Report — %lu", (unsigned long)pending.count];
        NSString *body = NQRReportBody(pending);
        NQRReportNotify(@"Sending report…", [NSString stringWithFormat:@"%lu pending reminders → %@", (unsigned long)pending.count, recipient]);

        NSString *normalized = [endpoint hasSuffix:@"/"] ? endpoint : [endpoint stringByAppendingString:@"/"];
        NSURL *baseURL = [NSURL URLWithString:normalized];
        NSURL *url = baseURL ? [NSURL URLWithString:@"v1/email-reminders/test" relativeToURL:baseURL].absoluteURL : nil;
        if (!url || ![[url.scheme lowercaseString] isEqualToString:@"https"]) {
            finish(NO, @"Report failed", @"The configured automation scheduler URL is invalid.");
            return;
        }

        NSDate *now = NSDate.date;
        NSDictionary *payload = @{
            @"localID": NSUUID.UUID.UUIDString,
            @"recipient": recipient,
            @"provider": provider,
            @"remoteConnectorID": connectorID,
            @"senderLabel": [settings[@"senderLabel"] isKindOfClass:NSString.class] ? settings[@"senderLabel"] : @"",
            @"subject": subject,
            @"body": body,
            @"scheduledAt": NQRReportISODate(now),
            @"timeZone": NSTimeZone.localTimeZone.name ?: @"UTC",
            @"reminderTitle": subject,
            @"reminderTime": NQRReportISODate(now),
            @"deadline": NSNull.null,
            @"testOnly": @YES
        };
        NSError *jsonError = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
        if (!json.length) {
            finish(NO, @"Report failed", jsonError.localizedDescription ?: @"Could not prepare the report email.");
            return;
        }

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";
        request.timeoutInterval = 30.0;
        request.HTTPBody = json;
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];
        [request setValue:@"NextQuickReminder-iOS/1.0.13" forHTTPHeaderField:@"User-Agent"];

        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block NSData *responseData = nil;
        __block NSURLResponse *urlResponse = nil;
        __block NSError *networkError = nil;
        NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            responseData = data;
            urlResponse = response;
            networkError = error;
            dispatch_semaphore_signal(semaphore);
        }];
        [task resume];
        long timedOut = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(35.0 * NSEC_PER_SEC)));
        if (timedOut != 0) {
            [task cancel];
            finish(NO, @"Report failed", @"The email server timed out. Check your internet connection and try again.");
            return;
        }
        if (networkError) {
            finish(NO, @"Report failed", networkError.localizedDescription ?: @"Network error while sending the report.");
            return;
        }

        NSHTTPURLResponse *http = [urlResponse isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)urlResponse : nil;
        if (!http) {
            finish(NO, @"Report failed", @"The email scheduler returned an invalid response.");
            return;
        }
        if (http.statusCode < 200 || http.statusCode >= 300) {
            NSString *serverMessage = NQRReportServerMessage(responseData, http.statusCode);
            finish(NO, @"Report failed", [NSString stringWithFormat:@"%@ Recipient: %@", serverMessage, recipient]);
            return;
        }

        finish(YES, @"Report sent", [NSString stringWithFormat:@"%lu pending reminders sent successfully to %@.", (unsigned long)pending.count, recipient]);
    });
}
