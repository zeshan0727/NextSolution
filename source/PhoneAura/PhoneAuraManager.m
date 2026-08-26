#import "PhoneAuraManager.h"
#import "PAConceptDUI.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static CFStringRef const PAPreferencesDomain = CFSTR("com.zeshan.phoneaura");
static CFStringRef const PAPreferencesChanged = CFSTR("com.zeshan.phoneaura/preferences.changed");

static const void *PAHeaderKey = &PAHeaderKey;
static const void *PADockKey = &PADockKey;
static const void *PACardKey = &PACardKey;
static const void *PABackgroundKey = &PABackgroundKey;
static const void *PAKeypadKey = &PAKeypadKey;
static const void *PAShortcutsKey = &PAShortcutsKey;

static void PAPreferencesDidChange(CFNotificationCenterRef center,
                                   void *observer,
                                   CFStringRef name,
                                   const void *object,
                                   CFDictionaryRef userInfo);

static id PAReadPreference(NSString *key) {
    CFPreferencesAppSynchronize(PAPreferencesDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, PAPreferencesDomain);
    return CFBridgingRelease(value);
}

static BOOL PABoolPreference(NSString *key, BOOL fallback) {
    id value = PAReadPreference(key);
    return value ? [value boolValue] : fallback;
}

static CGFloat PAFloatPreference(NSString *key, CGFloat fallback) {
    id value = PAReadPreference(key);
    return value ? [value doubleValue] : fallback;
}

static NSArray<UIView *> *PAAllSubviews(UIView *view) {
    if (!view) return @[];
    NSMutableArray<UIView *> *result = [NSMutableArray array];
    for (UIView *subview in view.subviews) {
        [result addObject:subview];
        [result addObjectsFromArray:PAAllSubviews(subview)];
    }
    return result;
}

static BOOL PAViewIsDescendantOf(UIView *view, UIView *ancestor) {
    if (!view || !ancestor) return NO;
    UIView *cursor = view;
    while (cursor) {
        if (cursor == ancestor) return YES;
        cursor = cursor.superview;
    }
    return NO;
}

static UIViewController *PATabTop(UITabBarController *tabController) {
    UIViewController *selected = tabController.selectedViewController;
    if ([selected isKindOfClass:[UINavigationController class]]) {
        return ((UINavigationController *)selected).topViewController;
    }
    return selected;
}

static UINavigationController *PASelectedNavigationController(UITabBarController *tabController) {
    UIViewController *selected = tabController.selectedViewController;
    return [selected isKindOfClass:[UINavigationController class]] ? (UINavigationController *)selected : nil;
}

static UITabBarController *PAFindTabController(UIViewController *controller) {
    UIViewController *cursor = controller;
    while (cursor) {
        if ([cursor isKindOfClass:[UITabBarController class]]) {
            return (UITabBarController *)cursor;
        }
        if (cursor.tabBarController) {
            return cursor.tabBarController;
        }
        cursor = cursor.parentViewController ?: cursor.presentingViewController;
    }

    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        UIViewController *root = window.rootViewController;
        if ([root isKindOfClass:[UITabBarController class]]) {
            return (UITabBarController *)root;
        }
        for (UIViewController *child in root.childViewControllers) {
            if ([child isKindOfClass:[UITabBarController class]]) {
                return (UITabBarController *)child;
            }
        }
    }
    return nil;
}

static BOOL PAContainsAny(NSString *value, NSArray<NSString *> *needles) {
    NSString *lower = value.lowercaseString ?: @"";
    for (NSString *needle in needles) {
        if ([lower containsString:needle.lowercaseString]) return YES;
    }
    return NO;
}

static BOOL PAIsStudioSurface(UITabBarController *tabController) {
    if (!tabController) return NO;
    UIViewController *top = PATabTop(tabController);
    if (!top) return NO;

    UINavigationController *navigationController = PASelectedNavigationController(tabController);
    if (!navigationController || navigationController.viewControllers.count <= 1) {
        return YES;
    }

    NSUInteger index = MIN(tabController.selectedIndex, 4);
    NSString *title = top.title ?: top.navigationItem.title ?: @"";
    NSString *className = NSStringFromClass(top.class);

    if (index == 2 && (PAContainsAny(title, @[@"contacts", @"all contacts"]) ||
                       PAContainsAny(className, @[@"contactlist", @"contactscontroller"]))) {
        return YES;
    }
    if (index == 3 && PAContainsAny(className, @[@"dialer", @"keypad", @"phonepad"])) {
        return YES;
    }
    if (index == 1 && PAContainsAny(title, @[@"recents", @"all", @"missed"])) {
        return YES;
    }
    if (index == 4 && PAContainsAny(title, @[@"voicemail", @"inbox"])) {
        return YES;
    }
    return NO;
}

static void PAStyleLabelsInView(UIView *view, UIColor *accent) {
    for (UIView *subview in PAAllSubviews(view)) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            if (label.hidden || label.alpha < 0.05) continue;
            NSString *text = label.text ?: @"";
            if (PAContainsAny(text, @[@"missed", @"declined"])) {
                label.textColor = PAColorHex(0xFF5B61, 1.0);
            } else if (label.font.pointSize >= 15.0 || (label.font.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold)) {
                label.textColor = UIColor.whiteColor;
            } else {
                label.textColor = PAColorHex(0xA7B2CA, 1.0);
            }
        } else if ([subview isKindOfClass:[UIImageView class]]) {
            UIImageView *imageView = (UIImageView *)subview;
            if (imageView.image && CGRectGetWidth(imageView.bounds) >= 28.0 && CGRectGetWidth(imageView.bounds) <= 72.0) {
                imageView.layer.cornerRadius = CGRectGetWidth(imageView.bounds) / 2.0;
                imageView.clipsToBounds = YES;
            }
        } else if ([subview isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton *)subview;
            if (button.tintColor && CGColorGetAlpha(button.tintColor.CGColor) > 0.05) {
                button.tintColor = accent;
            }
        }
    }
}

@interface PhoneAuraManager ()
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL haptics;
@property(nonatomic) BOOL animations;
@property(nonatomic) BOOL forceDark;
@property(nonatomic) BOOL showSubtitles;
@property(nonatomic) BOOL showShortcuts;
@property(nonatomic) BOOL styleKeypad;
@property(nonatomic) CGFloat cardOpacity;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic,weak) UITabBarController *tabController;
@property(nonatomic,strong) PAStudioHeaderView *header;
@property(nonatomic,strong) PAStudioDock *dock;
@end

@implementation PhoneAuraManager

+ (instancetype)sharedManager {
    static PhoneAuraManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

- (instancetype)init {
    if ((self = [super init])) {
        [self reloadPreferences];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)self,
                                        PAPreferencesDidChange,
                                        PAPreferencesChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (__bridge const void *)self,
                                       PAPreferencesChanged,
                                       NULL);
}

static void PAPreferencesDidChange(CFNotificationCenterRef center,
                                   void *observer,
                                   CFStringRef name,
                                   const void *object,
                                   CFDictionaryRef userInfo) {
    PhoneAuraManager *manager = (__bridge PhoneAuraManager *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [manager reloadPreferences];
    });
}

- (void)reloadPreferences {
    self.enabled = PABoolPreference(@"enabled", YES);
    self.haptics = PABoolPreference(@"haptics", YES);
    self.animations = PABoolPreference(@"animations", YES);
    self.forceDark = PABoolPreference(@"forceDark", YES);
    self.showSubtitles = PABoolPreference(@"showSubtitles", YES);
    self.showShortcuts = PABoolPreference(@"showShortcuts", YES);
    self.styleKeypad = PABoolPreference(@"styleKeypad", YES);
    self.cardOpacity = MAX(0.60, MIN(PAFloatPreference(@"cardOpacity", 0.96), 1.0));
    self.cornerRadius = MAX(10.0, MIN(PAFloatPreference(@"cornerRadius", 16.0), 24.0));

    if (!self.tabController) return;
    if (self.enabled) {
        [self applyToTabController:self.tabController animated:NO];
    } else {
        [self restoreTabController:self.tabController];
    }
}

- (void)controllerDidAppear:(UIViewController *)controller {
    UITabBarController *tabController = PAFindTabController(controller);
    if (!tabController) return;
    self.tabController = tabController;
    if (self.enabled) {
        [self applyToTabController:tabController animated:NO];
    } else {
        [self restoreTabController:tabController];
    }
}

- (void)controllerDidLayout:(UIViewController *)controller {
    if (!self.enabled || !self.tabController) return;
    UITabBarController *tabController = PAFindTabController(controller);
    if (tabController != self.tabController) return;
    [self applyToTabController:tabController animated:NO];
}

- (void)tabSelectionChanged:(UITabBarController *)tabController {
    self.tabController = tabController;
    if (!self.enabled) {
        [self restoreTabController:tabController];
        return;
    }
    [self applyToTabController:tabController animated:YES];
}

- (void)applyToTabController:(UITabBarController *)tabController animated:(BOOL)animated {
    if (!tabController.view.window && !tabController.view.superview) return;
    if (self.forceDark) tabController.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    BOOL studioSurface = PAIsStudioSurface(tabController);
    if (!studioSurface) {
        [self showSystemNavigationForTabController:tabController];
        return;
    }

    [self installDockForTabController:tabController];
    [self installHeaderForTabController:tabController];
    [self configureStudioChromeForTabController:tabController animated:animated];
    [self styleVisibleSurfaceForTabController:tabController];
}

- (void)installDockForTabController:(UITabBarController *)tabController {
    UITabBar *tabBar = tabController.tabBar;
    if (!tabBar) return;

    PAStudioDock *dock = objc_getAssociatedObject(tabBar, PADockKey);
    if (!dock) {
        dock = [[PAStudioDock alloc] init];
        __weak typeof(self) weakSelf = self;
        __weak UITabBarController *weakTab = tabController;
        dock.selectionHandler = ^(NSUInteger index) {
            __strong typeof(weakSelf) self = weakSelf;
            UITabBarController *strongTab = weakTab;
            if (!self || !strongTab || index >= strongTab.viewControllers.count) return;

            if (self.haptics) {
                UISelectionFeedbackGenerator *generator = [[UISelectionFeedbackGenerator alloc] init];
                [generator selectionChanged];
            }
            strongTab.selectedIndex = index;
            [self applyToTabController:strongTab animated:YES];
        };
        [tabBar addSubview:dock];
        objc_setAssociatedObject(tabBar, PADockKey, dock, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    self.dock = dock;
    dock.hidden = NO;
    dock.frame = CGRectInset(tabBar.bounds, 8.0, 4.0);
    dock.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    tabBar.backgroundImage = [UIImage new];
    tabBar.shadowImage = [UIImage new];
    tabBar.backgroundColor = UIColor.clearColor;
    tabBar.translucent = YES;

    for (UIView *subview in tabBar.subviews) {
        if (subview == dock) continue;
        NSString *className = NSStringFromClass(subview.class);
        if ([subview isKindOfClass:[UIControl class]] || [className containsString:@"Button"]) {
            subview.alpha = 0.0;
            subview.userInteractionEnabled = NO;
        }
    }
    [tabBar bringSubviewToFront:dock];
}

- (void)installHeaderForTabController:(UITabBarController *)tabController {
    PAStudioHeaderView *header = objc_getAssociatedObject(tabController.view, PAHeaderKey);
    if (!header) {
        header = [[PAStudioHeaderView alloc] init];
        __weak typeof(self) weakSelf = self;
        header.actionHandler = ^{
            [weakSelf performHeaderAction];
        };
        [tabController.view addSubview:header];
        objc_setAssociatedObject(tabController.view, PAHeaderKey, header, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    self.header = header;
    header.hidden = NO;
    CGFloat safeTop = tabController.view.safeAreaInsets.top;
    header.frame = CGRectMake(20.0, safeTop + 2.0, CGRectGetWidth(tabController.view.bounds) - 40.0, 66.0);
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    [tabController.view bringSubviewToFront:header];
}

- (void)configureStudioChromeForTabController:(UITabBarController *)tabController animated:(BOOL)animated {
    NSUInteger index = MIN(tabController.selectedIndex, 4);
    [self.dock updateSelectedIndex:index animated:(animated && self.animations)];

    NSArray<NSString *> *titles = @[@"Favorites", @"Recents", @"Contacts", @"Keypad", @"Voicemail"];
    NSArray<NSString *> *subtitles = @[@"Your people, one tap away.",
                                       @"Your call history at a glance.",
                                       @"All your connections.",
                                       @"Dial with confidence.",
                                       @"Messages that matter."];
    NSArray<NSString *> *icons = @[@"plus", @"line.3.horizontal.decrease", @"magnifyingglass", @"ellipsis", @"pencil"];

    [self.header configureTitle:titles[index]
                       subtitle:subtitles[index]
                           icon:icons[index]
                         accent:PAAccentForIndex(index)
                   showSubtitle:self.showSubtitles];

    UINavigationController *navigationController = PASelectedNavigationController(tabController);
    UIViewController *top = PATabTop(tabController);
    if (navigationController) navigationController.navigationBarHidden = YES;
    top.additionalSafeAreaInsets = UIEdgeInsetsMake(78.0, 0, 0, 0);

    if (index == 3 && self.styleKeypad) {
        [self installCustomKeypadForController:top];
    } else {
        [self hideCustomKeypadForController:top];
    }

    [tabController.view bringSubviewToFront:self.header];
    [tabController.tabBar bringSubviewToFront:self.dock];
}

- (void)styleVisibleSurfaceForTabController:(UITabBarController *)tabController {
    UIViewController *top = PATabTop(tabController);
    if (!top || !top.isViewLoaded) return;
    NSUInteger index = MIN(tabController.selectedIndex, 4);
    UIColor *accent = PAAccentForIndex(index);

    CAGradientLayer *background = objc_getAssociatedObject(top.view, PABackgroundKey);
    if (!background) {
        background = [CAGradientLayer layer];
        background.startPoint = CGPointMake(0.0, 0.0);
        background.endPoint = CGPointMake(1.0, 1.0);
        [top.view.layer insertSublayer:background atIndex:0];
        objc_setAssociatedObject(top.view, PABackgroundKey, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    background.frame = top.view.bounds;
    background.colors = @[(id)[accent colorWithAlphaComponent:0.14].CGColor,
                          (id)PAColorHex(0x08132B, 1.0).CGColor,
                          (id)PAColorHex(0x030712, 1.0).CGColor];
    background.locations = @[@0.0, @0.34, @1.0];
    top.view.backgroundColor = PAColorHex(0x030712, 1.0);

    for (UIView *view in PAAllSubviews(top.view)) {
        if ([view isKindOfClass:[UISearchBar class]]) {
            [self styleSearchBar:(UISearchBar *)view accent:accent];
        } else if ([view isKindOfClass:[UITableView class]]) {
            [self styleTableView:(UITableView *)view tabIndex:index];
        } else if ([view isKindOfClass:[UICollectionView class]]) {
            [self styleCollectionView:(UICollectionView *)view tabIndex:index];
        } else if ([view isKindOfClass:[UIScrollView class]]) {
            view.backgroundColor = UIColor.clearColor;
        }
    }

    [self.header.superview bringSubviewToFront:self.header];
    [self.dock.superview bringSubviewToFront:self.dock];
}

- (void)styleSearchBar:(UISearchBar *)searchBar accent:(UIColor *)accent {
    searchBar.searchBarStyle = UISearchBarStyleMinimal;
    UITextField *field = searchBar.searchTextField;
    field.backgroundColor = PAColorHex(0x17213D, 0.96);
    field.textColor = UIColor.whiteColor;
    field.tintColor = accent;
    field.layer.cornerRadius = 14.0;
    field.layer.cornerCurve = kCACornerCurveContinuous;
    field.clipsToBounds = YES;
    field.leftView.tintColor = PAColorHex(0xA7B2CA, 1.0);
    field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:(field.placeholder ?: @"Search")
                                                                   attributes:@{NSForegroundColorAttributeName: PAColorHex(0x8792AA, 1.0)}];
}

- (void)styleTableView:(UITableView *)tableView tabIndex:(NSUInteger)tabIndex {
    tableView.backgroundColor = UIColor.clearColor;
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    tableView.indicatorStyle = UIScrollViewIndicatorStyleWhite;

    for (UITableViewCell *cell in tableView.visibleCells) {
        NSIndexPath *indexPath = [tableView indexPathForCell:cell];
        NSUInteger row = indexPath ? indexPath.row : 0;

        PAStudioCardBackgroundView *background = objc_getAssociatedObject(cell, PACardKey);
        if (!background) {
            background = [[PAStudioCardBackgroundView alloc] initWithFrame:cell.bounds];
            cell.backgroundView = background;
            objc_setAssociatedObject(cell, PACardKey, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [background configureForTab:tabIndex row:row opacity:self.cardOpacity cornerRadius:self.cornerRadius];

        cell.backgroundColor = UIColor.clearColor;
        cell.contentView.backgroundColor = UIColor.clearColor;
        cell.tintColor = PAAccentForIndex(tabIndex);
        cell.preservesSuperviewLayoutMargins = NO;
        cell.layoutMargins = UIEdgeInsetsMake(0, 20.0, 0, 17.0);
        PAStyleLabelsInView(cell.contentView, PAAccentForIndex(tabIndex));
    }

    for (UIView *subview in tableView.subviews) {
        if ([subview isKindOfClass:[UITableViewHeaderFooterView class]]) {
            UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)subview;
            header.contentView.backgroundColor = UIColor.clearColor;
            header.textLabel.textColor = PAColorHex(0xA7B2CA, 1.0);
            header.textLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightBold];
        }
    }

    if (tabIndex == 0 && self.showShortcuts) {
        PAStudioShortcutsView *shortcuts = objc_getAssociatedObject(tableView, PAShortcutsKey);
        if (!shortcuts) {
            shortcuts = [[PAStudioShortcutsView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(tableView.bounds), 160.0)];
            __weak typeof(self) weakSelf = self;
            shortcuts.tapHandler = ^(NSUInteger index) {
                [weakSelf shortcutTapped:index];
            };
            objc_setAssociatedObject(tableView, PAShortcutsKey, shortcuts, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        shortcuts.frame = CGRectMake(0, 0, CGRectGetWidth(tableView.bounds), 160.0);
        if (tableView.tableFooterView != shortcuts) tableView.tableFooterView = shortcuts;
    }
}

- (void)styleCollectionView:(UICollectionView *)collectionView tabIndex:(NSUInteger)tabIndex {
    collectionView.backgroundColor = UIColor.clearColor;
    NSArray<UIColor *> *palette = PAPaletteForIndex(tabIndex);

    NSUInteger counter = 0;
    for (UICollectionViewCell *cell in collectionView.visibleCells) {
        UIColor *accent = palette[counter % palette.count];
        CAGradientLayer *gradient = objc_getAssociatedObject(cell, PABackgroundKey);
        if (!gradient) {
            gradient = [CAGradientLayer layer];
            gradient.startPoint = CGPointMake(0.0, 0.0);
            gradient.endPoint = CGPointMake(1.0, 1.0);
            [cell.layer insertSublayer:gradient atIndex:0];
            objc_setAssociatedObject(cell, PABackgroundKey, gradient, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        BOOL hero = (tabIndex == 0 && counter == 0) || (tabIndex == 2 && counter == 0);
        gradient.frame = cell.bounds;
        gradient.colors = hero
            ? @[(id)[accent colorWithAlphaComponent:0.86 * self.cardOpacity].CGColor,
                (id)PAColorHex(0x17213D, 0.94 * self.cardOpacity).CGColor]
            : @[(id)[accent colorWithAlphaComponent:0.26 * self.cardOpacity].CGColor,
                (id)PAColorHex(0x17213D, 0.96 * self.cardOpacity).CGColor];
        gradient.cornerRadius = self.cornerRadius;

        cell.layer.cornerRadius = self.cornerRadius;
        cell.layer.cornerCurve = kCACornerCurveContinuous;
        cell.layer.masksToBounds = YES;
        cell.layer.borderWidth = 0.8;
        cell.layer.borderColor = [accent colorWithAlphaComponent:0.30].CGColor;
        PAStyleLabelsInView(cell.contentView, accent);
        counter++;
    }
}

- (void)installCustomKeypadForController:(UIViewController *)controller {
    if (!controller || !controller.isViewLoaded) return;
    PAStudioKeypadView *keypad = objc_getAssociatedObject(controller.view, PAKeypadKey);
    if (!keypad) {
        keypad = [[PAStudioKeypadView alloc] initWithFrame:controller.view.bounds];
        keypad.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [controller.view addSubview:keypad];
        objc_setAssociatedObject(controller.view, PAKeypadKey, keypad, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    keypad.hapticsEnabled = self.haptics;
    keypad.animationsEnabled = self.animations;
    keypad.studioCornerRadius = self.cornerRadius;
    keypad.hidden = NO;
    keypad.frame = controller.view.bounds;
    [controller.view bringSubviewToFront:keypad];
}

- (void)hideCustomKeypadForController:(UIViewController *)controller {
    PAStudioKeypadView *keypad = controller ? objc_getAssociatedObject(controller.view, PAKeypadKey) : nil;
    keypad.hidden = YES;
}

- (void)showSystemNavigationForTabController:(UITabBarController *)tabController {
    self.header.hidden = YES;
    self.dock.hidden = YES;

    for (UIView *subview in tabController.tabBar.subviews) {
        if (subview == self.dock) continue;
        NSString *className = NSStringFromClass(subview.class);
        if ([subview isKindOfClass:[UIControl class]] || [className containsString:@"Button"]) {
            subview.alpha = 1.0;
            subview.userInteractionEnabled = YES;
        }
    }

    UINavigationController *navigationController = PASelectedNavigationController(tabController);
    if (navigationController) navigationController.navigationBarHidden = NO;
    UIViewController *top = PATabTop(tabController);
    top.additionalSafeAreaInsets = UIEdgeInsetsZero;
    [self hideCustomKeypadForController:top];
}

- (void)restoreTabController:(UITabBarController *)tabController {
    [self showSystemNavigationForTabController:tabController];
    tabController.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
    self.header.hidden = YES;
    self.dock.hidden = YES;
}

- (void)tableViewDidLayout:(UITableView *)tableView {
    if (!self.enabled || !self.tabController || !PAIsStudioSurface(self.tabController)) return;
    UIViewController *top = PATabTop(self.tabController);
    if (!top || !PAViewIsDescendantOf(tableView, top.view)) return;
    [self styleTableView:tableView tabIndex:MIN(self.tabController.selectedIndex, 4)];
}

- (void)collectionViewDidLayout:(UICollectionView *)collectionView {
    if (!self.enabled || !self.tabController || !PAIsStudioSurface(self.tabController)) return;
    UIViewController *top = PATabTop(self.tabController);
    if (!top || !PAViewIsDescendantOf(collectionView, top.view)) return;
    [self styleCollectionView:collectionView tabIndex:MIN(self.tabController.selectedIndex, 4)];
}

- (void)performHeaderAction {
    if (!self.tabController) return;
    NSUInteger index = MIN(self.tabController.selectedIndex, 4);
    UIViewController *top = PATabTop(self.tabController);

    if (index == 3) {
        PAStudioKeypadView *keypad = objc_getAssociatedObject(top.view, PAKeypadKey);
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"PhoneAura Keypad"
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Clear Number"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
            [keypad clearNumber];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"PhoneAura Settings"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [self openPhoneAuraSettings];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [top presentViewController:sheet animated:YES completion:nil];
        return;
    }

    UIBarButtonItem *item = top.navigationItem.rightBarButtonItem ?: top.navigationItem.rightBarButtonItems.lastObject;
    if (item.target && item.action) {
        [[UIApplication sharedApplication] sendAction:item.action to:item.target from:item forEvent:nil];
    } else {
        [self openPhoneAuraSettings];
    }
}

- (void)shortcutTapped:(NSUInteger)index {
    if (!self.tabController) return;
    switch (index) {
        case 0: {
            NSURL *url = [NSURL URLWithString:@"sms:"];
            if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            break;
        }
        case 1:
            self.tabController.selectedIndex = MIN((NSUInteger)3, self.tabController.viewControllers.count - 1);
            [self applyToTabController:self.tabController animated:YES];
            break;
        case 2:
            self.tabController.selectedIndex = MIN((NSUInteger)4, self.tabController.viewControllers.count - 1);
            [self applyToTabController:self.tabController animated:YES];
            break;
        default:
            [self openPhoneAuraSettings];
            break;
    }
}

- (void)openPhoneAuraSettings {
    NSArray<NSString *> *candidates = @[@"App-prefs:root=PhoneAura", @"prefs:root=PhoneAura"];
    for (NSString *candidate in candidates) {
        NSURL *url = [NSURL URLWithString:candidate];
        if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            return;
        }
    }
}

@end
