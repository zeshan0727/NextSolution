#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@interface PSListController : UIViewController
@property(nonatomic, retain) NSArray *specifiers;
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifiers;
@end

@interface NHLRootListController : PSListController {
    NSArray *_nhlSpecifiers;
}
@end

static NSString *const NHLStatusPath = @"/var/mobile/Library/Preferences/com.nextsolution.nexthomelock.runtime.plist";
static CFStringRef const NHLTestLockNotification = CFSTR("com.nextsolution.nexthomelock.test-lock");

@implementation NHLRootListController

- (NSArray *)specifiers {
    if (!_nhlSpecifiers) {
        _nhlSpecifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _nhlSpecifiers;
}

- (NSMutableDictionary *)statusDictionary {
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:NHLStatusPath];
    return stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
}

- (NSString *)formattedTimeForValue:(id)value {
    NSTimeInterval timestamp = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
    if (timestamp <= 0) return @"Never";

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]] ?: @"Unknown";
}

- (NSString *)installedVersion {
    return @"1.0.3";
}

- (NSString *)injectionStatus {
    NSDictionary *status = [self statusDictionary];
    NSString *loadedVersion = status[@"loadedVersion"];
    if (![status[@"tweakLoaded"] boolValue]) return @"Not detected in SpringBoard";
    if (![loadedVersion isEqualToString:@"1.0.3"]) {
        return [NSString stringWithFormat:@"Stale runtime: %@", loadedVersion ?: @"unknown version"];
    }
    return [NSString stringWithFormat:@"Active · PID %@", status[@"springBoardPID"] ?: @"?"];
}

- (NSString *)loadedAtStatus {
    return [self formattedTimeForValue:[self statusDictionary][@"loadedAt"]];
}

- (NSString *)rootFolderStatus {
    NSDictionary *status = [self statusDictionary];
    if (![status[@"tweakLoaded"] boolValue]) return @"Unknown until injection is active";
    if (![status[@"rootFolderClassPresent"] boolValue]) return @"SBRootFolderView class missing";
    if (![status[@"rootFolderHookSeen"] boolValue]) return @"Class exists; hook not reached";
    return @"Hook reached";
}

- (NSString *)gestureStatus {
    NSDictionary *status = [self statusDictionary];
    if (![status[@"gestureInstalled"] boolValue]) return @"Not attached";
    NSString *host = status[@"gestureHostClass"] ?: @"Unknown host";
    return [NSString stringWithFormat:@"Attached to %@", host];
}

- (NSString *)lastTouchStatus {
    NSDictionary *status = [self statusDictionary];
    NSString *reason = status[@"lastTouchReason"];
    if (!reason.length) return @"No Home Screen touch recorded";
    NSString *decision = [status[@"lastTouchAccepted"] boolValue] ? @"Accepted" : @"Rejected";
    NSString *className = status[@"lastTouchClass"] ?: @"Unknown view";
    return [NSString stringWithFormat:@"%@ · %@ · %@", decision, className, reason];
}

- (NSString *)lastGestureStatus {
    NSDictionary *status = [self statusDictionary];
    if ([status[@"lastGestureRecognized"] boolValue]) {
        return [NSString stringWithFormat:@"Recognized at %@", [self formattedTimeForValue:status[@"lastGestureRecognizedAt"]]];
    }
    NSString *reason = status[@"lastGestureBeginReason"];
    return reason.length ? reason : @"No double-tap recognized";
}

- (NSString *)testCommandStatus {
    NSDictionary *status = [self statusDictionary];
    if (![status[@"testCommandReceived"] boolValue]) return @"Not received by SpringBoard";
    return [NSString stringWithFormat:@"Received at %@", [self formattedTimeForValue:status[@"testCommandReceivedAt"]]];
}

- (NSString *)lastLockStatus {
    NSDictionary *status = [self statusDictionary];
    NSString *source = status[@"lastLockSource"];
    NSString *route = status[@"lastLockRoute"];
    if (!source.length && !route.length) return @"No lock request recorded";
    return [NSString stringWithFormat:@"%@ · %@", source ?: @"Unknown source", route ?: @"Unknown route"];
}

- (void)testLock {
    NSMutableDictionary *status = [self statusDictionary];
    status[@"testCommandReceived"] = @NO;
    status[@"lastSettingsCommandSentAt"] = @([[NSDate date] timeIntervalSince1970]);
    [status writeToFile:NHLStatusPath atomically:YES];

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NHLTestLockNotification,
        NULL,
        NULL,
        true
    );

    [self reloadSpecifiers];
}

- (void)refreshStatus {
    [self reloadSpecifiers];
}

@end
