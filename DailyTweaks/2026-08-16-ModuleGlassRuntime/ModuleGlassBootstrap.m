#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <unistd.h>

static NSString * const MGBootLogDirectory = @"/var/mobile/Library/Logs/NextSolution";
static NSString * const MGBootLogPath = @"/var/mobile/Library/Logs/NextSolution/module-glass.log";
static NSString * const MGBootControlNotification = @"com.nextsolution.nextlog/control.changed";

static void MGBootWrite(NSString *message) {
    if (!message.length) return;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *dirError = nil;
    [fm createDirectoryAtPath:MGBootLogDirectory withIntermediateDirectories:YES attributes:nil error:&dirError];
    NSString *line = [NSString stringWithFormat:@"[%@] BOOT %@\n", [NSDate date], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (![fm fileExistsAtPath:MGBootLogPath]) {
        NSError *writeError = nil;
        BOOL ok = [data writeToFile:MGBootLogPath options:NSDataWritingAtomic error:&writeError];
        if (!ok) NSLog(@"[ModuleGlass] heartbeat write failed: %@", writeError);
        return;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:MGBootLogPath];
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    } else {
        NSLog(@"[ModuleGlass] heartbeat could not open %@", MGBootLogPath);
    }
}

static void MGBootControlChanged(__unused CFNotificationCenterRef center,
                                 __unused void *observer,
                                 __unused CFStringRef name,
                                 __unused const void *object,
                                 __unused CFDictionaryRef userInfo) {
    NSDictionary *control = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.nextsolution.nextlog.plist"];
    MGBootWrite([NSString stringWithFormat:@"NextLog notification received controlReadable=%d enabled=%@ activeTweak=%@",
                 [control isKindOfClass:NSDictionary.class], control[@"enabled"], control[@"activeTweak"]]);
}

__attribute__((constructor(101))) static void ModuleGlassEarlyBootstrap(void) {
    @autoreleasepool {
        void *handle = dlopen("/System/Library/PrivateFrameworks/ControlCenterUI.framework/ControlCenterUI", RTLD_LAZY | RTLD_LOCAL);
        Class moduleClass = NSClassFromString(@"CCUIModuleContainerViewController");
        Class contentClass = NSClassFromString(@"CCUIContentModuleContainerViewController");
        MGBootWrite([NSString stringWithFormat:@"ModuleGlass runtime process=%@ pid=%d dlopen=%p moduleClass=%@ contentClass=%@",
                     NSBundle.mainBundle.bundleIdentifier ?: @"<nil>", getpid(), handle,
                     moduleClass ? NSStringFromClass(moduleClass) : @"<missing>",
                     contentClass ? NSStringFromClass(contentClass) : @"<missing>"]);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, MGBootControlChanged,
                                        (__bridge CFStringRef)MGBootControlNotification, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
