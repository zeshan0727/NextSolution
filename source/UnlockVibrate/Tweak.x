#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

static CFStringRef const UVPreferencesDomain = CFSTR("com.nextsolution.unlockvibrate");
static CFStringRef const UVPreferencesNotification = CFSTR("com.nextsolution.unlockvibrate/preferences.changed");

static BOOL UVUnlockEnabled = YES;
static BOOL UVCallConnectedEnabled = YES;
static __unsafe_unretained id UVLastConnectedCall = nil;
static CFAbsoluteTime UVLastCallVibrationTime = 0;

static BOOL UVReadBool(CFStringRef key, BOOL fallback) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, UVPreferencesDomain);
    if (!value) return fallback;

    BOOL result = fallback;
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
        result = CFBooleanGetValue((CFBooleanRef)value);
    } else if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        result = [(__bridge NSNumber *)value boolValue];
    }
    CFRelease(value);
    return result;
}

static void UVLoadPreferences(void) {
    UVUnlockEnabled = UVReadBool(CFSTR("Enabled"), YES);
    UVCallConnectedEnabled = UVReadBool(CFSTR("CallConnectedEnabled"), YES);
}

static void UVPreferencesChanged(CFNotificationCenterRef center, void *observer,
                                 CFStringRef name, const void *object,
                                 CFDictionaryRef userInfo) {
    UVLoadPreferences();
}

static void UVVibrate(void) {
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

static void UVVibrateForConnectedCall(id call) {
    if (!UVCallConnectedEnabled || !call) return;

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (UVLastConnectedCall == call && (now - UVLastCallVibrationTime) < 3.0) return;

    UVLastConnectedCall = call;
    UVLastCallVibrationTime = now;
    UVVibrate();
}

@interface SBLockScreenManager : NSObject
- (void)_finishUIUnlockFromSource:(NSInteger)source withOptions:(id)options;
@end

@interface TUCall : NSObject
- (NSInteger)status;
@end

%hook SBLockScreenManager

- (void)_finishUIUnlockFromSource:(NSInteger)source withOptions:(id)options {
    %orig;
    if (UVUnlockEnabled) UVVibrate();
}

%end

%hook TUCallCenter

- (void)handleCallConnected:(id)call {
    %orig;
    UVVibrateForConnectedCall(call);
}

- (void)handleCallStatusChanged:(TUCall *)call userInfo:(id)userInfo {
    %orig;
    if ([call respondsToSelector:@selector(status)] && [call status] == 4) {
        UVVibrateForConnectedCall(call);
    }
}

- (void)handleCallStatusChanged:(TUCall *)call {
    %orig;
    if ([call respondsToSelector:@selector(status)] && [call status] == 4) {
        UVVibrateForConnectedCall(call);
    }
}

%end

%ctor {
    @autoreleasepool {
        UVLoadPreferences();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        UVPreferencesChanged,
                                        UVPreferencesNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
