#import "PhoneAuraManager.h"
#import "PAConceptDUI.h"
#import "PAConceptDSurfaces.h"
#import <ContactsUI/ContactsUI.h>
#import <objc/runtime.h>

static CFStringRef const PADomain = CFSTR("com.zeshan.phoneaura");
static CFStringRef const PAChanged = CFSTR("com.zeshan.phoneaura/preferences.changed");

static const void *PAHeaderKey = &PAHeaderKey;
static const void *PADockKey = &PADockKey;
static const void *PAOverlayKey = &PAOverlayKey;
static const void *PAFavoritesKey = &PAFavoritesKey;
static const void *PARecentsKey = &PARecentsKey;
static const void *PAContactsKey = &PAContactsKey;
static const void *PAKeypadKey = &PAKeypadKey;
static const void *PAFavoritesSignatureKey = &PAFavoritesSignatureKey;

static id PARead(NSString *key) {
    CFPreferencesAppSynchronize(PADomain);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, PADomain));
}

static BOOL PABool(NSString *key, BOOL fallback) {
    id value = PARead(key);
    return value ? [value boolValue] : fallback;
}

static CGFloat PAFloat(NSString *key, CGFloat fallback) {
    id value = PARead(key);
    return value ? [value doubleValue] : fallback;
}

static UINavigationController *PANavigation(UITabBarController *tabController) {
    UIViewController *selected = tabController.selectedViewController;
    return [selected isKindOfClass:[UINavigationController class]] ? (UINavigationController *)selected : nil;
}

static UIViewController *PATop(UITabBarController *tabController) {
    UINavigationController *navigationController = PANavigation(tabController);
    return navigationController ? navigationController.topViewController : tabController.selectedViewController;
}

static UITabBarController *PAFindTab(UIViewController *controller) {
    if ([controller isKindOfClass:[UITabBarController class]]) return (UITabBarController *)controller;
    if (controller.tabBarController) return controller.tabBarController;
    UIViewController *cursor = controller.parentViewController;
    while (cursor) {
        if ([cursor isKindOfClass:[UITabBarController class]]) return (UITabBarController *)cursor;
        if (cursor.tabBarController) return cursor.tabBarController;
        cursor = cursor.parentViewController;
    }
    return nil;
}

/*
 * The iOS 16 Contacts tab commonly has a two-controller root stack:
 * Lists -> Contacts.  Treat that stack as the tab root.  Only a real contact
 * detail controller (or a deeper navigation stack) should expose Apple's UI.
 */
static BOOL PAIsSystemDetail(UITabBarController *tabController) {
    UINavigationController *navigationController = PANavigation(tabController);
    UIViewController *top = PATop(tabController);
    if (!top) return NO;

    if ([top isKindOfClass:[CNContactViewController class]]) return YES;

    NSUInteger index = MIN(tabController.selectedIndex, (NSUInteger)4);
    NSUInteger count = navigationController.viewControllers.count;
    if (!navigationController || count <= 1) return NO;

    if (index == 2 && count <= 2) {
        NSString *className = NSStringFromClass(top.class);
        NSString *title = (top.navigationItem.title ?: top.title ?: @"").lowercaseString;
        if ([className containsString:@"Contact"] ||
            [className containsString:@"People"] ||
            [title containsString:@"contact"] ||
            [title containsString:@"list"]) {
            return NO;
        }
    }

    return YES;
}

static void PASettingsChanged(CFNotificationCenterRef center,
                              void *observer,
                              CFStringRef name,
                              const void *object,
                              CFDictionaryRef userInfo) {
    PhoneAuraManager *manager = (__bridge PhoneAuraManager *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{ [manager reloadPreferences]; });
}

@interface PhoneAuraManager ()
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL haptics;
@property(nonatomic) BOOL animations;
@property(nonatomic) BOOL showSubtitles;
@property(nonatomic) BOOL fullFavorites;
@property(nonatomic) BOOL fullRecents;
@property(nonatomic) BOOL fullContacts;
@property(nonatomic) BOOL fullKeypad;
@property(nonatomic) CGFloat cardOpacity;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic,strong) NSArray<NSString *> *favoriteIdentifiers;
@property(nonatomic,weak) UITabBarController *tabController;
@property(nonatomic,strong) PAStudioHeaderView *header;
@property(nonatomic,strong) PAStudioDock *dock;
@property(nonatomic,strong) UIView *overlay;
@property(nonatomic) BOOL applying;
@property(nonatomic) NSUInteger lastSelectedIndex;
@property(nonatomic) BOOL hasLastSelectedIndex;
@end

@implementation PhoneAuraManager

+ (instancetype)sharedManager {
    static PhoneAuraManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[self alloc] init]; });
    return manager;
}

- (instancetype)init {
    if ((self = [super init])) {
        _lastSelectedIndex = NSNotFound;
        [self reloadPreferences];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)self,
                                        PASettingsChanged,
                                        PAChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (__bridge const void *)self,
                                       PAChanged,
                                       NULL);
}

- (void)reloadPreferences {
    self.enabled = PABool(@"enabled", YES);
    self.haptics = PABool(@"haptics", YES);
    self.animations = PABool(@"animations", YES);
    self.showSubtitles = PABool(@"showSubtitles", YES);
    self.fullFavorites = PABool(@"fullFavorites", YES);
    self.fullRecents = PABool(@"fullRecents", YES);
    self.fullContacts = PABool(@"fullContacts", YES);
    self.fullKeypad = PABool(@"fullKeypad", YES);
    self.cardOpacity = MAX(0.65, MIN(PAFloat(@"cardOpacity", 0.96), 1.0));
    self.cornerRadius = MAX(10.0, MIN(PAFloat(@"cornerRadius", 16.0), 26.0));
    id identifiers = PARead(@"favoriteIdentifiers");
    self.favoriteIdentifiers = [identifiers isKindOfClass:[NSArray class]] ? identifiers : @[];
    self.hasLastSelectedIndex = NO;

    if (!self.tabController) return;
    if (self.enabled) [self applyToTabController:self.tabController animated:NO forceDataRefresh:YES];
    else [self restoreTabController:self.tabController];
}

- (void)controllerDidAppear:(UIViewController *)controller {
    UITabBarController *tabController = PAFindTab(controller);
    if (!tabController) return;
    self.tabController = tabController;
    if (self.enabled) [self applyToTabController:tabController animated:NO forceDataRefresh:NO];
    else [self restoreTabController:tabController];
}

- (void)controllerDidLayout:(UIViewController *)controller {
    UITabBarController *tabController = PAFindTab(controller);
    if (!self.enabled || !tabController || tabController != self.tabController) return;
    if (PAIsSystemDetail(tabController)) {
        [self showSystemNavigation:tabController];
        return;
    }
    [self layoutChromeForTabController:tabController];
}

- (void)tabSelectionChanged:(UITabBarController *)tabController {
    self.tabController = tabController;
    __weak typeof(self) weakSelf = self;
    __weak UITabBarController *weakTab = tabController;
    dispatch_async(dispatch_get_main_queue(), ^{
        PhoneAuraManager *strongSelf = weakSelf;
        UITabBarController *strongTab = weakTab;
        if (!strongSelf || !strongTab) return;
        if (strongSelf.enabled) [strongSelf applyToTabController:strongTab animated:YES forceDataRefresh:NO];
        else [strongSelf restoreTabController:strongTab];
    });
}

- (BOOL)customSurfaceEnabledForIndex:(NSUInteger)index {
    switch (index) {
        case 0: return self.fullFavorites;
        case 1: return self.fullRecents;
        case 2: return self.fullContacts;
        case 3: return self.fullKeypad;
        default: return NO;
    }
}

- (void)applyToTabController:(UITabBarController *)tabController
                     animated:(BOOL)animated
             forceDataRefresh:(BOOL)forceRefresh {
    if (self.applying || !tabController.view.window) return;
    self.applying = YES;

    if (PAIsSystemDetail(tabController)) {
        [self showSystemNavigation:tabController];
        self.applying = NO;
        return;
    }

    NSUInteger index = MIN(tabController.selectedIndex, (NSUInteger)4);
    if (![self customSurfaceEnabledForIndex:index]) {
        [self showSystemNavigation:tabController];
        self.lastSelectedIndex = index;
        self.hasLastSelectedIndex = YES;
        self.applying = NO;
        return;
    }

    tabController.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self installDock:tabController];
    [self installHeader:tabController];
    [self installOverlay:tabController];
    [self hideStockRootChrome:tabController];
    [self layoutChromeForTabController:tabController];

    BOOL changed = !self.hasLastSelectedIndex || self.lastSelectedIndex != index;
    [self configureChromeForIndex:index animated:(animated && changed)];
    [self showSurfaceForIndex:index refresh:(forceRefresh || changed)];

    self.lastSelectedIndex = index;
    self.hasLastSelectedIndex = YES;

    [tabController.view bringSubviewToFront:self.overlay];
    [tabController.view bringSubviewToFront:self.header];
    [tabController.view bringSubviewToFront:tabController.tabBar];
    [tabController.tabBar bringSubviewToFront:self.dock];
    self.applying = NO;
}

- (void)installDock:(UITabBarController *)tabController {
    UITabBar *tabBar = tabController.tabBar;
    PAStudioDock *dock = objc_getAssociatedObject(tabBar, PADockKey);
    if (!dock) {
        dock = [[PAStudioDock alloc] init];
        __weak typeof(self) weakSelf = self;
        __weak UITabBarController *weakTab = tabController;
        dock.selectionHandler = ^(NSUInteger index) {
            PhoneAuraManager *strongSelf = weakSelf;
            UITabBarController *strongTab = weakTab;
            if (!strongSelf || !strongTab || index >= strongTab.viewControllers.count) return;
            if (strongSelf.haptics) {
                UISelectionFeedbackGenerator *generator = [[UISelectionFeedbackGenerator alloc] init];
                [generator selectionChanged];
            }
            if (strongTab.selectedIndex == index) {
                [strongSelf applyToTabController:strongTab animated:NO forceDataRefresh:NO];
            } else {
                strongTab.selectedIndex = index;
            }
        };
        [tabBar addSubview:dock];
        objc_setAssociatedObject(tabBar, PADockKey, dock, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    self.dock = dock;
    dock.hidden = NO;
}

- (void)installHeader:(UITabBarController *)tabController {
    PAStudioHeaderView *header = objc_getAssociatedObject(tabController.view, PAHeaderKey);
    if (!header) {
        header = [[PAStudioHeaderView alloc] init];
        __weak typeof(self) weakSelf = self;
        header.actionHandler = ^{ [weakSelf headerAction]; };
        [tabController.view addSubview:header];
        objc_setAssociatedObject(tabController.view, PAHeaderKey, header, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    self.header = header;
    header.hidden = NO;
}

- (void)installOverlay:(UITabBarController *)tabController {
    UIView *overlay = objc_getAssociatedObject(tabController.view, PAOverlayKey);
    if (!overlay) {
        overlay = [[UIView alloc] init];
        overlay.backgroundColor = PAColorHex(0x040817, 1.0);
        overlay.opaque = YES;
        overlay.clipsToBounds = YES;
        [tabController.view addSubview:overlay];
        objc_setAssociatedObject(tabController.view, PAOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    self.overlay = overlay;
    overlay.hidden = NO;
    overlay.userInteractionEnabled = YES;
}

- (void)hideStockRootChrome:(UITabBarController *)tabController {
    UINavigationController *navigationController = PANavigation(tabController);
    if (navigationController) navigationController.navigationBarHidden = YES;

    UITabBar *tabBar = tabController.tabBar;
    tabBar.backgroundImage = [UIImage new];
    tabBar.shadowImage = [UIImage new];
    tabBar.backgroundColor = UIColor.clearColor;
    tabBar.translucent = YES;
    for (UIView *subview in tabBar.subviews) {
        if (subview == self.dock) continue;
        NSString *name = NSStringFromClass(subview.class);
        if ([subview isKindOfClass:[UIControl class]] || [name containsString:@"Button"]) {
            subview.alpha = 0.0;
            subview.userInteractionEnabled = NO;
        }
    }

    UIViewController *top = PATop(tabController);
    top.additionalSafeAreaInsets = UIEdgeInsetsZero;
}

- (void)layoutChromeForTabController:(UITabBarController *)tabController {
    if (!tabController.view.window || !self.header || !self.overlay || !self.dock) return;

    CGFloat width = CGRectGetWidth(tabController.view.bounds);
    CGFloat height = CGRectGetHeight(tabController.view.bounds);
    CGFloat safeTop = tabController.view.safeAreaInsets.top;
    self.header.frame = CGRectMake(16.0, safeTop + 8.0, MAX(0.0, width - 32.0), 74.0);

    CGRect tabFrame = tabController.tabBar.frame;
    CGFloat overlayTop = safeTop + 88.0;
    CGFloat overlayBottom = CGRectGetMinY(tabFrame);
    if (overlayBottom <= overlayTop || overlayBottom > height) {
        overlayBottom = height - MAX(49.0, CGRectGetHeight(tabController.tabBar.bounds));
    }
    self.overlay.frame = CGRectMake(0.0, overlayTop, width, MAX(0.0, overlayBottom - overlayTop));
    for (UIView *surface in self.overlay.subviews) surface.frame = self.overlay.bounds;

    self.dock.frame = CGRectInset(tabController.tabBar.bounds, 8.0, 4.0);
    self.dock.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
}

- (void)configureChromeForIndex:(NSUInteger)index animated:(BOOL)animated {
    NSArray *titles = @[@"Favorites", @"Recents", @"Contacts", @"Keypad", @"Voicemail"];
    NSArray *subtitles = @[@"Your people, one tap away.",
                           @"Your call history at a glance.",
                           @"All your connections.",
                           @"Dial with confidence.",
                           @"Messages that matter."];
    NSArray *icons = @[@"plus", @"arrow.clockwise", @"person.badge.plus", @"ellipsis", @"pencil"];
    [self.header configureTitle:titles[index]
                       subtitle:subtitles[index]
                           icon:icons[index]
                         accent:PAAccentForIndex(index)
                   showSubtitle:self.showSubtitles];
    [self.dock updateSelectedIndex:index animated:(animated && self.animations)];
}

- (void)hideAllOverlaySurfacesExcept:(UIView *)visible {
    for (UIView *surface in self.overlay.subviews) {
        surface.hidden = surface != visible;
        surface.userInteractionEnabled = surface == visible;
    }
}

- (void)showSurfaceForIndex:(NSUInteger)index refresh:(BOOL)refresh {
    UIView *visible = nil;

    if (index == 0 && self.fullFavorites) {
        PAFavoritesDashboardView *surface = objc_getAssociatedObject(self.overlay, PAFavoritesKey);
        if (!surface) {
            surface = [[PAFavoritesDashboardView alloc] initWithFrame:self.overlay.bounds];
            __weak typeof(self) weakSelf = self;
            surface.callHandler = ^(NSString *number) { [weakSelf callNumber:number]; };
            surface.settingsHandler = ^{ [weakSelf openStudioApp]; };
            [self.overlay addSubview:surface];
            objc_setAssociatedObject(self.overlay, PAFavoritesKey, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        surface.hapticsEnabled = self.haptics;
        NSString *signature = [self.favoriteIdentifiers componentsJoinedByString:@"|"] ?: @"";
        NSString *loadedSignature = objc_getAssociatedObject(surface, PAFavoritesSignatureKey);
        if (refresh || ![loadedSignature isEqualToString:signature]) {
            objc_setAssociatedObject(surface, PAFavoritesSignatureKey, signature, OBJC_ASSOCIATION_COPY_NONATOMIC);
            [surface reloadFavoriteIdentifiers:self.favoriteIdentifiers];
        }
        visible = surface;
    } else if (index == 1 && self.fullRecents) {
        PARecentsDashboardView *surface = objc_getAssociatedObject(self.overlay, PARecentsKey);
        if (!surface) {
            surface = [[PARecentsDashboardView alloc] initWithFrame:self.overlay.bounds];
            __weak typeof(self) weakSelf = self;
            surface.callHandler = ^(NSString *number) { [weakSelf callNumber:number]; };
            [self.overlay addSubview:surface];
            objc_setAssociatedObject(self.overlay, PARecentsKey, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if (refresh) {
            [surface refresh];
        }
        surface.hapticsEnabled = self.haptics;
        visible = surface;
    } else if (index == 2 && self.fullContacts) {
        PAContactsDashboardView *surface = objc_getAssociatedObject(self.overlay, PAContactsKey);
        if (!surface) {
            surface = [[PAContactsDashboardView alloc] initWithFrame:self.overlay.bounds];
            __weak typeof(self) weakSelf = self;
            surface.contactHandler = ^(CNContact *contact) { [weakSelf showContact:contact]; };
            [self.overlay addSubview:surface];
            objc_setAssociatedObject(self.overlay, PAContactsKey, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if (refresh) {
            [surface refresh];
        }
        surface.hapticsEnabled = self.haptics;
        visible = surface;
    } else if (index == 3 && self.fullKeypad) {
        PAStudioKeypadView *surface = objc_getAssociatedObject(self.overlay, PAKeypadKey);
        if (!surface) {
            surface = [[PAStudioKeypadView alloc] initWithFrame:self.overlay.bounds];
            [self.overlay addSubview:surface];
            objc_setAssociatedObject(self.overlay, PAKeypadKey, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        surface.backgroundColor = PAColorHex(0x040817, 1.0);
        surface.hapticsEnabled = self.haptics;
        surface.animationsEnabled = self.animations;
        surface.studioCornerRadius = self.cornerRadius;
        visible = surface;
    }

    [self hideAllOverlaySurfacesExcept:visible];
    if (visible) {
        visible.frame = self.overlay.bounds;
        visible.hidden = NO;
        visible.userInteractionEnabled = YES;
        [self.overlay bringSubviewToFront:visible];
    }
}

- (void)showContact:(CNContact *)contact {
    UINavigationController *navigationController = PANavigation(self.tabController);
    if (!navigationController || !contact) return;
    [self showSystemNavigation:self.tabController];
    CNContactViewController *controller = [CNContactViewController viewControllerForContact:contact];
    controller.allowsEditing = YES;
    controller.allowsActions = YES;
    [navigationController pushViewController:controller animated:YES];
}

- (void)callNumber:(NSString *)number {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"+0123456789*#"];
    NSMutableString *clean = [NSMutableString string];
    for (NSUInteger index = 0; index < number.length; index++) {
        NSString *character = [number substringWithRange:NSMakeRange(index, 1)];
        if ([character rangeOfCharacterFromSet:allowed].location != NSNotFound) [clean appendString:character];
    }
    if (!clean.length) return;
    NSString *escaped = [clean stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"tel://%@", escaped ?: clean]];
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (void)headerAction {
    NSUInteger index = MIN(self.tabController.selectedIndex, (NSUInteger)4);
    if (index == 0 || index == 4) {
        [self openStudioApp];
    } else if (index == 1) {
        PARecentsDashboardView *surface = objc_getAssociatedObject(self.overlay, PARecentsKey);
        [surface refresh];
    } else if (index == 2) {
        PAContactsDashboardView *surface = objc_getAssociatedObject(self.overlay, PAContactsKey);
        [surface refresh];
    } else if (index == 3) {
        PAStudioKeypadView *surface = objc_getAssociatedObject(self.overlay, PAKeypadKey);
        [surface clearNumber];
    }
}

- (void)openStudioApp {
    NSURL *url = [NSURL URLWithString:@"phoneaurastudio://settings"];
    if (url && [UIApplication.sharedApplication canOpenURL:url]) {
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        return;
    }
    NSURL *fallback = [NSURL URLWithString:@"App-prefs:root=PhoneAura"];
    if (fallback) [UIApplication.sharedApplication openURL:fallback options:@{} completionHandler:nil];
}

- (void)showSystemNavigation:(UITabBarController *)tabController {
    self.header.hidden = YES;
    self.overlay.hidden = YES;
    self.overlay.userInteractionEnabled = NO;
    self.dock.hidden = YES;

    UITabBar *tabBar = tabController.tabBar;
    tabBar.backgroundImage = nil;
    tabBar.shadowImage = nil;
    tabBar.backgroundColor = nil;
    for (UIView *subview in tabBar.subviews) {
        if (subview == self.dock) continue;
        NSString *name = NSStringFromClass(subview.class);
        if ([subview isKindOfClass:[UIControl class]] || [name containsString:@"Button"]) {
            subview.alpha = 1.0;
            subview.userInteractionEnabled = YES;
        }
    }

    UINavigationController *navigationController = PANavigation(tabController);
    if (navigationController) navigationController.navigationBarHidden = NO;
    UIViewController *top = PATop(tabController);
    top.additionalSafeAreaInsets = UIEdgeInsetsZero;
    tabController.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
}

- (void)restoreTabController:(UITabBarController *)tabController {
    [self showSystemNavigation:tabController];
    self.hasLastSelectedIndex = NO;
}

@end
