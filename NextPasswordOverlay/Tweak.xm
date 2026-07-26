#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface UIKeyboardDockView : UIView
@end

static const void *NPButtonKey = &NPButtonKey;
static NSString * const NPStorePath = @"/var/mobile/Library/Preferences/com.nextsolution.nextpasswordoverlay.plist";

@interface UIResponder (NPFirstResponder)
+ (id)np_currentFirstResponder;
@end

static __weak id npFirstResponder;
@implementation UIResponder (NPFirstResponder)
+ (id)np_currentFirstResponder {
    npFirstResponder = nil;
    [[UIApplication sharedApplication] sendAction:@selector(np_captureFirstResponder:) to:nil from:nil forEvent:nil];
    return npFirstResponder;
}
- (void)np_captureFirstResponder:(id)sender { npFirstResponder = self; }
@end

static UIViewController *NPTopController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (candidate.isKeyWindow) { window = candidate; break; }
                if (!window && !candidate.hidden) window = candidate;
            }
        }
        if (window.isKeyWindow) break;
    }
    if (!window) return nil;
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    if ([controller isKindOfClass:UINavigationController.class]) controller = ((UINavigationController *)controller).visibleViewController;
    if ([controller isKindOfClass:UITabBarController.class]) controller = ((UITabBarController *)controller).selectedViewController;
    return controller;
}

static NSString *NPCleanSite(NSString *site) {
    NSCharacterSet *letters = NSCharacterSet.letterCharacterSet;
    NSMutableString *clean = [NSMutableString string];
    for (NSUInteger i = 0; i < site.length; i++) {
        unichar c = [site characterAtIndex:i];
        if ([letters characterIsMember:c]) [clean appendFormat:@"%C", c];
    }
    return clean.lowercaseString;
}

static NSString *NPPasswordForSite(NSString *site) {
    NSString *clean = NPCleanSite(site ?: @"");
    if (clean.length == 0) return @"";
    unichar first = [[clean uppercaseString] characterAtIndex:0];
    unichar last = [[clean uppercaseString] characterAtIndex:clean.length - 1];
    NSInteger firstPos = (first >= 'A' && first <= 'Z') ? first - 'A' + 1 : 0;
    NSInteger lastPos = (last >= 'A' && last <= 'Z') ? last - 'A' + 1 : 0;
    return [NSString stringWithFormat:@"MpMr@%lu%02ld%02ld", (unsigned long)clean.length, (long)firstPos, (long)lastPos];
}

static NSMutableDictionary *NPStore(void) {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:NPStorePath];
    return saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
}

static void NPInsert(NSString *text) {
    id responder = [UIResponder np_currentFirstResponder];
    if ([responder respondsToSelector:@selector(insertText:)]) {
        [responder insertText:text];
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
    }
}

static void NPShowSaved(void) {
    UIViewController *top = NPTopController();
    if (!top) return;
    NSDictionary *store = NPStore();
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Saved Passwords" message:store.count ? @"Tap a website to insert its password." : @"No passwords saved from the keyboard yet." preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *sites = [[store allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSUInteger limit = MIN((NSUInteger)12, sites.count);
    for (NSUInteger i = 0; i < limit; i++) {
        NSString *site = sites[i];
        NSString *password = store[site];
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@  —  %@", site, password] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NPInsert(password);
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:sheet animated:YES completion:nil];
}

static void NPShowGenerator(void) {
    UIViewController *top = NPTopController();
    if (!top) return;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Next Password" message:@"Generate from a website name or insert a saved password." preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"Generate Password" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Generate Password" message:@"Rule: MpMr@ + length + first letter position + last letter position" preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = @"Website name, e.g. Google";
            field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Insert" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *insertAction) {
            NSString *site = alert.textFields.firstObject.text ?: @"";
            NSString *password = NPPasswordForSite(site);
            if (password.length) NPInsert(password);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Save & Insert" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *saveAction) {
            NSString *site = alert.textFields.firstObject.text ?: @"";
            NSString *password = NPPasswordForSite(site);
            if (!password.length) return;
            NSMutableDictionary *store = NPStore();
            store[site.capitalizedString] = password;
            [store writeToFile:NPStorePath atomically:YES];
            NPInsert(password);
        }]];
        UIViewController *presenter = NPTopController();
        if (presenter) [presenter presentViewController:alert animated:YES completion:nil];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Saved Passwords" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { NPShowSaved(); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:menu animated:YES completion:nil];
}

%hook UIKeyboardDockView
- (void)layoutSubviews {
    %orig;
    UIButton *button = objc_getAssociatedObject(self, NPButtonKey);
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.backgroundColor = [UIColor colorWithRed:0.05 green:0.45 blue:1 alpha:0.95];
        button.tintColor = UIColor.whiteColor;
        button.layer.cornerRadius = 18.0;
        [button setImage:[UIImage systemImageNamed:@"lock.shield.fill"] forState:UIControlStateNormal];
        button.accessibilityLabel = @"Next Password";
        [button addTarget:nil action:@selector(np_openNextPassword) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:button];
        objc_setAssociatedObject(self, NPButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat size = 36.0;
    button.frame = CGRectMake(self.bounds.size.width - size - 8.0, 5.0, size, size);
    [self bringSubviewToFront:button];
}
%end

%hook NSObject
%new
- (void)np_openNextPassword { NPShowGenerator(); }
%end
