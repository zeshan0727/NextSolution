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

static NSString *NQRConsoleAppSupportDirectory(void) {
    @try {
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        SEL proxySelector = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if (!proxyClass || ![proxyClass respondsToSelector:proxySelector]) return nil;

        id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, proxySelector, @"com.nextsolution.nextreminder");
        SEL containerSelector = NSSelectorFromString(@"dataContainerURL");
        if (!proxy || ![proxy respondsToSelector:containerSelector]) return nil;

        NSURL *containerURL = ((id (*)(id, SEL))objc_msgSend)(proxy, containerSelector);
        NSString *path = [containerURL isKindOfClass:NSURL.class] ? containerURL.path : nil;
        if (!path.length) return nil;

        NQRConsoleAppContainerPath = [path copy];
        return [path stringByAppendingPathComponent:@"Library/Application Support/NextReminder"];
    } @catch (NSException *exception) {
        NSString *reason = exception.reason ?: exception.name ?: @"unknown exception";
        NQRConsoleLastCommandResult = [NSString stringWithFormat:@"App container lookup failed: %@", reason];
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
    @try {
        NSError *error = nil;
        NSString *directory = [path stringByDeletingLastPathComponent];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) return NO;
        NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
        if (!data.length || error) return NO;
        return [data writeToFile:path options:NSDataWritingAtomic error:&error];
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static id NQRConsolePreference(NSString *key) {
    if (!key.length) return nil;
    CFPreferencesAppSynchronize(NQRConsoleDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, NQRConsoleDomain);
    return CFBridgingRelease(value);
}

static void NQRConsoleSetPreference(NSString *key, id value) {
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, value ? (__bridge CFPropertyListRef)value : NULL, NQRConsoleDomain);
    CFPreferencesAppSynchronize(NQRConsoleDomain);
}

static NSString *NQRConsoleSelectedGesture(void) {
    id value = NQRConsolePreference(@"gesture");
    if (![value isKindOfClass:NSString.class]) return @"off";
    NSString *gesture = value;
    if ([gesture isEqualToString:@"statusbar"] || [gesture isEqualToString:@"shake"] || [gesture isEqualToString:@"volume"] || [gesture isEqualToString:@"off"]) return gesture;
    return @"off";
}

static BOOL NQRConsoleDiagnosticLogging(void) {
    id value = NQRConsolePreference(@"diagnosticLogging");
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : YES;
}

static NSMutableDictionary *NQRConsoleSnapshotDictionary(void) {
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    if (!snapshot) return nil;

    NSString *processName = NSProcessInfo.processInfo.processName;
    NSString *gesture = NQRConsoleSelectedGesture();
    id commandID = NQRConsolePreference(@"consoleLastCommandID");
    NSString *snapshotPath = NQRConsoleSnapshotPath();

    snapshot[@"version"] = @"1.0.2";
    snapshot[@"tweakLoaded"] = @YES;
    snapshot[@"processName"] = processName.length ? processName : @"SpringBoard";
    snapshot[@"loadedTimestamp"] = @(NQRConsoleLoadedTimestamp);
    snapshot[@"lastHeartbeatTimestamp"] = @(NSDate.date.timeIntervalSince1970);
    snapshot[@"selectedGesture"] = gesture.length ? gesture : @"off";
    snapshot[@"diagnosticLogging"] = @(NQRConsoleDiagnosticLogging());
    snapshot[@"lastCommandID"] = [commandID isKindOfClass:NSString.class] ? commandID : @"";
    snapshot[@"lastCommandResult"] = NQRConsoleLastCommandResult.length ? NQRConsoleLastCommandResult : @"";
    snapshot[@"appContainerPath"] = NQRConsoleAppContainerPath.length ? NQRConsoleAppContainerPath : @"";
    snapshot[@"snapshotPath"] = snapshotPath.length ? snapshotPath : @"App container not resolved";
    snapshot[@"logText"] = @"Safe startup mode active. Detailed file logging is disabled until the tweak is confirmed stable.";
    return snapshot;
}

static void NQRConsoleWriteSnapshot(void) {
    NSMutableDictionary *snapshot = NQRConsoleSnapshotDictionary();
    if (!snapshot) return;
    NSString *path = NQRConsoleSnapshotPath();
    if (path.length) NQRConsoleWriteDictionary(snapshot, path);
}

static void NQRConsoleApplyConfiguration(BOOL processCommand) {
    NSDictionary *configuration = NQRConsoleReadDictionary(NQRConsoleConfigurationPath());
    if (![configuration isKindOfClass:NSDictionary.class]) {
        NQRConsoleLastCommandResult = @"Tweak loaded in safe mode. Open the in-app console and apply a gesture.";
        NQRConsoleWriteSnapshot();
        return;
    }

    id gestureValue = configuration[@"gesture"];
    if ([gestureValue isKindOfClass:NSString.class]) {
        NSString *gesture = gestureValue;
        if ([gesture isEqualToString:@"off"] || [gesture isEqualToString:@"statusbar"] || [gesture isEqualToString:@"shake"] || [gesture isEqualToString:@"volume"]) {
            NQRConsoleSetPreference(@"gesture", gesture);
        }
    }

    id loggingValue = configuration[@"diagnosticLogging"];
    if ([loggingValue isKindOfClass:NSNumber.class]) NQRConsoleSetPreference(@"diagnosticLogging", loggingValue);

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), NQRConsolePreferencesChanged, NULL, NULL, true);

    id requestValue = configuration[@"commandRequestID"];
    id commandValue = configuration[@"command"];
    NSString *requestID = [requestValue isKindOfClass:NSString.class] ? requestValue : nil;
    NSString *command = [commandValue isKindOfClass:NSString.class] ? commandValue : nil;
    id processedValue = NQRConsolePreference(@"consoleLastCommandID");
    NSString *processedID = [processedValue isKindOfClass:NSString.class] ? processedValue : nil;

    if (processCommand && requestID.length && ![requestID isEqualToString:processedID]) {
        NQRConsoleSetPreference(@"consoleLastCommandID", requestID);
        if ([command isEqualToString:@"showPanel"]) {
            NQRConsoleLastCommandResult = @"Test Panel command received by SpringBoard.";
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), NQRConsoleShowPanel, NULL, NULL, true);
        } else if ([command isEqualToString:@"reload"]) {
            NQRConsoleLastCommandResult = [NSString stringWithFormat:@"Gesture configuration applied: %@.", NQRConsoleSelectedGesture()];
        } else if ([command isEqualToString:@"clearLogs"]) {
            NQRConsoleLastCommandResult = @"Safe-mode console state cleared.";
        } else {
            NQRConsoleLastCommandResult = @"Unknown or missing console command.";
        }
    }

    NSLog(@"[NextQuickReminderConsole] %@", NQRConsoleLastCommandResult);
    NQRConsoleWriteSnapshot();
}

static void NQRConsoleCommandChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{ NQRConsoleApplyConfiguration(YES); });
}

__attribute__((constructor))
static void NQRConsoleInitialize(void) {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        NSString *processName = NSProcessInfo.processInfo.processName;
        if (![bundleID isEqualToString:@"com.apple.springboard"] && ![processName isEqualToString:@"SpringBoard"]) return;

        NQRConsoleLoadedTimestamp = NSDate.date.timeIntervalSince1970;
        NQRConsoleLastCommandResult = @"Console bridge loaded in SpringBoard safe mode.";
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NQRConsoleCommandChanged, NQRConsoleAppCommand, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ NQRConsoleApplyConfiguration(NO); });
        NSLog(@"[NextQuickReminderConsole] 1.0.2 safe bridge initialized");
    }
}
