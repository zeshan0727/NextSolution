#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>

static NSString * const LGTPrefsDomain = @"com.nextsolution.lockglyphtime";
static CFStringRef const LGTReloadNotification = CFSTR("com.nextsolution.lockglyphtime/ReloadPrefs");

@interface LGTListController : PSListController <UIColorPickerViewControllerDelegate>
@property(nonatomic, copy) NSString *activeColorKey;
@property(nonatomic, copy) NSString *activeColorDefault;
@end

@implementation LGTListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (UIColor *)lgt_colorFromHex:(NSString *)hex fallback:(UIColor *)fallback {
    if (![hex isKindOfClass:NSString.class]) return fallback;
    NSString *clean = [[hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([clean hasPrefix:@"#"]) clean = [clean substringFromIndex:1];
    if (clean.length != 6 && clean.length != 8) return fallback;
    unsigned long long value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexLongLong:&value] || !scanner.isAtEnd) return fallback;
    CGFloat r,g,b,a = 1.0;
    if (clean.length == 8) {
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

- (NSString *)lgt_hexFromColor:(UIColor *)color {
    CGFloat r=0,g=0,b=0,a=1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 1.0;
        if ([color getWhite:&white alpha:&a]) r = g = b = white;
        else { r = g = b = 1.0; a = 1.0; }
    }
    return [NSString stringWithFormat:@"#%02X%02X%02X%02X",
            (int)lrint(r*255.0),(int)lrint(g*255.0),(int)lrint(b*255.0),(int)lrint(a*255.0)];
}

- (void)lgt_presentColorPickerForKey:(NSString *)key defaultHex:(NSString *)defaultHex title:(NSString *)title {
    self.activeColorKey = key;
    self.activeColorDefault = defaultHex;
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain];
    NSString *saved = [prefs stringForKey:key] ?: defaultHex;

    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.delegate = self;
    picker.selectedColor = [self lgt_colorFromHex:saved fallback:UIColor.whiteColor];
    picker.supportsAlpha = YES;
    picker.title = title;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)lgt_saveSelectedColor:(UIColor *)color {
    if (!self.activeColorKey.length || !color) return;
    NSString *hex = [self lgt_hexFromColor:color];
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:LGTPrefsDomain];
    [prefs setObject:hex forKey:self.activeColorKey];
    [prefs synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         LGTReloadNotification,
                                         NULL,
                                         NULL,
                                         true);
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {
    [self lgt_saveSelectedColor:viewController.selectedColor];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {
    [self lgt_saveSelectedColor:viewController.selectedColor];
    self.activeColorKey = nil;
    self.activeColorDefault = nil;
}

- (void)openTimeColorPicker { [self lgt_presentColorPickerForKey:@"timeColor" defaultHex:@"#FFFFFFFF" title:@"Time Color"]; }
- (void)openTimeShadowColorPicker { [self lgt_presentColorPickerForKey:@"timeShadowColor" defaultHex:@"#000000FF" title:@"Time Shadow Color"]; }
- (void)openDateColorPicker { [self lgt_presentColorPickerForKey:@"dateColor" defaultHex:@"#FFFFFFFF" title:@"Date Color"]; }
- (void)openDateShadowColorPicker { [self lgt_presentColorPickerForKey:@"dateShadowColor" defaultHex:@"#000000FF" title:@"Date Shadow Color"]; }
- (void)openIconColorPicker { [self lgt_presentColorPickerForKey:@"iconColor" defaultHex:@"#FFFFFFFF" title:@"Icon Color"]; }
- (void)openIconShadowColorPicker { [self lgt_presentColorPickerForKey:@"shadowColor" defaultHex:@"#000000FF" title:@"Icon Shadow Color"]; }

@end
