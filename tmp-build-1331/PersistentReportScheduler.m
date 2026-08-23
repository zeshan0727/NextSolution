#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "PendingReportSender.h"

static NSString * const NQRAutomationEnabledKey = @"NextReminder.PendingReportAutomationEnabled.v1";
static NSString * const NQRAutomationHourKey = @"NextReminder.PendingReportAutomationHour.v1";
static NSString * const NQRAutomationMinuteKey = @"NextReminder.PendingReportAutomationMinute.v1";
static NSString * const NQRAutomationWeekdaysKey = @"NextReminder.PendingReportAutomationWeekdays.v1";
static CFStringRef const NQRAutomationChanged = CFSTR("com.nextsolution.nextreminder.reportAutomationChanged");

static id NQRPersistentTimer = nil;
static id NQRSchedulerTarget = nil;

static NSString *NQRAppContainerPath(void) {
    @try {
        Class c = NSClassFromString(@"LSApplicationProxy");
        SEL s = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if (!c || ![c respondsToSelector:s]) return nil;
        id proxy = ((id (*)(id, SEL, id))objc_msgSend)(c, s, @"com.nextsolution.nextreminder");
        SEL d = NSSelectorFromString(@"dataContainerURL");
        if (!proxy || ![proxy respondsToSelector:d]) return nil;
        NSURL *url = ((id (*)(id, SEL))objc_msgSend)(proxy, d);
        return [url isKindOfClass:NSURL.class] ? url.path : nil;
    } @catch (__unused NSException *e) { return nil; }
}

static NSDictionary *NQRAutomationPrefs(void) {
    NSString *container = NQRAppContainerPath();
    if (!container.length) return @{};
    NSString *p = [container stringByAppendingPathComponent:@"Library/Preferences/com.nextsolution.nextreminder.plist"];
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
    return [d isKindOfClass:NSDictionary.class] ? d : @{};
}

static NSSet<NSNumber *> *NQRSelectedWeekdays(NSDictionary *prefs) {
    id raw = prefs[NQRAutomationWeekdaysKey];
    NSMutableSet *out = [NSMutableSet set];
    if ([raw isKindOfClass:NSArray.class]) {
        for (id v in (NSArray *)raw) if ([v respondsToSelector:@selector(integerValue)]) [out addObject:@([v integerValue])];
    } else if ([raw isKindOfClass:NSSet.class]) {
        for (id v in (NSSet *)raw) if ([v respondsToSelector:@selector(integerValue)]) [out addObject:@([v integerValue])];
    } else if ([raw isKindOfClass:NSData.class]) {
        id obj = [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil];
        if ([obj isKindOfClass:NSArray.class]) for (id v in obj) if ([v respondsToSelector:@selector(integerValue)]) [out addObject:@([v integerValue])];
    }
    return out;
}

static BOOL NQRWeekdaySelected(NSSet<NSNumber *> *set, NSInteger appleWeekday) {
    if (set.count == 0) return YES;
    if ([set containsObject:@(appleWeekday)]) return YES; // 1=Sun ... 7=Sat
    NSInteger zeroBased = appleWeekday - 1;
    if (zeroBased == 0 && [set containsObject:@0]) return YES; // support 0-based Sunday
    return NO;
}

static NSDate *NQRNextAutomationDate(void) {
    NSDictionary *prefs = NQRAutomationPrefs();
    if (![prefs[NQRAutomationEnabledKey] boolValue]) return nil;
    NSInteger hour = [prefs[NQRAutomationHourKey] respondsToSelector:@selector(integerValue)] ? [prefs[NQRAutomationHourKey] integerValue] : 9;
    NSInteger minute = [prefs[NQRAutomationMinuteKey] respondsToSelector:@selector(integerValue)] ? [prefs[NQRAutomationMinuteKey] integerValue] : 0;
    hour = MAX(0, MIN(23, hour)); minute = MAX(0, MIN(59, minute));
    NSSet *weekdays = NQRSelectedWeekdays(prefs);
    NSCalendar *cal = NSCalendar.currentCalendar;
    NSDate *now = NSDate.date;
    NSDate *start = [cal startOfDayForDate:now];
    for (NSInteger offset = 0; offset < 8; offset++) {
        NSDate *day = [cal dateByAddingUnit:NSCalendarUnitDay value:offset toDate:start options:0];
        NSDateComponents *parts = [cal components:(NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay) fromDate:day];
        parts.hour = hour; parts.minute = minute; parts.second = 0;
        NSDate *candidate = [cal dateFromComponents:parts];
        if (!candidate || [candidate timeIntervalSinceDate:now] < 2.0) continue;
        NSInteger wd = [cal component:NSCalendarUnitWeekday fromDate:candidate];
        if (NQRWeekdaySelected(weekdays, wd)) return candidate;
    }
    return nil;
}

static void NQRInvalidatePersistentTimer(void) {
    if (NQRPersistentTimer && [NQRPersistentTimer respondsToSelector:NSSelectorFromString(@"invalidate")]) {
        ((void (*)(id, SEL))objc_msgSend)(NQRPersistentTimer, NSSelectorFromString(@"invalidate"));
    }
    NQRPersistentTimer = nil;
}

@class NQRPersistentScheduleTarget;
static void NQRScheduleNextPersistentReport(void);

@interface NQRPersistentScheduleTarget : NSObject
- (void)nqrPersistentTimerFired:(id)timer;
@end
@implementation NQRPersistentScheduleTarget
- (void)nqrPersistentTimerFired:(id)timer {
    NSLog(@"[NextQuickReminder] Persistent report timer fired while locked/waking");
    NQRInvalidatePersistentTimer();
    NQRSendPendingReportInBackground();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ NQRScheduleNextPersistentReport(); });
}
@end

static void NQRScheduleNextPersistentReport(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NQRInvalidatePersistentTimer();
        NSDate *fireDate = NQRNextAutomationDate();
        if (!fireDate) {
            NSLog(@"[NextQuickReminder] Persistent report automation disabled or no eligible day");
            return;
        }
        if (!NSClassFromString(@"PCPersistentTimer")) {
            dlopen("/System/Library/PrivateFrameworks/PersistentConnection.framework/PersistentConnection", RTLD_LAZY | RTLD_LOCAL);
        }
        Class timerClass = NSClassFromString(@"PCPersistentTimer");
        if (!timerClass) {
            NSLog(@"[NextQuickReminder] ERROR PCPersistentTimer unavailable; cannot wake locked device");
            return;
        }
        if (!NQRSchedulerTarget) NQRSchedulerTarget = [NQRPersistentScheduleTarget new];
        SEL initSel = NSSelectorFromString(@"initWithFireDate:serviceIdentifier:target:selector:userInfo:");
        id obj = [timerClass alloc];
        if (![obj respondsToSelector:initSel]) {
            NSLog(@"[NextQuickReminder] ERROR PCPersistentTimer initializer unavailable");
            return;
        }
        obj = ((id (*)(id, SEL, id, id, id, SEL, id))objc_msgSend)(obj, initSel, fireDate, @"com.nextsolution.nextquickreminder.pendingreport", NQRSchedulerTarget, @selector(nqrPersistentTimerFired:), nil);
        if (!obj) return;
        SEL wakeSel = NSSelectorFromString(@"setDisableSystemWaking:");
        if ([obj respondsToSelector:wakeSel]) ((void (*)(id, SEL, BOOL))objc_msgSend)(obj, wakeSel, NO);
        SEL earlySel = NSSelectorFromString(@"setMinimumEarlyFireProportion:");
        if ([obj respondsToSelector:earlySel]) ((void (*)(id, SEL, double))objc_msgSend)(obj, earlySel, 1.0);
        SEL scheduleSel = NSSelectorFromString(@"scheduleInRunLoop:");
        if ([obj respondsToSelector:scheduleSel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(obj, scheduleSel, NSRunLoop.mainRunLoop);
            NQRPersistentTimer = obj;
            NSLog(@"[NextQuickReminder] PCPersistentTimer scheduled %@ (system waking enabled)", fireDate);
        } else {
            NSLog(@"[NextQuickReminder] ERROR PCPersistentTimer scheduleInRunLoop unavailable");
        }
    });
}

static void NQRAutomationChangedCallback(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    NQRScheduleNextPersistentReport();
}

void NQRStartPersistentReportScheduler(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NQRAutomationChangedCallback, NQRAutomationChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    });
    NSLog(@"[NextQuickReminder] Starting PCPersistentTimer report scheduler");
    NQRScheduleNextPersistentReport();
}
