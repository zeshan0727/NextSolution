#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

static CFStringRef const MGPrefsDomain = CFSTR("com.nextsolution.unlockvibrate");
static CFStringRef const MGVolumeIconColorKey = CFSTR("CCModuleVolumeIconColor");
static CFStringRef const MGVolumeIconColorEnabledKey = CFSTR("CCModuleVolumeIconColorEnabled");
static const void *MGPickerDelegateKey = &MGPickerDelegateKey;

static NSString *MGHexFromColor(UIColor *color) {
    CGFloat r = 1.0, g = 1.0, b = 1.0, a = 1.0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w = 1.0;
        if ([color getWhite:&w alpha:&a]) r = g = b = w;
    }
    NSInteger ri = (NSInteger)llround(MAX(0.0, MIN(1.0, r)) * 255.0);
    NSInteger gi = (NSInteger)llround(MAX(0.0, MIN(1.0, g)) * 255.0);
    NSInteger bi = (NSInteger)llround(MAX(0.0, MIN(1.0, b)) * 255.0);
    return [NSString stringWithFormat:@"#%02lX%02lX%02lX", (long)ri, (long)gi, (long)bi];
}

static UIColor *MGColorFromHex(NSString *input) {
    if (![input isKindOfClass:NSString.class]) return UIColor.whiteColor;
    NSString *hex = [[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    if (hex.length != 6 && hex.length != 8) return UIColor.whiteColor;
    unsigned int value = 0;
    if (![[NSScanner scannerWithString:hex] scanHexInt:&value]) return UIColor.whiteColor;
    CGFloat r, g, b, a = 1.0;
    if (hex.length == 8) {
        r = ((value >> 24) & 0xFF) / 255.0;
        g = ((value >> 16) & 0xFF) / 255.0;
        b = ((value >> 8) & 0xFF) / 255.0;
        a = (value & 0xFF) / 255.0;
    } else {
        r = ((value >> 16) & 0xFF) / 255.0;
        g = ((value >> 8) & 0xFF) / 255.0;
        b = (value & 0xFF) / 255.0;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static NSString *MGStoredVolumeColor(void) {
    CFPreferencesAppSynchronize(MGPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(MGVolumeIconColorKey, MGPrefsDomain);
    if (!value) return @"#FFFFFF";
    id bridged = CFBridgingRelease(value);
    return [bridged isKindOfClass:NSString.class] ? bridged : @"#FFFFFF";
}

static void MGSaveVolumeColor(UIColor *color) {
    NSString *hex = MGHexFromColor(color ?: UIColor.whiteColor);
    CFPreferencesSetAppValue(MGVolumeIconColorKey, (__bridge CFStringRef)hex, MGPrefsDomain);
    CFPreferencesSetAppValue(MGVolumeIconColorEnabledKey, kCFBooleanTrue, MGPrefsDomain);
    CFPreferencesAppSynchronize(MGPrefsDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.nextsolution.unlockvibrate/preferences.changed"),
                                         NULL, NULL, true);
}

@interface MGVolumeColorPickerDelegate : NSObject <UIColorPickerViewControllerDelegate>
@property (nonatomic, weak) UIViewController *presenter;
@end

@implementation MGVolumeColorPickerDelegate
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    MGSaveVolumeColor(viewController.selectedColor);
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    MGSaveVolumeColor(viewController.selectedColor);
}
@end

static void MGChooseVolumeIconColor(id self, SEL _cmd, id specifier) {
    if (![self isKindOfClass:UIViewController.class]) return;
    UIViewController *presenter = (UIViewController *)self;
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.title = @"Volume Icon Color";
    picker.supportsAlpha = NO;
    picker.selectedColor = MGColorFromHex(MGStoredVolumeColor());
    MGVolumeColorPickerDelegate *delegate = [MGVolumeColorPickerDelegate new];
    delegate.presenter = presenter;
    picker.delegate = delegate;
    objc_setAssociatedObject(picker, MGPickerDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [presenter presentViewController:picker animated:YES completion:nil];
}

static void MGInstallVolumeColorAction(void) {
    Class cls = NSClassFromString(@"AuraCategoryListController");
    if (!cls) return;
    SEL selector = NSSelectorFromString(@"chooseVolumeIconColor:");
    if (!class_getInstanceMethod(cls, selector)) {
        class_addMethod(cls, selector, (IMP)MGChooseVolumeIconColor, "v@:@");
    }
}

@interface MGPrefsBundleObserver : NSObject
+ (instancetype)shared;
- (void)bundleDidLoad:(NSNotification *)notification;
@end

@implementation MGPrefsBundleObserver
+ (instancetype)shared {
    static MGPrefsBundleObserver *observer;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ observer = [MGPrefsBundleObserver new]; });
    return observer;
}
- (void)bundleDidLoad:(NSNotification *)notification {
    MGInstallVolumeColorAction();
}
@end

__attribute__((constructor)) static void MGPrefsExtensionInit(void) {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserver:[MGPrefsBundleObserver shared]
                                                 selector:@selector(bundleDidLoad:)
                                                     name:NSBundleDidLoadNotification
                                                   object:nil];
        dispatch_async(dispatch_get_main_queue(), ^{ MGInstallVolumeColorAction(); });
    }
}
