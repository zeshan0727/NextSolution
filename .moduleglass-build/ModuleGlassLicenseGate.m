#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <substrate.h>
#import <dlfcn.h>

static CFStringRef const MGTweakPrefsDomain = CFSTR("com.nextsolution.unlockvibrate");
static CFStringRef const MGLicensePrefsDomain = CFSTR("com.nextsolution.moduleglass");
static CFPropertyListRef (*MGOrigCFPreferencesCopyAppValue)(CFStringRef key, CFStringRef applicationID) = NULL;

static BOOL MGStringEqual(CFStringRef a, CFStringRef b) {
    if (!a || !b) return NO;
    return CFStringCompare(a, b, 0) == kCFCompareEqualTo;
}

static BOOL MGIsGatedBoolKey(CFStringRef key) {
    if (!key) return NO;
    static CFStringRef keys[] = {
        CFSTR("CCModuleBackgroundsEnabled"),
        CFSTR("CCModuleRemoveBlur"),
        CFSTR("CCModuleControlGlowEnabled"),
        CFSTR("CCModuleVolumeIconColorEnabled")
    };
    for (NSUInteger i = 0; i < sizeof(keys)/sizeof(keys[0]); i++) {
        if (MGStringEqual(key, keys[i])) return YES;
    }
    return NO;
}

static BOOL MGLicenseIsActive(void) {
    if (!MGOrigCFPreferencesCopyAppValue) return YES;
    CFPreferencesAppSynchronize(MGLicensePrefsDomain);
    CFPropertyListRef value = MGOrigCFPreferencesCopyAppValue(CFSTR("licenseActivated"), MGLicensePrefsDomain);
    BOOL active = NO;
    if (value) {
        if (CFGetTypeID(value) == CFBooleanGetTypeID()) active = CFBooleanGetValue((CFBooleanRef)value);
        else if (CFGetTypeID(value) == CFNumberGetTypeID()) {
            int numeric = 0;
            CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &numeric);
            active = numeric != 0;
        }
        CFRelease(value);
    }
    return active;
}

static CFPropertyListRef MGCFPreferencesCopyAppValue(CFStringRef key, CFStringRef applicationID) {
    if (MGOrigCFPreferencesCopyAppValue && MGStringEqual(applicationID, MGTweakPrefsDomain) && MGIsGatedBoolKey(key) && !MGLicenseIsActive()) {
        return CFRetain(kCFBooleanFalse);
    }
    return MGOrigCFPreferencesCopyAppValue ? MGOrigCFPreferencesCopyAppValue(key, applicationID) : NULL;
}

__attribute__((constructor)) static void ModuleGlassLicenseGateInit(void) {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"";
        if (![bundleID isEqualToString:@"com.apple.springboard"]) return;
        void *symbol = dlsym(RTLD_DEFAULT, "CFPreferencesCopyAppValue");
        if (symbol) MSHookFunction(symbol, (void *)&MGCFPreferencesCopyAppValue, (void **)&MGOrigCFPreferencesCopyAppValue);
    }
}
