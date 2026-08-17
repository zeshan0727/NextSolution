#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parent
runtime_path = ROOT / "RuntimeV023.xm"
src = runtime_path.read_text()

anchor = '''typedef void(*LGTLayoutIMP)(id,SEL);static LGTLayoutIMP gOriginalLayout=NULL;'''
if anchor not in src:
    raise SystemExit("Live-clock insertion anchor not found")

live_clock = r'''
static dispatch_source_t gLGTLiveClockTimer = nil;

static BOOL LGTSystemUses24HourTime(void) {
    BOOL use24 = NO;
    CFPropertyListRef forced = CFPreferencesCopyAppValue(CFSTR("AppleICUForce24HourTime"), CFSTR(".GlobalPreferences"));
    if (forced && CFGetTypeID(forced) == CFBooleanGetTypeID()) {
        use24 = CFBooleanGetValue((CFBooleanRef)forced);
        CFRelease(forced);
        return use24;
    }
    if (forced) CFRelease(forced);
    NSString *format = [NSDateFormatter dateFormatFromTemplate:@"jmm" options:0 locale:NSLocale.currentLocale];
    return [format rangeOfString:@"H"].location != NSNotFound || [format rangeOfString:@"k"].location != NSNotFound;
}

static NSString *LGTCurrentClockText(void) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = NSLocale.currentLocale;
    formatter.calendar = NSCalendar.currentCalendar;
    formatter.timeZone = NSTimeZone.localTimeZone;
    formatter.dateFormat = LGTSystemUses24HourTime() ? @"HH:mm" : @"h:mm";
    return [formatter stringFromDate:[NSDate date]] ?: @"";
}

static void LGTRefreshLiveClockNow(void) {
    if (!gEnabled) return;
    NSString *clockText = gCustomTimeEnabled ? LGTCurrentClockText() : nil;
    NSDate *now = [NSDate date];
    for (UIView *container in gKnownContainers.allObjects) {
        if (!container || !container.window) continue;
        UILabel *time = nil, *date = nil;
        LGTResolveLabels(container, &time, &date);
        if (time && gCustomTimeEnabled && clockText.length) {
            LGTLabelState *state = LGTStateForLabel(time);
            state.nativeText = clockText;
            state.nativeAttributedText = nil;
            time.text = clockText;
            LGTApplyTimeAppearance(time);
        }
        if (date && gCustomDateEnabled && gDateFormatter) {
            NSString *dateText = [gDateFormatter stringFromDate:now];
            if (dateText.length) {
                LGTLabelState *state = LGTStateForLabel(date);
                state.nativeText = dateText;
                state.nativeAttributedText = nil;
                date.text = dateText;
                LGTApplyDateAppearance(date);
            }
        }
        LGTApplyFinalGeometry(container);
    }
}

static void LGTArmLiveClockTimer(void) {
    if (!gLGTLiveClockTimer) return;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    long long wholeSeconds = (long long)now;
    NSTimeInterval delay = (60 - (wholeSeconds % 60)) + 0.08;
    dispatch_source_set_timer(gLGTLiveClockTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                              60 * NSEC_PER_SEC,
                              150 * NSEC_PER_MSEC);
}

static void LGTStartLiveClockTimer(void) {
    if (gLGTLiveClockTimer) return;
    gLGTLiveClockTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(gLGTLiveClockTimer, ^{
        LGTRefreshLiveClockNow();
    });
    LGTArmLiveClockTimer();
    dispatch_resume(gLGTLiveClockTimer);
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationSignificantTimeChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        LGTRefreshLiveClockNow();
        LGTArmLiveClockTimer();
    }];
}

'''
src = src.replace(anchor, live_clock + anchor, 1)

old_ctor = '''        Class cls=LGTResolveContainerClass();if(cls)MSHookMessageEx(cls,@selector(layoutSubviews),(IMP)LGTHookedLayout,(IMP *)&gOriginalLayout);'''
new_ctor = '''        Class cls=LGTResolveContainerClass();if(cls)MSHookMessageEx(cls,@selector(layoutSubviews),(IMP)LGTHookedLayout,(IMP *)&gOriginalLayout);\n        LGTStartLiveClockTimer();'''
if old_ctor not in src:
    raise SystemExit("Live-clock ctor anchor not found")
src = src.replace(old_ctor, new_ctor, 1)

runtime_path.write_text(src)
print("Patched RuntimeV023.xm with minute-aligned live clock/date refresh")
