#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <CommonCrypto/CommonDigest.h>

static NSString * const MGActivationDomain = @"com.nextsolution.moduleglass";
static NSString * const MGPackageID = @"com.nextsolution.nextaura.cc-module-backgrounds";
static NSString * const MGRegistryURL = @"https://raw.githubusercontent.com/zeshan0727/NextSolution/main/licenses/moduleglass.json";
static NSString * const MGPrice = @"$1.00";

static char kMGHeaderKey;
static char kMGStatusLabelKey;
static char kMGLicenseButtonKey;
static char kMGInstalledKey;

static IMP gOrigViewDidLoad = NULL;
static IMP gOrigViewWillAppear = NULL;
static IMP gOrigWillDisplayCell = NULL;

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
    if (size == 0) return UIDevice.currentDevice.model ?: @"iPhone";
    char *machine = calloc(1, size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *result = [NSString stringWithUTF8String:machine ?: ""];
    free(machine);
    return result.length ? result : (UIDevice.currentDevice.model ?: @"iPhone");
}

static NSString *MGDeviceID(void) {
    static NSString *cached = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *udid = MGGestaltString(CFSTR("UniqueDeviceID"));
        NSString *serial = MGGestaltString(CFSTR("SerialNumber"));
        NSString *raw = [NSString stringWithFormat:@"%@|%@|%@|%@",
                         udid ?: @"", serial ?: @"", MGMachine(), MGPackageID];
        if (raw.length < 8) {
            NSString *vendor = UIDevice.currentDevice.identifierForVendor.UUIDString ?: @"unknown";
            raw = [NSString stringWithFormat:@"%@|%@|%@", vendor, MGMachine(), MGPackageID];
        }
        NSString *hex = [MGHexSHA256(raw) uppercaseString];
        cached = [NSString stringWithFormat:@"NS-%@-%@-%@-%@",
                  [hex substringWithRange:NSMakeRange(0,4)],
                  [hex substringWithRange:NSMakeRange(4,4)],
                  [hex substringWithRange:NSMakeRange(8,4)],
                  [hex substringWithRange:NSMakeRange(12,4)]];
    });
    return cached;
}

static NSString *MGLicenseToken(void) {
    return MGHexSHA256([NSString stringWithFormat:@"%@|%@|nextsolution-license-v1", MGDeviceID(), MGPackageID]);
}

static NSUserDefaults *MGActivationDefaults(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:MGActivationDomain];
}

static void MGStoreActivation(BOOL active) {
    NSUserDefaults *d = MGActivationDefaults();
    [d setObject:MGDeviceID() forKey:@"licenseDeviceID"];
    [d setObject:(active ? @"Activated" : @"Unactivated") forKey:@"licenseStatusDisplay"];
    [d setBool:active forKey:@"licenseActivated"];
    [d setDouble:NSDate.date.timeIntervalSince1970 forKey:@"licenseLastCheck"];
    [d synchronize];
}

static void MGCheckActivation(void (^completion)(BOOL active, NSError *error)) {
    NSString *urlText = [NSString stringWithFormat:@"%@?t=%.0f", MGRegistryURL, NSDate.date.timeIntervalSince1970];
    NSURL *url = [NSURL URLWithString:urlText];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15.0];
    [request setValue:@"ModuleGlass/1.1.18" forHTTPHeaderField:@"User-Agent"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        BOOL active = NO;
        NSError *finalError = error;
        if (!error && data.length) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&finalError];
            NSArray *list = [json isKindOfClass:NSDictionary.class] ? json[@"active"] : nil;
            if ([list isKindOfClass:NSArray.class]) {
                NSString *wanted = MGLicenseToken().lowercaseString;
                for (id entry in list) {
                    if ([entry isKindOfClass:NSString.class] && [((NSString *)entry).lowercaseString isEqualToString:wanted]) {
                        active = YES;
                        break;
                    }
                }
            }
        }
        MGStoreActivation(active);
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(active, finalError); });
    }];
    [task resume];
}

static NSString *MGURLQueryEscape(NSString *s) {
    NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];
    return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static NSURL *MGCheckoutURL(void) {
    NSString *model = MGMachine();
    NSString *ios = UIDevice.currentDevice.systemVersion ?: @"";
    NSString *url = [NSString stringWithFormat:@"https://nextsolution.cc/license/moduleglass/?device=%@&model=%@&ios=%@",
                     MGURLQueryEscape(MGDeviceID()), MGURLQueryEscape(model), MGURLQueryEscape(ios)];
    return [NSURL URLWithString:url];
}

static UIViewController *MGTopController(UIViewController *root) {
    if (!root) return nil;
    if ([root isKindOfClass:UINavigationController.class]) return MGTopController(((UINavigationController *)root).topViewController);
    if ([root isKindOfClass:UITabBarController.class]) return MGTopController(((UITabBarController *)root).selectedViewController);
    if (root.presentedViewController) return MGTopController(root.presentedViewController);
    return root;
}

static void MGOpenURL(NSURL *url) {
    if (!url) return;
    UIApplication *app = UIApplication.sharedApplication;
    if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [app openURL:url options:@{} completionHandler:nil];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [app openURL:url];
#pragma clang diagnostic pop
    }
}

static BOOL MGIsModuleGlassController(id controller) {
    if (![controller isKindOfClass:UIViewController.class]) return NO;
    NSString *title = ((UIViewController *)controller).title ?: @"";
    if ([title rangeOfString:@"Module Glass" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    @try {
        id specifier = [controller valueForKey:@"specifier"];
        NSString *label = nil;
        if ([specifier respondsToSelector:@selector(name)]) label = [specifier valueForKey:@"name"];
        if (!label.length && [specifier respondsToSelector:@selector(propertyForKey:)]) {
            label = ((id(*)(id,SEL,id))objc_msgSend)(specifier, @selector(propertyForKey:), @"label");
        }
        if ([label rangeOfString:@"Module Glass" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    } @catch (__unused NSException *e) {}
    return NO;
}

static UITableView *MGFindTableInView(UIView *view) {
    if ([view isKindOfClass:UITableView.class]) return (UITableView *)view;
    for (UIView *sub in view.subviews) {
        UITableView *table = MGFindTableInView(sub);
        if (table) return table;
    }
    return nil;
}

static UITableView *MGTableForController(id controller) {
    UITableView *table = nil;
    @try {
        id value = [controller valueForKey:@"table"];
        if ([value isKindOfClass:UITableView.class]) table = value;
    } @catch (__unused NSException *e) {}
    if (!table && [controller isKindOfClass:UIViewController.class]) table = MGFindTableInView(((UIViewController *)controller).view);
    return table;
}

static UIImage *MGSymbol(NSString *name) {
    if (@available(iOS 13.0, *)) return [UIImage systemImageNamed:name];
    return nil;
}

static NSString *MGSymbolForLabel(NSString *label) {
    if ([label containsString:@"Brightness"]) return @"sun.max.fill";
    if ([label containsString:@"Volume Icon Color"]) return @"drop.fill";
    if ([label containsString:@"Volume"]) return @"speaker.wave.2.fill";
    if ([label containsString:@"Connectivity"]) return @"antenna.radiowaves.left.and.right";
    if ([label containsString:@"Now Playing"]) return @"music.note";
    if ([label containsString:@"Screen Mirroring"]) return @"rectangle.on.rectangle";
    if ([label isEqualToString:@"Focus"]) return @"moon.circle.fill";
    if ([label isEqualToString:@"Flashlight"]) return @"flashlight.on.fill";
    if ([label isEqualToString:@"Timer"]) return @"timer";
    if ([label isEqualToString:@"Calculator"]) return @"plus.forwardslash.minus";
    if ([label isEqualToString:@"Camera"]) return @"camera.fill";
    if ([label isEqualToString:@"Orientation Lock"]) return @"lock.rotation";
    if ([label isEqualToString:@"Screen Recording"]) return @"record.circle";
    if ([label isEqualToString:@"Low Power Mode"]) return @"battery.25";
    if ([label isEqualToString:@"Dark Mode"]) return @"moon.fill";
    if ([label isEqualToString:@"Hearing"]) return @"ear.fill";
    if ([label isEqualToString:@"Notes"]) return @"note.text";
    if ([label isEqualToString:@"Home"]) return @"house.fill";
    if ([label isEqualToString:@"Other Modules"]) return @"square.grid.2x2.fill";
    if ([label isEqualToString:@"Remove All Module Images"]) return @"trash.fill";
    if ([label isEqualToString:@"Apply Module Glass"]) return @"checkmark.circle.fill";
    if ([label isEqualToString:@"Respring"]) return @"arrow.clockwise.circle.fill";
    return nil;
}

static void MGUpdateStatusUI(id controller, NSString *text, BOOL active, BOOL checking) {
    UILabel *status = objc_getAssociatedObject(controller, &kMGStatusLabelKey);
    UIButton *button = objc_getAssociatedObject(controller, &kMGLicenseButtonKey);
    if (!status) return;
    status.text = checking ? @"Checking…" : text;
    UIColor *green = [UIColor colorWithRed:0.10 green:0.68 blue:0.35 alpha:1.0];
    UIColor *orange = [UIColor colorWithRed:0.92 green:0.48 blue:0.08 alpha:1.0];
    status.textColor = checking ? UIColor.secondaryLabelColor : (active ? green : orange);
    status.superview.backgroundColor = checking ? [UIColor secondarySystemBackgroundColor] : [(active ? green : orange) colorWithAlphaComponent:0.10];
    if (button) button.accessibilityValue = active ? @"Activated" : @"Unactivated";
}

static void MGPresentLicensePanel(id controller) {
    UIViewController *presenter = [controller isKindOfClass:UIViewController.class] ? controller : MGTopController(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!presenter) return;
    NSUserDefaults *d = MGActivationDefaults();
    BOOL active = [d boolForKey:@"licenseActivated"];
    NSString *status = active ? @"Activated" : @"Unactivated";
    NSString *message = [NSString stringWithFormat:@"Status: %@\nDevice ID: %@\nLicense: %@ lifetime\n\nActivation uses the live Next Solution license registry.", status, MGDeviceID(), MGPrice];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Module Glass License & Device" message:message preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy Device ID" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIPasteboard.generalPasteboard.string = MGDeviceID();
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Buy / Activate — %@", MGPrice] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        MGOpenURL(MGCheckoutURL());
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Check Activation" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        MGUpdateStatusUI(controller, @"Checking…", NO, YES);
        MGCheckActivation(^(BOOL nowActive, NSError *error) {
            MGUpdateStatusUI(controller, nowActive ? @"Activated ✓" : @"Unactivated", nowActive, NO);
            NSString *body = error ? [NSString stringWithFormat:@"Could not check the registry: %@", error.localizedDescription] : (nowActive ? @"This device is activated." : @"This device is not activated yet.");
            UIAlertController *result = [UIAlertController alertControllerWithTitle:@"Module Glass Activation" message:body preferredStyle:UIAlertControllerStyleAlert];
            [result addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [presenter presentViewController:result animated:YES completion:nil];
        });
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *pop = sheet.popoverPresentationController;
    if (pop) {
        pop.sourceView = presenter.view;
        pop.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMaxY(presenter.view.bounds)-20, 1, 1);
    }
    [presenter presentViewController:sheet animated:YES completion:nil];
}

static UIView *MGCreateHeader(id controller, CGFloat width) {
    CGFloat h = 202.0;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, MAX(width, 320), h)];
    header.backgroundColor = UIColor.clearColor;

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 12, MAX(width - 32, 288), 174)];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    card.layer.cornerRadius = 24;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.masksToBounds = YES;

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = card.bounds;
    gradient.colors = @[(id)[UIColor colorWithRed:0.80 green:0.94 blue:1.00 alpha:0.72].CGColor,
                        (id)[UIColor colorWithRed:0.91 green:0.88 blue:1.00 alpha:0.66].CGColor,
                        (id)[UIColor colorWithRed:0.95 green:0.96 blue:1.00 alpha:0.72].CGColor];
    gradient.startPoint = CGPointMake(0, 0);
    gradient.endPoint = CGPointMake(1, 1);
    [card.layer addSublayer:gradient];
    [header addSubview:card];

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(22, 26, 74, 74)];
    NSString *bundlePath = @"/Library/PreferenceBundles/ModuleGlassPrefs.bundle";
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    UIImage *iconImage = [UIImage imageWithContentsOfFile:[bundle pathForResource:@"NextAura-cc-module-backgrounds" ofType:@"png"]];
    icon.image = iconImage ?: MGSymbol(@"square.grid.2x2.fill");
    icon.contentMode = UIViewContentModeScaleAspectFill;
    icon.tintColor = [UIColor colorWithRed:0.34 green:0.39 blue:1.0 alpha:1.0];
    icon.layer.cornerRadius = 18;
    icon.layer.masksToBounds = YES;
    [card addSubview:icon];

    UILabel *brand = [[UILabel alloc] initWithFrame:CGRectMake(112, 24, card.bounds.size.width-220, 22)];
    brand.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    brand.text = @"NEXT SOLUTION";
    brand.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    brand.textColor = [UIColor colorWithRed:0.37 green:0.37 blue:0.49 alpha:1.0];
    [card addSubview:brand];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(112, 48, card.bounds.size.width-220, 36)];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    title.text = @"Module Glass";
    title.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    title.textColor = UIColor.labelColor;
    [card addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(112, 86, card.bounds.size.width-132, 40)];
    subtitle.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    subtitle.text = @"Customize and elevate your\nControl Center experience.";
    subtitle.numberOfLines = 2;
    subtitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    subtitle.textColor = UIColor.secondaryLabelColor;
    [card addSubview:subtitle];

    UIView *badge = [[UIView alloc] initWithFrame:CGRectMake(card.bounds.size.width-112, 24, 92, 32)];
    badge.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    badge.layer.cornerRadius = 16;
    badge.layer.cornerCurve = kCACornerCurveContinuous;
    badge.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [card addSubview:badge];

    UILabel *status = [[UILabel alloc] initWithFrame:badge.bounds];
    status.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    status.textAlignment = NSTextAlignmentCenter;
    status.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    status.text = @"Checking…";
    status.textColor = UIColor.secondaryLabelColor;
    [badge addSubview:status];
    objc_setAssociatedObject(controller, &kMGStatusLabelKey, status, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIButton *license = [UIButton buttonWithType:UIButtonTypeSystem];
    license.frame = CGRectMake(card.bounds.size.width-154, 118, 134, 40);
    license.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    license.layer.cornerRadius = 14;
    license.layer.cornerCurve = kCACornerCurveContinuous;
    license.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    [license setTitle:@"License & Device  ›" forState:UIControlStateNormal];
    license.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [license addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) { MGPresentLicensePanel(controller); }] forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:license];
    objc_setAssociatedObject(controller, &kMGLicenseButtonKey, license, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILabel *version = [[UILabel alloc] initWithFrame:CGRectMake(22, 137, card.bounds.size.width-190, 22)];
    version.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    version.text = @"v1.1.18 • External Host Isolation";
    version.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    version.textColor = UIColor.tertiaryLabelColor;
    [card addSubview:version];

    BOOL cachedActive = [MGActivationDefaults() boolForKey:@"licenseActivated"];
    MGUpdateStatusUI(controller, cachedActive ? @"Activated ✓" : @"Unactivated", cachedActive, YES);
    MGCheckActivation(^(BOOL active, NSError *error) {
        MGUpdateStatusUI(controller, active ? @"Activated ✓" : @"Unactivated", active, NO);
    });
    return header;
}

static void MGInstallHeader(id controller) {
    if (!MGIsModuleGlassController(controller)) return;
    UITableView *table = MGTableForController(controller);
    if (!table) return;
    table.backgroundColor = UIColor.systemGroupedBackgroundColor;
    UIView *existing = objc_getAssociatedObject(controller, &kMGHeaderKey);
    if (!existing || fabs(existing.bounds.size.width - table.bounds.size.width) > 2.0) {
        UIView *header = MGCreateHeader(controller, table.bounds.size.width);
        table.tableHeaderView = header;
        objc_setAssociatedObject(controller, &kMGHeaderKey, header, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if ([controller isKindOfClass:UIViewController.class]) ((UIViewController *)controller).title = @"Module Glass";
}

static void MG_viewDidLoad(id self, SEL _cmd) {
    if (gOrigViewDidLoad) ((void(*)(id,SEL))gOrigViewDidLoad)(self,_cmd);
    dispatch_async(dispatch_get_main_queue(), ^{ MGInstallHeader(self); });
}

static void MG_viewWillAppear(id self, SEL _cmd, BOOL animated) {
    if (gOrigViewWillAppear) ((void(*)(id,SEL,BOOL))gOrigViewWillAppear)(self,_cmd,animated);
    dispatch_async(dispatch_get_main_queue(), ^{ MGInstallHeader(self); });
}

static void MG_willDisplayCell(id self, SEL _cmd, UITableView *table, UITableViewCell *cell, NSIndexPath *indexPath) {
    if (gOrigWillDisplayCell) ((void(*)(id,SEL,UITableView*,UITableViewCell*,NSIndexPath*))gOrigWillDisplayCell)(self,_cmd,table,cell,indexPath);
    if (!MGIsModuleGlassController(self)) return;
    NSString *label = cell.textLabel.text ?: @"";
    NSString *symbolName = MGSymbolForLabel(label);
    if (symbolName.length) {
        UIImage *image = MGSymbol(symbolName);
        if (image) {
            cell.imageView.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            cell.imageView.tintColor = [UIColor colorWithRed:0.36 green:0.45 blue:0.66 alpha:0.80];
        }
    }
    if ([label isEqualToString:@"Remove All Module Images"]) {
        cell.textLabel.textColor = UIColor.systemRedColor;
        cell.imageView.tintColor = UIColor.systemRedColor;
    }
}

static void MGInstallHooks(void) {
    Class cls = NSClassFromString(@"AuraCategoryListController");
    if (!cls || objc_getAssociatedObject(cls, &kMGInstalledKey)) return;
    objc_setAssociatedObject(cls, &kMGInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    Method m = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (m) { gOrigViewDidLoad = method_getImplementation(m); class_replaceMethod(cls, @selector(viewDidLoad), (IMP)MG_viewDidLoad, method_getTypeEncoding(m)); }
    m = class_getInstanceMethod(cls, @selector(viewWillAppear:));
    if (m) { gOrigViewWillAppear = method_getImplementation(m); class_replaceMethod(cls, @selector(viewWillAppear:), (IMP)MG_viewWillAppear, method_getTypeEncoding(m)); }
    SEL willDisplay = @selector(tableView:willDisplayCell:forRowAtIndexPath:);
    m = class_getInstanceMethod(cls, willDisplay);
    if (m) { gOrigWillDisplayCell = method_getImplementation(m); class_replaceMethod(cls, willDisplay, (IMP)MG_willDisplayCell, method_getTypeEncoding(m)); }
}

__attribute__((constructor)) static void ModuleGlassModernPrefsInit(void) {
    @autoreleasepool {
        [NSNotificationCenter.defaultCenter addObserverForName:NSBundleDidLoadNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            MGInstallHooks();
        }];
        dispatch_async(dispatch_get_main_queue(), ^{ MGInstallHooks(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MGInstallHooks(); });
    }
}
