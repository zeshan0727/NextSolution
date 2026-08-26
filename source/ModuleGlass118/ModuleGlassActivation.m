// Module Glass 1.1.19 — Next Jailbreak activation UI and live license refresh.
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <stdlib.h>
#import <sys/sysctl.h>

static NSString * const MGPackageID = @"com.nextsolution.nextaura.cc-module-backgrounds";
static NSString * const MGLicenseDomain = @"com.nextsolution.moduleglass";
static NSString * const MGRegistryURL = @"https://raw.githubusercontent.com/zeshan0727/NextJailbreak/main/licenses/moduleglass.json";
static NSString * const MGLicenseSalt = @"nextsolution-license-v1";

static NSString *MGHexSHA256(NSString *input) {
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static NSUserDefaults *MGLicenseDefaults(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:MGLicenseDomain];
}

static BOOL MGValidDeviceID(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^NS-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}$" options:0 error:nil];
    return [regex firstMatchInString:value options:0 range:NSMakeRange(0, value.length)] != nil;
}

static NSString *MGGestaltString(CFStringRef key) {
    typedef CFTypeRef (*MGCopyAnswerFn)(CFStringRef);
    static MGCopyAnswerFn function = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
        if (handle) function = (MGCopyAnswerFn)dlsym(handle, "MGCopyAnswer");
    });
    if (!function) return nil;
    CFTypeRef value = function(key);
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
    NSString *result = [NSString stringWithUTF8String:machine] ?: @"iPhone";
    free(machine);
    return result;
}

static NSString *MGDeviceID(void) {
    static NSString *cached = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUserDefaults *defaults = MGLicenseDefaults();
        NSString *stored = [[defaults stringForKey:@"licenseDeviceID"] uppercaseString];
        if (!MGValidDeviceID(stored)) stored = [[defaults stringForKey:@"deviceIDDisplay"] uppercaseString];
        if (MGValidDeviceID(stored)) {
            cached = stored;
            return;
        }

        NSString *udid = MGGestaltString(CFSTR("UniqueDeviceID"));
        NSString *serial = MGGestaltString(CFSTR("SerialNumber"));
        NSString *raw = [NSString stringWithFormat:@"%@|%@|%@|%@", udid ?: @"", serial ?: @"", MGMachine(), MGPackageID];
        if (!(udid.length || serial.length)) {
            NSString *vendor = UIDevice.currentDevice.identifierForVendor.UUIDString ?: [NSUUID UUID].UUIDString;
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
    return MGHexSHA256([NSString stringWithFormat:@"%@|%@|%@", MGDeviceID(), MGPackageID, MGLicenseSalt]);
}

static BOOL MGStoredActive(void) {
    NSUserDefaults *defaults = MGLicenseDefaults();
    id current = [defaults objectForKey:@"licenseActive"];
    if (current) return [current boolValue];
    return [defaults boolForKey:@"licenseActivated"];
}

static void MGPostLicenseChange(void) {
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(center, CFSTR("com.nextsolution.moduleglass/license.changed"), NULL, NULL, true);
    CFNotificationCenterPostNotification(center, CFSTR("com.nextsolution.unlockvibrate/preferences.changed"), NULL, NULL, true);
}

static void MGPrepareDisplayValues(void) {
    NSUserDefaults *defaults = MGLicenseDefaults();
    BOOL active = MGStoredActive();
    [defaults setObject:MGDeviceID() forKey:@"licenseDeviceID"];
    [defaults setObject:MGDeviceID() forKey:@"deviceIDDisplay"];
    if (![defaults stringForKey:@"licenseStatusDisplay"]) {
        [defaults setObject:(active ? @"Activated" : @"Unactivated") forKey:@"licenseStatusDisplay"];
    }
    [defaults setBool:active forKey:@"licenseActive"];
    [defaults setBool:active forKey:@"licenseActivated"];
    [defaults synchronize];
    CFPreferencesAppSynchronize((__bridge CFStringRef)MGLicenseDomain);
}

static void MGStoreActivation(BOOL active) {
    NSUserDefaults *defaults = MGLicenseDefaults();
    [defaults setObject:MGDeviceID() forKey:@"licenseDeviceID"];
    [defaults setObject:MGDeviceID() forKey:@"deviceIDDisplay"];
    [defaults setObject:(active ? @"Activated" : @"Unactivated") forKey:@"licenseStatusDisplay"];
    [defaults setBool:active forKey:@"licenseActive"];
    [defaults setBool:active forKey:@"licenseActivated"];
    [defaults setDouble:NSDate.date.timeIntervalSince1970 forKey:@"licenseLastCheck"];
    [defaults synchronize];
    CFPreferencesAppSynchronize((__bridge CFStringRef)MGLicenseDomain);
    MGPostLicenseChange();
}

static void MGCheckActivation(void (^completion)(BOOL active, NSError *error)) {
    NSString *urlText = [NSString stringWithFormat:@"%@?t=%.0f", MGRegistryURL, NSDate.date.timeIntervalSince1970];
    NSURL *url = [NSURL URLWithString:urlText];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15.0];
    [request setValue:@"ModuleGlass/1.1.19" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSError *finalError = error;
        BOOL active = MGStoredActive();
        NSArray *entries = nil;
        if (!finalError && [response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)response).statusCode != 200) {
            finalError = [NSError errorWithDomain:@"ModuleGlassLicense" code:((NSHTTPURLResponse *)response).statusCode userInfo:@{NSLocalizedDescriptionKey: @"The activation server returned an unexpected response."}];
        }
        if (!finalError && !data.length) {
            finalError = [NSError errorWithDomain:@"ModuleGlassLicense" code:1 userInfo:@{NSLocalizedDescriptionKey: @"The activation server returned no data."}];
        }
        if (!finalError && data.length) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&finalError];
            entries = [json isKindOfClass:NSDictionary.class] ? ((NSDictionary *)json)[@"active"] : nil;
            if (![entries isKindOfClass:NSArray.class] && !finalError) {
                finalError = [NSError errorWithDomain:@"ModuleGlassLicense" code:2 userInfo:@{NSLocalizedDescriptionKey: @"The activation registry is invalid."}];
            }
        }
        if (!finalError && [entries isKindOfClass:NSArray.class]) {
            active = NO;
            NSString *wanted = MGLicenseToken().lowercaseString;
            for (id entry in entries) {
                if ([entry isKindOfClass:NSString.class] && [((NSString *)entry).lowercaseString isEqualToString:wanted]) {
                    active = YES;
                    break;
                }
            }
            MGStoreActivation(active);
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(active, finalError); });
    }] resume];
}

static NSString *MGQueryEscape(NSString *value) {
    return [value stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: @"";
}

static NSURL *MGCheckoutURL(void) {
    NSString *url = [NSString stringWithFormat:@"https://nextjailbreak.com/license/moduleglass/?device=%@&model=%@&ios=%@",
                     MGQueryEscape(MGDeviceID()), MGQueryEscape(MGMachine()), MGQueryEscape(UIDevice.currentDevice.systemVersion ?: @"")];
    return [NSURL URLWithString:url];
}

static UIViewController *MGPresenter(id controller) {
    if ([controller isKindOfClass:UIViewController.class]) return controller;
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    UIViewController *presenter = window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    return presenter;
}

static void MGShowResult(id controller, NSString *title, NSString *message) {
    UIViewController *presenter = MGPresenter(controller);
    if (!presenter) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static void MGReloadSpecifiers(id controller) {
    SEL selector = NSSelectorFromString(@"reloadSpecifiers");
    if ([controller respondsToSelector:selector]) ((void (*)(id, SEL))objc_msgSend)(controller, selector);
}

static void MGCopyLicenseDeviceIDAction(id controller, SEL command) {
    UIPasteboard.generalPasteboard.string = MGDeviceID();
    MGShowResult(controller, @"Device ID Copied", MGDeviceID());
}

static void MGBuyLicenseAction(id controller, SEL command) {
    NSURL *url = MGCheckoutURL();
    if (!url) return;
    UIApplication *application = UIApplication.sharedApplication;
    if ([application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [application openURL:url options:@{} completionHandler:nil];
    }
}

static void MGCheckActivationAction(id controller, SEL command) {
    MGCheckActivation(^(BOOL active, NSError *error) {
        MGReloadSpecifiers(controller);
        if (error) {
            MGShowResult(controller, @"Module Glass License", [NSString stringWithFormat:@"Could not reach the Next Jailbreak activation server. Your existing activation state was not changed.\n\n%@", error.localizedDescription]);
        } else if (active) {
            MGShowResult(controller, @"Activated", @"Module Glass is activated on this device.");
        } else {
            MGShowResult(controller, @"Unactivated", @"This Device ID is not activated yet. If you already paid, confirm that this exact Device ID has been approved.");
        }
    });
}

static void MGInstallActionOnClass(Class targetClass, const char *name, IMP implementation) {
    if (!targetClass) return;
    SEL selector = sel_registerName(name);
    if (!class_getInstanceMethod(targetClass, selector)) class_addMethod(targetClass, selector, implementation, "v@:");
}

static void MGInstallPreferenceActions(NSUInteger attempt) {
    Class listController = objc_getClass("PSListController");
    Class moduleGlassController = objc_getClass("AuraCategoryListController");
    Class targets[] = { moduleGlassController, listController };
    for (NSUInteger i = 0; i < sizeof(targets) / sizeof(targets[0]); i++) {
        MGInstallActionOnClass(targets[i], "copyLicenseDeviceID", (IMP)MGCopyLicenseDeviceIDAction);
        MGInstallActionOnClass(targets[i], "buyLicense", (IMP)MGBuyLicenseAction);
        MGInstallActionOnClass(targets[i], "checkActivation", (IMP)MGCheckActivationAction);
    }
    if (listController) {
        MGPrepareDisplayValues();
        NSTimeInterval last = [MGLicenseDefaults() doubleForKey:@"licenseLastCheck"];
        if (NSDate.date.timeIntervalSince1970 - last > 60.0) MGCheckActivation(nil);
        return;
    }
    if (attempt < 40) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            MGInstallPreferenceActions(attempt + 1);
        });
    }
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
            dispatch_async(dispatch_get_main_queue(), ^{ MGInstallPreferenceActions(0); });
        } else if ([bundleID isEqualToString:@"com.apple.springboard"]) {
            MGPrepareDisplayValues();
            MGScheduleRuntimeRefresh(8.0);
        }
    }
}
