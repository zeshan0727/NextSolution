#import <UIKit/UIKit.h>
#import "PhoneAuraManager.h"

static BOOL PAIsPhoneProcess(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.mobilephone"];
}

%hook UITabBarController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (PAIsPhoneProcess()) {
        [[PhoneAuraManager sharedManager] controllerDidAppear:self];
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (PAIsPhoneProcess()) {
        [[PhoneAuraManager sharedManager] controllerDidLayout:self];
    }
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    %orig;
    if (PAIsPhoneProcess()) {
        [[PhoneAuraManager sharedManager] tabSelectionChanged:self];
    }
}

- (void)setSelectedViewController:(UIViewController *)selectedViewController {
    %orig;
    if (PAIsPhoneProcess()) {
        [[PhoneAuraManager sharedManager] tabSelectionChanged:self];
    }
}

%end

/* Re-apply the root stage after Apple finishes closing a contact detail. */
%hook UINavigationController

- (void)viewDidShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    %orig;
    if (PAIsPhoneProcess() && self.tabBarController) {
        __weak UITabBarController *weakTab = self.tabBarController;
        dispatch_async(dispatch_get_main_queue(), ^{
            UITabBarController *tab = weakTab;
            if (tab) {
                [[PhoneAuraManager sharedManager] controllerDidAppear:tab];
            }
        });
    }
}

%end

%ctor {
    if (!PAIsPhoneProcess()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [PhoneAuraManager sharedManager];
    });
}
