#import "PAContactsRootBridge.h"
#import "PhoneAuraManager.h"

@interface PhoneAuraManager (PAContactsRootPrivate)
- (void)installDock:(UITabBarController *)tabController;
- (void)installHeader:(UITabBarController *)tabController;
- (void)configureChrome:(UITabBarController *)tabController animated:(BOOL)animated;
- (void)installSelectedSurface:(UITabBarController *)tabController;
@end

static BOOL PAContactTextContains(NSString *value, NSArray<NSString *> *needles) {
    NSString *lower = value.lowercaseString ?: @"";
    for (NSString *needle in needles) {
        if ([lower containsString:needle.lowercaseString]) return YES;
    }
    return NO;
}

void PAForceContactsRootSurfaceIfNeeded(UIViewController *controller) {
    if (!controller) return;

    UITabBarController *tabController = controller.tabBarController;
    if (!tabController || tabController.selectedIndex != 2) return;

    UINavigationController *navigationController = [tabController.selectedViewController isKindOfClass:[UINavigationController class]]
        ? (UINavigationController *)tabController.selectedViewController : nil;
    UIViewController *top = navigationController ? navigationController.topViewController : tabController.selectedViewController;
    if (!top || top != controller || !top.isViewLoaded) return;

    NSString *title = top.title ?: top.navigationItem.title ?: @"";
    NSString *className = NSStringFromClass(top.class);
    BOOL looksLikeContactsRoot = PAContactTextContains(title, @[@"contacts", @"all contacts"])
        || PAContactTextContains(className, @[@"contactlist", @"contactscontroller", @"cncontactlist"]);
    if (!looksLikeContactsRoot) return;

    PhoneAuraManager *manager = [PhoneAuraManager sharedManager];
    BOOL enabled = [[manager valueForKey:@"enabled"] boolValue];
    BOOL fullContacts = [[manager valueForKey:@"fullContacts"] boolValue];
    if (!enabled || !fullContacts) return;

    [manager installDock:tabController];
    [manager installHeader:tabController];
    [manager configureChrome:tabController animated:NO];
    [manager installSelectedSurface:tabController];

    UIView *header = [manager valueForKey:@"header"];
    UIView *dock = [manager valueForKey:@"dock"];
    if (header.superview) [header.superview bringSubviewToFront:header];
    if (dock.superview) [dock.superview bringSubviewToFront:dock];
}
