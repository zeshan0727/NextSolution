#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

static CFStringRef const NQRConsoleDomain = CFSTR("com.nextsolution.nextquickreminder");
static CFStringRef const NQRConsolePreferencesChanged = CFSTR("com.nextsolution.nextquickreminder.preferences.changed");
static CFStringRef const NQRConsoleShowPanel = CFSTR("com.nextsolution.nextquickreminder.showpanel");
static CFStringRef const NQRConsoleAppCommand = CFSTR("com.nextsolution.nextquickreminder.appcommand");

static NSTimeInterval NQRConsoleLoadedTimestamp = 0;
static NSString *NQRConsoleLastCommandResult = @"No command received yet.";
static NSString *NQRConsoleAppContainerPath = @"";

static NSString *NQRConsoleLogPath(void) {
    return @"/var/mobile/Library/Logs/NextQuickReminder.log";
}

static NSString *NQRConsoleAppSupportDirectory(void) {
    @try {
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        SEL proxySelector = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if (!proxyClass || ![proxyClass respondsToSelector:proxySelector]) return nil;

        id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, proxySelector, @"com.nextsolution.nextreminder");
        SEL containerSelector = NSSelectorFromString(@"dataContainerURL");
        if (!proxy || ![proxy respondsToSelector:containerSelector]) return nil;

        NSURL *containerURL = ((id (*)(id, SEL))objc_msgSend)(proxy, containerSelector);
        if (![containerURL isKindOfClass:NSURL.class] || !containerURL.path.length) return nil;

        NQRConsoleAppContainerPath = containerURL.path;
        return [containerURL.path stringByAppendingPathComponent:@"Library/Application Support/NextReminder"];
    } @catch (NSException *exception) {
        NQRConsoleLastCommandResult = [NSString stringWithFormat:@"App container lookup failed: %@", exception.reason ?: exception.name];
        return nil;
    }
}

static NSString *NQRConsoleConfigurationPath(void) {
    NSString *directory = NQRConsoleAppSupportDirectory();
    return directory.length ? [directory stringByAppendingPathComponent:@"quick-tweak-config.json"] : nil;
}

static NSString *NQRConsoleSnapshotPath(void) {
    NSString *directory = NQRConsoleAppSupportDirectory();
    return directory.length ? [directory stringByAppendingPathComponent:@"quick-tweak-console.json"] : nil;
}

static NSDictionary *NQRConsoleReadDictionary(NSString *path) {
    if (!path.length) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

static BOOL NQRConsoleWriteDictionary(NSDictionary *dictionary, NSString *path) {
    if (!path.length || !dictionary) return NO;
    NSError *error = nil;
    NSString *directory = [path stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NQRConsoleLastCommandResult = [NSString stringWithFormat:@"Console directory failed: %@", error.localizedDescription ?: @"unknown error"];
        return NO;
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    if (!data || error) {
        NQRConsoleLastCommandResult = [NSString stringWithFormat:@"Console JSON failed: %@", error.localizedDescription ?: @"unknown error"];
        return NO;
    }
    return [data writeToFile:path options:NSDataWritingAtomic error:&error];
}

static id NQRConsolePreference(NSString *key) {
    CFPreferencesAppSynchronize(NQRConsoleDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, NQRConsoleDomain);
    return CFBridgingRelease(value);
}

static void NQRConsoleSetPreference(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, NQRConsoleDomain);
    CFPreferencesAppSynchronize(NQRConsoleDomain);
}

static NSString *NQRConsoleSelectedGesture(void) {
    NSString *gesture = NQRConsolePreference(@"gesture");
    NSArray *valid = @[@"off", @"statusbar", @"shake", @"volume"];
    return [gesture isKindOfClass:NSString.class] && [valid containsObject:gesture] ? gesture : @"statusbar";
}

static BOOL NQRConsoleDiagnosticLogging(void) {
    NSNumber *value = NQRConsolePreference(@"diagnosticLogging");
    return value ? value.boolValue : YES;
}

static NSString *NQRConsoleLogTail(void) {
    NSData *data = [NSData dataWithContentsOfFile:NQRConsoleLogPath()];
    if (!data.length) return @"No tweak log entries yet.";
    NSUInteger maximum = 96 * 1024;
    if (data.length > maximum) data = [data subdataWithRange:NSMakeRange(data.length - maximum, maximum)];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return text ?: @"The tweak log could not be decoded.";
}

static void NQRConsoleWriteSnapshot(void) {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSDictionary *snapshot = @{
        @"version": @"1.0.1",
        @"tweakLoaded": @YES,
        @"processName": NSProcessInfo.processInfo.processName ?: @"SpringBoard",
        @"loadedTimestamp": @(NQRConsoleLoadedTimestamp),
        @"lastHeartbeatTimestamp": @(now),
        @"selectedGesture": NQRConsoleSelectedGesture(),
        @"diagnosticLogging": @(NQRConsoleDiagnosticLogging()),
        @"lastCommandID": NQRConsolePreference(@"consoleLastCommandID") ?: @"",
        @"lastCommandResult": NQRConsoleLastCommandResult ?: @"",
        @"appContainerPath": NQRConsoleAppContainerPath ?: @"",
        @"snapshotPath": NQRConsoleSnapshotPath() ?: @"App container not resolved",
        @"logText": NQRConsoleLogTail(),
    };

    NSString *primary = NQRConsoleSnapshotPath();
    if (primary.length) NQRConsoleWriteDictionary(snapshot, primary);
    NQRConsoleWriteDictionary(snapshot, @"/var/mobile/Library/Logs/NextQuickReminder-runtime.json");
}

static void NQRConsoleApplyConfiguration(BOOL processCommand) {
    NSDictionary *configuration = NQRConsoleReadDictionary(NQRConsoleConfigurationPath());
    if (!configuration) {
        NQRConsoleLastCommandResult = @"Waiting for the in-app console configuration.";
        NQRConsoleWriteSnapshot();
        return;
    }

    NSString *gesture = configuration[@"gesture"];
    NSNumber *logging = configuration[@"diagnosticLogging"];
    NSArray *valid = @[@"off", @"statusbar", @"shake", @"volume"];
    if ([gesture isKindOfClass:NSString.class] && [valid containsObject:gesture]) NQRConsoleSetPreference(@"gesture", gesture);
    if ([logging isKindOfClass:NSNumber.class]) NQRConsoleSetPreference(@"diagnosticLogging", logging);

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NQRConsolePreferencesChanged,
        NULL,
        NULL,
        true
    );

    NSString *requestID = configuration[@"commandRequestID"];
    NSString *command = configuration[@"command"];
    NSString *processedID = NQRConsolePreference(@"consoleLastCommandID");
    if (processCommand && [requestID isKindOfClass:NSString.class] && requestID.length && ![requestID isEqualToString:processedID]) {
        NQRConsoleSetPreference(@"consoleLastCommandID", requestID);

        if ([command isEqualToString:@"showPanel"]) {
            NQRConsoleLastCommandResult = @"Test Panel command received by SpringBoard.";
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                NQRConsoleShowPanel,
                NULL,
                NULL,
                true
            );
        } else if ([command isEqualToString:@"clearLogs"]) {
            [[NSData data] writeToFile:NQRConsoleLogPath() atomically:YES];
            NQRConsoleLastCommandResult = @"Tweak log cleared.";
        } else if ([command isEqualToString:@"reload"]) {
            NQRConsoleLastCommandResult = [NSString stringWithFormat:@"Gesture configuration applied: %@.", NQRConsoleSelectedGesture()];
        } else {
            NQRConsoleLastCommandResult = [NSString stringWithFormat:@"Unknown command: %@", command ?: @"missing"];
        }
    } else if (!processCommand) {
        NQRConsoleLastCommandResult = [NSString stringWithFormat:@"Configuration synchronized: %@.", NQRConsoleSelectedGesture()];
    }

    NSLog(@"[NextQuickReminderConsole] %@", NQRConsoleLastCommandResult);
    NQRConsoleWriteSnapshot();
}

static void NQRConsoleCommandChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NQRConsoleApplyConfiguration(YES);
    });
}

__attribute__((constructor))
static void NQRConsoleInitialize(void) {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if (![bundleID isEqualToString:@"com.apple.springboard"] && ![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;

        NQRConsoleLoadedTimestamp = NSDate.date.timeIntervalSince1970;
        NQRConsoleLastCommandResult = @"Console bridge loaded in SpringBoard.";
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            NQRConsoleCommandChanged,
            NQRConsoleAppCommand,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NQRConsoleApplyConfiguration(YES);
        });

        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(__unused NSTimer *timer) {
            NQRConsoleWriteSnapshot();
        }];

        NSLog(@"[NextQuickReminderConsole] 1.0.1 bridge initialized");
    }
}
