#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <CommonCrypto/CommonDigest.h>
#import <dlfcn.h>
#import <sys/sysctl.h>

static NSString * const MGPackageID = @"com.nextsolution.nextaura.cc-module-backgrounds";
static NSString * const MGLicenseDomain = @"com.nextsolution.moduleglass";
static NSString * const MGRegistryURL = @"https://raw.githubusercontent.com/zeshan0727/NextSolution/main/licenses/moduleglass.json";
static NSString * const MGPrice = @"$1.00";
static CFStringRef const MGTweakPrefsDomain = CFSTR("com.nextsolution.unlockvibrate");
static CFStringRef const MGLicensePrefsDomain = CFSTR("com.nextsolution.moduleglass");

static CFPropertyListRef (*MGOrigCFPreferencesCopyAppValue)(CFStringRef, CFStringRef) = NULL;

static NSString *MGHexSHA256(NSString *input) {
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [result appendFormat:@"%02x", digest[i]];
    return result;
}

static NSString *MGGestaltString(CFStringRef key) {
    typedef CFTypeRef (*MGCopyAnswerFn)(CFStringRef);
    static MGCopyAnswerFn fn = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
        if (handle) fn = (MGCopyAnswerFn)dlsym(handle, "MGCopyAnswer");
    });
    if (!fn) return nil;
    CFTypeRef value = fn(key);
    if (!value) return nil;
    NSString *result = nil;
    if (CFGetTypeID(value) == CFStringGetTypeID()) result = [(__bridge NSString *)value copy];
    CFRelease(value);
    return result;
}

static NSString *MGMachine(void) {
    size_t size = 0;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    if (!size) return @"iPhone";
    char *machine = calloc(1, size);
    if (!machine) return @"iPhone";
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *value = [NSString stringWithUTF8String:machine] ?: @"iPhone";
    free(machine);
    return value;
}

static NSString *MGDeviceID(void) {
    static NSString *cached = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *udid = MGGestaltString(CFSTR("UniqueDeviceID"));
        NSString *serial = MGGestaltString(CFSTR("SerialNumber"));
        NSString *raw = [NSString stringWithFormat:@"%@|%@|%@|%@", udid ?: @"", serial ?: @"", MGMachine(), MGPackageID];
        if (!(udid.length || serial.length)) {
            NSString *vendor = UIDevice.currentDevice.identifierForVendor.UUIDString ?: @"unknown";
            raw = [NSString stringWithFormat:@"%@|%@|%@", vendor, MGMachine(), MGPackageID];
        }
        NSString *hex = [MGHexSHA256(raw) uppercaseString];
        cached = [NSString stringWithFormat:@"NS-%@-%@-%@-%@",
                  [hex substringWithRange:NSMakeRange(0, 4)],
                  [hex substringWithRange:NSMakeRange(4, 4)],
                  [hex substringWithRange:NSMakeRange(8, 4)],
                  [hex substringWithRange:NSMakeRange(12, 4)]];
    });
    return cached;
}

static NSString *MGLicenseToken(void) {
    return MGHexSHA256([NSString stringWithFormat:@"%@|%@|nextsolution-license-v1", MGDeviceID(), MGPackageID]);
}

static NSUserDefaults *MGLicenseDefaults(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:MGLicenseDomain];
}

static BOOL MGStoredActive(void) {
    return [MGLicenseDefaults() boolForKey:@"licenseActivated"];
}

static void MGPostLicenseChange(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.nextsolution.moduleglass/license.changed"), NULL, NULL, true);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.nextsolution.unlockvibrate/preferences.changed"), NULL, NULL, true);
}

static void MGStoreActivation(BOOL active) {
    NSUserDefaults *d = MGLicenseDefaults();
    [d setObject:MGDeviceID() forKey:@"licenseDeviceID"];
    [d setObject:(active ? @"Activated" : @"Not Activated") forKey:@"licenseStatusDisplay"];
    [d setBool:active forKey:@"licenseActivated"];
    [d setDouble:NSDate.date.timeIntervalSince1970 forKey:@"licenseLastCheck"];
    [d synchronize];
    MGPostLicenseChange();
}

static void MGCheckActivation(void (^completion)(BOOL active, NSError *error)) {
    NSString *urlText = [NSString stringWithFormat:@"%@?t=%.0f", MGRegistryURL, NSDate.date.timeIntervalSince1970];
    NSURL *url = [NSURL URLWithString:urlText];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15.0];
    [request setValue:@"ModuleGlass/1.1.18" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSError *finalError = error;
        BOOL active = MGStoredActive();
        BOOL validRegistry = NO;
        if (!finalError && data.length) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&finalError];
            NSArray *list = [json isKindOfClass:NSDictionary.class] ? ((NSDictionary *)json)[@"active"] : nil;
            if ([list isKindOfClass:NSArray.class]) {
                validRegistry = YES;
                active = NO;
                NSString *wanted = MGLicenseToken().lowercaseString;
                for (id entry in list) {
                    if ([entry isKindOfClass:NSString.class] && [((NSString *)entry).lowercaseString isEqualToString:wanted]) {
                        active = YES;
                        break;
                    }
                }
            } else if (!finalError) {
                finalError = [NSError errorWithDomain:@"ModuleGlassLicense" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Invalid activation registry."}];
            }
        }
        if (validRegistry && !finalError) MGStoreActivation(active);
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(active, finalError); });
    }] resume];
}

static NSString *MGQueryEscape(NSString *value) {
    return [value stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: @"";
}

static NSURL *MGCheckoutURL(void) {
    NSString *url = [NSString stringWithFormat:@"https://nextsolution.cc/license/moduleglass/?device=%@&model=%@&ios=%@",
                     MGQueryEscape(MGDeviceID()), MGQueryEscape(MGMachine()), MGQueryEscape(UIDevice.currentDevice.systemVersion ?: @"")];
    return [NSURL URLWithString:url];
}

static void MGOpenURL(NSURL *url) {
    if (!url) return;
    UIApplication *app = UIApplication.sharedApplication;
    if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [app openURL:url options:@{} completionHandler:nil];
    }
}

static void MGReloadSpecifiers(id controller) {
    SEL selector = NSSelectorFromString(@"reloadSpecifiers");
    if ([controller respondsToSelector:selector]) ((void(*)(id, SEL))objc_msgSend)(controller, selector);
}

static UIViewController *MGPresenter(id controller) {
    if ([controller isKindOfClass:UIViewController.class]) return controller;
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}

static void MGShowResult(UIViewController *presenter, NSString *message) {
    if (!presenter) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Module Glass Activation" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static void MGOpenModuleGlassLicense(id controller, SEL _cmd, id specifier) {
    UIViewController *presenter = MGPresenter(controller);
    if (!presenter) return;
    NSUserDefaults *d = MGLicenseDefaults();
    NSString *status = [d stringForKey:@"licenseStatusDisplay"] ?: (MGStoredActive() ? @"Activated" : @"Not Activated");
    NSString *message = [NSString stringWithFormat:@"Status: %@\nDevice ID: %@\nLicense: %@ lifetime", status, MGDeviceID(), MGPrice];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Module Glass License & Device" message:message preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy Device ID" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = MGDeviceID();
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Check Activation" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        MGCheckActivation(^(BOOL active, NSError *error) {
            MGReloadSpecifiers(controller);
            if (error) MGShowResult(presenter, [NSString stringWithFormat:@"Could not check activation.\n%@", error.localizedDescription]);
            else MGShowResult(presenter, active ? @"This device is activated. Module Glass is enabled." : @"This device is not activated yet. Copy the Device ID and activate it first.");
        });
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Buy / Activate — %@", MGPrice] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        MGOpenURL(MGCheckoutURL());
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = presenter.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMaxY(presenter.view.bounds) - 20.0, 1.0, 1.0);
    }
    [presenter presentViewController:sheet animated:YES completion:nil];
}

static void MGInstallPreferenceAction(NSUInteger attempt) {
    Class cls = objc_getClass("PSListController");
    SEL sel = NSSelectorFromString(@"openModuleGlassLicense:");
    if (cls) {
        if (!class_getInstanceMethod(cls, sel)) class_addMethod(cls, sel, (IMP)MGOpenModuleGlassLicense, "v@:@");
        NSUserDefaults *d = MGLicenseDefaults();
        NSTimeInterval last = [d doubleForKey:@"licenseLastCheck"];
        if (NSDate.date.timeIntervalSince1970 - last > 60.0) MGCheckActivation(nil);
        return;
    }
    if (attempt < 20) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MGInstallPreferenceAction(attempt + 1); });
}

static BOOL MGStringEqual(CFStringRef a, CFStringRef b) {
    return a && b && CFStringCompare(a, b, 0) == kCFCompareEqualTo;
}

static BOOL MGIsGatedKey(CFStringRef key) {
    static CFStringRef keys[] = {
        CFSTR("CCModuleBackgroundsEnabled"),
        CFSTR("CCModuleRemoveBlur"),
        CFSTR("CCModuleControlGlowEnabled"),
        CFSTR("CCModuleVolumeIconColorEnabled")
    };
    for (NSUInteger i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) if (MGStringEqual(key, keys[i])) return YES;
    return NO;
}

static BOOL MGLicenseIsActiveForRuntime(void) {
    if (!MGOrigCFPreferencesCopyAppValue) return NO;
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
    if (MGOrigCFPreferencesCopyAppValue && MGStringEqual(applicationID, MGTweakPrefsDomain) && MGIsGatedKey(key) && !MGLicenseIsActiveForRuntime()) {
        return CFRetain(kCFBooleanFalse);
    }
    return MGOrigCFPreferencesCopyAppValue ? MGOrigCFPreferencesCopyAppValue(key, applicationID) : NULL;
}

static void MGScheduleRuntimeRefresh(NSTimeInterval delay) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        MGCheckActivation(^(__unused BOOL active, __unused NSError *error) {
            MGScheduleRuntimeRefresh(20.0 * 60.0);
        });
    });
}

__attribute__((constructor)) static void ModuleGlassActivationInit(void) {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"";
        if ([bundleID isEqualToString:@"com.apple.Preferences"]) {
            dispatch_async(dispatch_get_main_queue(), ^{ MGInstallPreferenceAction(0); });
        } else if ([bundleID isEqualToString:@"com.apple.springboard"]) {
            void *symbol = dlsym(RTLD_DEFAULT, "CFPreferencesCopyAppValue");
            if (symbol) MSHookFunction(symbol, (void *)&MGCFPreferencesCopyAppValue, (void **)&MGOrigCFPreferencesCopyAppValue);
            MGScheduleRuntimeRefresh(8.0);
        }
    }
}
