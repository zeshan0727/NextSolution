#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <dlfcn.h>

static NSString * const MGLicensePackage = @"com.nextsolution.nextaura.cc-module-backgrounds";
static NSString * const MGLicenseSalt = @"nextsolution-license-v1";
static NSString * const MGLicenseRegistryURL = @"https://nextsolution.cc/licenses/moduleglass.json";
static NSString * const MGLicenseCheckoutBase = @"https://nextsolution.cc/license/moduleglass/";
static NSString * const MGLicenseDefaultsSuite = @"com.nextsolution.moduleglass.license";
static NSString * const MGLicenseScreenMarker = @"Module Glass License & Device";

static NSString *MGSHA256(NSString *input) {
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *out = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [out appendFormat:@"%02x", digest[i]];
    return out;
}

static NSString *MGRawHardwareIdentity(void) {
    typedef CFTypeRef (*MGCopyAnswerFunc)(CFStringRef);
    void *handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (handle) {
        MGCopyAnswerFunc copyAnswer = (MGCopyAnswerFunc)dlsym(handle, "MGCopyAnswer");
        if (copyAnswer) {
            NSArray<NSString *> *keys = @[@"UniqueDeviceID", @"UniqueChipID", @"SerialNumber"];
            for (NSString *key in keys) {
                CFTypeRef value = copyAnswer((__bridge CFStringRef)key);
                if (value) {
                    id bridged = CFBridgingRelease(value);
                    NSString *s = [bridged description];
                    if (s.length > 4) { dlclose(handle); return s; }
                }
            }
        }
        dlclose(handle);
    }
    UIDevice *d = UIDevice.currentDevice;
    return [NSString stringWithFormat:@"%@|%@|%@", d.name ?: @"iPhone", d.model ?: @"iPhone", d.systemVersion ?: @"0"];
}

static NSString *MGDeviceIDFromRaw(NSString *raw) {
    NSString *hex = [MGSHA256([NSString stringWithFormat:@"%@|%@|moduleglass-device-v1", raw ?: @"unknown", MGLicensePackage]) uppercaseString];
    if (hex.length < 16) return @"NS-0000-0000-0000-0000";
    return [NSString stringWithFormat:@"NS-%@-%@-%@-%@",
            [hex substringWithRange:NSMakeRange(0,4)],
            [hex substringWithRange:NSMakeRange(4,4)],
            [hex substringWithRange:NSMakeRange(8,4)],
            [hex substringWithRange:NSMakeRange(12,4)]];
}

@interface MGLicenseManager : NSObject {
    NSString *_deviceID;
    BOOL _active;
    NSDate *_lastCheck;
}
@property (nonatomic, readonly) NSString *deviceID;
@property (nonatomic, readonly, getter=isActive) BOOL active;
@property (nonatomic, readonly) NSDate *lastCheck;
+ (instancetype)shared;
- (void)refreshWithCompletion:(void (^)(BOOL active))completion;
- (NSURL *)checkoutURL;
@end

@implementation MGLicenseManager

+ (instancetype)shared {
    static MGLicenseManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [MGLicenseManager new]; });
    return m;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        (void)MGLicenseScreenMarker;
        NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:MGLicenseDefaultsSuite];
        NSString *stored = [d stringForKey:@"deviceID"];
        _deviceID = stored.length ? stored : MGDeviceIDFromRaw(MGRawHardwareIdentity());
        [d setObject:_deviceID forKey:@"deviceID"];
        _active = [d boolForKey:@"licenseActive"];
        NSTimeInterval ts = [d doubleForKey:@"licenseLastCheck"];
        if (ts > 0) _lastCheck = [NSDate dateWithTimeIntervalSince1970:ts];
        [d synchronize];
    }
    return self;
}

- (NSString *)deviceID { return _deviceID; }
- (BOOL)isActive { return _active; }
- (NSDate *)lastCheck { return _lastCheck; }

- (NSString *)licenseToken {
    return MGSHA256([NSString stringWithFormat:@"%@|%@|%@", self.deviceID, MGLicensePackage, MGLicenseSalt]);
}

- (void)storeActive:(BOOL)active {
    _active = active;
    _lastCheck = NSDate.date;
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:MGLicenseDefaultsSuite];
    [d setObject:self.deviceID forKey:@"deviceID"];
    [d setBool:active forKey:@"licenseActive"];
    [d setDouble:_lastCheck.timeIntervalSince1970 forKey:@"licenseLastCheck"];
    [d synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.nextsolution.moduleglass/license.changed"), NULL, NULL, true);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.nextsolution.unlockvibrate/preferences.changed"), NULL, NULL, true);
}

- (void)refreshWithCompletion:(void (^)(BOOL))completion {
    NSURL *url = [NSURL URLWithString:MGLicenseRegistryURL];
    if (!url) { if (completion) completion(self.active); return; }
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        BOOL active = self.active;
        if (data.length && !error) {
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([obj isKindOfClass:NSDictionary.class]) {
                NSArray *list = ((NSDictionary *)obj)[@"active"];
                if ([list isKindOfClass:NSArray.class]) {
                    NSString *needle = self.licenseToken.lowercaseString;
                    active = NO;
                    for (id value in list) {
                        if ([[value description].lowercaseString isEqualToString:needle]) { active = YES; break; }
                    }
                    [self storeActive:active];
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(active); });
    }];
    [task resume];
}

- (NSURL *)checkoutURL {
    UIDevice *d = UIDevice.currentDevice;
    NSURLComponents *c = [NSURLComponents componentsWithString:MGLicenseCheckoutBase];
    c.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"device" value:self.deviceID],
        [NSURLQueryItem queryItemWithName:@"model" value:d.model ?: @"iPhone"],
        [NSURLQueryItem queryItemWithName:@"ios" value:d.systemVersion ?: @""]
    ];
    return c.URL;
}
@end

__attribute__((constructor)) static void MGLicenseInit(void) {
    @autoreleasepool { (void)[MGLicenseManager shared]; }
}
