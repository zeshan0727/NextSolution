#import "PAContactFlowV46.h"
#import "PAConceptDUI.h"
#import <Contacts/Contacts.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const PA47ContactsChanged = @"com.zeshan.phoneaura.contacts.changed.v47";
static CFStringRef const PA47PreferencesDomain = CFSTR("com.zeshan.phoneaura");
static CFStringRef const PA47PreferencesChanged = CFSTR("com.zeshan.phoneaura/preferences.changed");

static const void *PA47ContactsLastRefreshKey = &PA47ContactsLastRefreshKey;
static const void *PA47DetailContactKey = &PA47DetailContactKey;
static const void *PA47DetailDeleteButtonKey = &PA47DetailDeleteButtonKey;

static UIViewController *PA47ContactTopController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
        if (window) break;
    }

    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    if ([controller isKindOfClass:[UITabBarController class]]) {
        controller = ((UITabBarController *)controller).selectedViewController;
    }
    if ([controller isKindOfClass:[UINavigationController class]]) {
        controller = ((UINavigationController *)controller).topViewController;
    }
    return controller;
}

static void PA47ContactToast(UIView *host, NSString *text, BOOL error) {
    if (!host || !text.length) return;
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 2;
    label.backgroundColor = error ? PAColorHex(0xB91C1C, 0.97) : PAColorHex(0x166534, 0.97);
    label.layer.cornerRadius = 14;
    label.layer.cornerCurve = kCACornerCurveContinuous;
    label.layer.masksToBounds = YES;
    CGFloat width = MIN(CGRectGetWidth(host.bounds)-36, 310);
    label.frame = CGRectMake((CGRectGetWidth(host.bounds)-width)/2.0,
                             CGRectGetHeight(host.bounds)-80,
                             width,
                             48);
    label.alpha = 0;
    [host addSubview:label];
    [host bringSubviewToFront:label];
    [UIView animateWithDuration:0.18 animations:^{ label.alpha = 1; } completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.2 delay:1.25 options:0 animations:^{ label.alpha = 0; } completion:^(__unused BOOL done) { [label removeFromSuperview]; }];
    }];
}

static NSString *PA47ContactDisplayName(CNContact *contact) {
    if (!contact) return @"Contact";
    @try {
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        if (contact.givenName.length) [parts addObject:contact.givenName];
        if (contact.middleName.length) [parts addObject:contact.middleName];
        if (contact.familyName.length) [parts addObject:contact.familyName];
        NSString *name = [parts componentsJoinedByString:@" "];
        if (name.length) return name;
        if (contact.nickname.length) return contact.nickname;
        if (contact.organizationName.length) return contact.organizationName;
    } @catch (__unused NSException *exception) {
    }
    return @"Contact";
}

static void PA47RemoveDeletedFavoriteIdentifier(NSString *identifier) {
    if (!identifier.length) return;
    CFPreferencesAppSynchronize(PA47PreferencesDomain);
    NSArray *saved = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("favoriteIdentifiers"), PA47PreferencesDomain));
    if (![saved isKindOfClass:[NSArray class]] || ![saved containsObject:identifier]) return;

    NSMutableArray *updated = [saved mutableCopy];
    [updated removeObject:identifier];
    CFPreferencesSetAppValue(CFSTR("favoriteIdentifiers"), (__bridge CFArrayRef)[updated copy], PA47PreferencesDomain);
    CFPreferencesAppSynchronize(PA47PreferencesDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         PA47PreferencesChanged,
                                         NULL,
                                         NULL,
                                         true);
}

static void PA47DeleteContact(CNContact *contact,
                              void (^completion)(BOOL success, NSString *message)) {
    if (!contact.identifier.length) {
        if (completion) completion(NO, @"This contact cannot be identified.");
        return;
    }

    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.zeshan.phoneaura.contact-delete.v47", DISPATCH_QUEUE_SERIAL);
    });

    NSString *identifier = [contact.identifier copy];
    dispatch_async(queue, ^{
        @autoreleasepool {
            BOOL success = NO;
            NSString *message = @"Unable to delete this contact.";
            @try {
                CNContactStore *store = [[CNContactStore alloc] init];
                NSError *fetchError = nil;
                NSArray<id<CNKeyDescriptor>> *keys = @[
                    CNContactIdentifierKey,
                    CNContactGivenNameKey,
                    CNContactMiddleNameKey,
                    CNContactFamilyNameKey,
                    CNContactOrganizationNameKey,
                    CNContactPhoneNumbersKey
                ];
                CNContact *freshContact = [store unifiedContactWithIdentifier:identifier
                                                                  keysToFetch:keys
                                                                        error:&fetchError];
                if (freshContact && !fetchError) {
                    CNSaveRequest *request = [[CNSaveRequest alloc] init];
                    [request deleteContact:[freshContact mutableCopy]];
                    NSError *saveError = nil;
                    success = [store executeSaveRequest:request error:&saveError];
                    if (success) message = @"Contact deleted.";
                    else if (saveError.localizedDescription.length) message = saveError.localizedDescription;
                } else if (fetchError.localizedDescription.length) {
                    message = fetchError.localizedDescription;
                }
            } @catch (NSException *exception) {
                if (exception.reason.length) message = exception.reason;
            }

            if (success) PA47RemoveDeletedFavoriteIdentifier(identifier);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    [[NSNotificationCenter defaultCenter] postNotificationName:PA47ContactsChanged object:nil];
                }
                if (completion) completion(success, message);
            });
        }
    });
}

static void PA47ConfirmContactDeletion(CNContact *contact,
                                       UIView *sourceView,
                                       void (^completion)(BOOL confirmed)) {
    UIViewController *controller = PA47ContactTopController();
    if (!controller) { if (completion) completion(YES); return; }

    NSString *name = PA47ContactDisplayName(contact);
    NSString *message = [NSString stringWithFormat:@"%@ will be permanently removed from Contacts and synced accounts. If this is your My Card, Siri/My Info may also be cleared.", name];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Contact?"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
        if (completion) completion(NO);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete Contact" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        if (completion) completion(YES);
    }]];
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = sourceView ?: controller.view;
        alert.popoverPresentationController.sourceRect = sourceView ? sourceView.bounds : controller.view.bounds;
    }
    [controller presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Contacts list swipe deletion and refresh throttling

@interface PAContactsDashboardV46 (PhoneAuraV47)
- (instancetype)pa47_contactsInitWithFrame:(CGRect)frame;
- (void)pa47_contactsRefresh;
@end

@implementation PAContactsDashboardV46 (PhoneAuraV47)

- (instancetype)pa47_contactsInitWithFrame:(CGRect)frame {
    self = [self pa47_contactsInitWithFrame:frame];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pa47_contactsDidChange:)
                                                     name:PA47ContactsChanged
                                                   object:nil];
    }
    return self;
}

- (void)pa47_contactsRefresh {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSTimeInterval last = [objc_getAssociatedObject(self, PA47ContactsLastRefreshKey) doubleValue];
    NSArray *existing = nil;
    @try { existing = [self valueForKey:@"allContacts"]; } @catch (__unused NSException *exception) {}

    if (existing.count > 0 && now-last < 2.5) return;
    objc_setAssociatedObject(self, PA47ContactsLastRefreshKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self pa47_contactsRefresh];
}

- (void)pa47_contactsDidChange:(NSNotification *)notification {
    objc_setAssociatedObject(self, PA47ContactsLastRefreshKey, @(0), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self refresh];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
 trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<CNContact *> *filtered = nil;
    @try { filtered = [self valueForKey:@"filteredContacts"]; } @catch (__unused NSException *exception) {}
    if (indexPath.row >= filtered.count) return nil;

    CNContact *contact = filtered[indexPath.row];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                                title:@"Delete"
                                                                              handler:^(__unused UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        PA47ConfirmContactDeletion(contact, sourceView, ^(BOOL confirmed) {
            if (!confirmed) { completionHandler(NO); return; }
            PA47DeleteContact(contact, ^(BOOL success, NSString *message) {
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf) { completionHandler(NO); return; }
                if (success) {
                    NSArray<CNContact *> *all = nil;
                    NSArray<CNContact *> *currentFiltered = nil;
                    @try {
                        all = [strongSelf valueForKey:@"allContacts"];
                        currentFiltered = [strongSelf valueForKey:@"filteredContacts"];
                    } @catch (__unused NSException *exception) {}
                    NSPredicate *keep = [NSPredicate predicateWithBlock:^BOOL(CNContact *item, NSDictionary *bindings) {
                        return ![item.identifier isEqualToString:contact.identifier];
                    }];
                    @try {
                        [strongSelf setValue:[all filteredArrayUsingPredicate:keep] forKey:@"allContacts"];
                        [strongSelf setValue:[currentFiltered filteredArrayUsingPredicate:keep] forKey:@"filteredContacts"];
                    } @catch (__unused NSException *exception) {}
                    [tableView reloadData];
                }
                PA47ContactToast(strongSelf, message, !success);
                completionHandler(success);
            });
        });
    }];
    deleteAction.image = [UIImage systemImageNamed:@"trash.fill"];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

@end

#pragma mark - Delete button inside PhoneAura contact details

@interface PAContactDetailViewV46 (PhoneAuraV47)
- (void)pa47_configureContact:(CNContact *)contact;
- (void)pa47_detailLayoutSubviews;
@end

@implementation PAContactDetailViewV46 (PhoneAuraV47)

- (void)pa47_configureContact:(CNContact *)contact {
    [self pa47_configureContact:contact];
    objc_setAssociatedObject(self, PA47DetailContactKey, contact, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIButton *button = objc_getAssociatedObject(self, PA47DetailDeleteButtonKey);
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:@"Delete Contact" forState:UIControlStateNormal];
        [button setImage:[UIImage systemImageNamed:@"trash.fill"] forState:UIControlStateNormal];
        button.tintColor = UIColor.whiteColor;
        button.backgroundColor = PAColorHex(0xB91C1C, 1.0);
        button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        button.layer.cornerRadius = 17;
        button.layer.cornerCurve = kCACornerCurveContinuous;
        [button addTarget:self action:@selector(pa47_detailDeleteTapped) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(self, PA47DetailDeleteButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIScrollView *scrollView = nil;
    @try { scrollView = [self valueForKey:@"scrollView"]; } @catch (__unused NSException *exception) {}
    if (scrollView && button.superview != scrollView) [scrollView addSubview:button];
    [self setNeedsLayout];
}

- (void)pa47_detailLayoutSubviews {
    [self pa47_detailLayoutSubviews];
    UIButton *button = objc_getAssociatedObject(self, PA47DetailDeleteButtonKey);
    if (!button) return;

    UIScrollView *scrollView = nil;
    UIView *numbersCard = nil;
    @try {
        scrollView = [self valueForKey:@"scrollView"];
        numbersCard = [self valueForKey:@"numbersCard"];
    } @catch (__unused NSException *exception) {}
    if (!scrollView) return;
    if (button.superview != scrollView) [scrollView addSubview:button];

    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat y = numbersCard ? CGRectGetMaxY(numbersCard.frame)+16 : MAX(330, scrollView.contentSize.height+8);
    button.frame = CGRectMake(16, y, width-32, 54);
    scrollView.contentSize = CGSizeMake(width, MAX(CGRectGetMaxY(button.frame)+24, CGRectGetHeight(self.bounds)+1));
}

- (void)pa47_detailDeleteTapped {
    CNContact *contact = objc_getAssociatedObject(self, PA47DetailContactKey);
    if (!contact) {
        PA47ContactToast(self, @"Contact information is unavailable.", YES);
        return;
    }

    UIButton *button = objc_getAssociatedObject(self, PA47DetailDeleteButtonKey);
    __weak typeof(self) weakSelf = self;
    PA47ConfirmContactDeletion(contact, button, ^(BOOL confirmed) {
        if (!confirmed) return;
        button.enabled = NO;
        button.alpha = 0.55;
        PA47DeleteContact(contact, ^(BOOL success, NSString *message) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            PA47ContactToast(strongSelf, message, !success);
            if (!success) {
                button.enabled = YES;
                button.alpha = 1;
                return;
            }

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                Class managerClass = NSClassFromString(@"PhoneAuraManager");
                SEL sharedSelector = NSSelectorFromString(@"sharedManager");
                SEL closeSelector = NSSelectorFromString(@"closeAuxiliaryMode");
                if (managerClass && [managerClass respondsToSelector:sharedSelector]) {
                    typedef id (*SharedFunction)(id, SEL);
                    id manager = ((SharedFunction)objc_msgSend)(managerClass, sharedSelector);
                    if (manager && [manager respondsToSelector:closeSelector]) {
                        typedef void (*CloseFunction)(id, SEL);
                        ((CloseFunction)objc_msgSend)(manager, closeSelector);
                    }
                }
            });
        });
    });
}

@end

static void PA47ContactExchange(Class cls, SEL original, SEL replacement) {
    Method first = class_getInstanceMethod(cls, original);
    Method second = class_getInstanceMethod(cls, replacement);
    if (first && second) method_exchangeImplementations(first, second);
}

__attribute__((constructor)) static void PA47InstallContactActions(void) {
    Class contactsClass = NSClassFromString(@"PAContactsDashboardV46");
    if (contactsClass) {
        PA47ContactExchange(contactsClass, @selector(initWithFrame:), @selector(pa47_contactsInitWithFrame:));
        PA47ContactExchange(contactsClass, @selector(refresh), @selector(pa47_contactsRefresh));
    }

    Class detailClass = NSClassFromString(@"PAContactDetailViewV46");
    if (detailClass) {
        PA47ContactExchange(detailClass, @selector(configureContact:), @selector(pa47_configureContact:));
        PA47ContactExchange(detailClass, @selector(layoutSubviews), @selector(pa47_detailLayoutSubviews));
    }
}
