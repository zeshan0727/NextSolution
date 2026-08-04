#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).with_name("Tweak.xm")
text = path.read_text()

text = text.replace('static NSString *NQRSelectedGesture = @"statusbar";', 'static NSString *NQRSelectedGesture = @"off";', 1)

start = text.index('static void NQRLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);')
end = text.index('static id NQRCopyPreference', start)
safe_log = r'''static NSString *NQRLastRuntimeLog = @"Tweak loaded; no gesture has been activated yet.";

static void NQRLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void NQRLog(NSString *format, ...) {
    if (!format.length) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    if (!message.length) return;
    NQRLastRuntimeLog = [message copy];
    NSLog(@"[NextQuickReminder] %@", message);
}

'''
text = text[:start] + safe_log + text[end:]

text = text.replace('? gesture : @"statusbar";', '? gesture : @"off";', 1)

start = text.index('static void NQRInstallVolumeHook(void) {')
end = text.index('\nstatic void NQRApplyGestureSelection(void)', start)
safe_volume = r'''static BOOL NQRVolumeObserverInstalled = NO;

static void NQRInstallVolumeHook(void) {
    if (NQRVolumeObserverInstalled) return;
    NQRVolumeObserverInstalled = YES;
    [NSNotificationCenter.defaultCenter addObserverForName:@"AVSystemController_SystemVolumeDidChangeNotification"
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(__unused NSNotification *note) {
        NQRHandleVolumePulse(@"volume-change notification");
    }];
    NQRLog(@"Volume Up monitoring enabled without private method hooks");
}
'''
text = text[:start] + safe_volume + text[end:]

text = text.replace('''        } else if ([NQRSelectedGesture isEqualToString:@"volume"]) {
            NQRLog(@"Volume Up hold selected; waiting for repeated button pulses");
''', '''        } else if ([NQRSelectedGesture isEqualToString:@"volume"]) {
            NQRInstallVolumeHook();
            NQRLog(@"Volume Up hold selected; waiting for repeated system volume notifications");
''', 1)

old_ctor_observers = '''        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidChangeStatusBarFrameNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            NQRUpdateStatusGestureFrame();
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:@"AVSystemController_SystemVolumeDidChangeNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            NQRHandleVolumePulse(@"volume-change notification");
        }];

'''
text = text.replace(old_ctor_observers, '', 1)
text = text.replace('''        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NQRInstallVolumeHook();
            NQRReloadPreferences();
        });
''', '''        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NQRReloadPreferences();
        });
''', 1)
text = text.replace('Next Quick Reminder 1.0.0 loaded', 'Next Quick Reminder 1.0.2 loaded in safe startup mode', 1)

path.write_text(text)
print("Applied Next Quick Reminder 1.0.2 SpringBoard crash hardening.")
