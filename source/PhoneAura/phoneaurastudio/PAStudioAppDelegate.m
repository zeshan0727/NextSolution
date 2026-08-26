#import "PAStudioAppDelegate.h"
#import "PAStudioRootController.h"

@implementation PAStudioAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    PAStudioRootController *root = [[PAStudioRootController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:root];
    navigationController.navigationBar.prefersLargeTitles = NO;
    navigationController.navigationBar.tintColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.38 alpha:1.0];
    navigationController.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window.rootViewController = navigationController;
    self.window.backgroundColor = UIColor.blackColor;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
