#import <UIKit/UIKit.h>
#import <Contacts/Contacts.h>
#import <objc/runtime.h>

static NSString * const PADomain = @"com.zeshan.phoneaura";
static NSString * const PASelectionKey = @"contactBookSelection";
static NSString * const PASelectionLabelKey = @"contactBookSelectionLabel";
static NSString * const PASelectorEnabledKey = @"contactBookSelector";

static const void *PAButtonAssociationKey = &PAButtonAssociationKey;
static const void *PAMasterContactsAssociationKey = &PAMasterContactsAssociationKey;
static const void *PAApplyingAssociationKey = &PAApplyingAssociationKey;

static IMP PAOriginalViewDidAppear = NULL;
static IMP PAOriginalContactsRefresh = NULL;
static IMP PAOriginalContactsChanged = NULL;

@interface PABookChoice : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, copy) NSArray<PABookChoice *> *children;
@end
@implementation PABookChoice
@end

static id PACopyPreference(NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)PADomain);
    return CFBridgingRelease(value);
}

static BOOL PABoolPreference(NSString *key, BOOL fallback) {
    id value = PACopyPreference(key);
    return value ? [value boolValue] : fallback;
}

static void PASetPreference(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)PADomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PADomain);
}

static NSString *PASelectedIdentifier(void) {
    NSString *value = PACopyPreference(PASelectionKey);
    return [value isKindOfClass:NSString.class] && value.length ? value : @"all";
}

static NSString *PASelectedLabel(void) {
    NSString *value = PACopyPreference(PASelectionLabelKey);
    return [value isKindOfClass:NSString.class] && value.length ? value : @"All Contacts";
}

static UIView *PAFindViewNamed(UIView *root, NSString *className) {
    if (!root) return nil;
    if ([NSStringFromClass(root.class) isEqualToString:className]) return root;
    for (UIView *child in root.subviews) {
        UIView *match = PAFindViewNamed(child, className);
        if (match) return match;
    }
    return nil;
}

static void PAReloadTables(UIView *root) {
    if (!root) return;
    if ([root isKindOfClass:UITableView.class]) {
        [(UITableView *)root reloadData];
    }
    for (UIView *child in root.subviews) {
        PAReloadTables(child);
    }
}

static NSArray<id<CNKeyDescriptor>> *PAContactKeys(void) {
    return @[
        CNContactIdentifierKey,
        CNContactNamePrefixKey,
        CNContactGivenNameKey,
        CNContactMiddleNameKey,
        CNContactFamilyNameKey,
        CNContactNameSuffixKey,
        CNContactNicknameKey,
        CNContactOrganizationNameKey,
        CNContactPhoneNumbersKey,
        CNContactThumbnailImageDataKey,
        CNContactImageDataAvailableKey,
        [CNContactFormatter descriptorForRequiredKeysForStyle:CNContactFormatterStyleFullName]
    ];
}

static NSArray<CNContact *> *PAContactsForChoice(PABookChoice *choice, NSError **errorOut) {
    CNContactStore *store = [CNContactStore new];
    NSPredicate *predicate = nil;
    if ([choice.kind isEqualToString:@"container"]) {
        predicate = [CNContact predicateForContactsInContainerWithIdentifier:choice.identifier];
    } else if ([choice.kind isEqualToString:@"group"]) {
        predicate = [CNContact predicateForContactsInGroupWithIdentifier:choice.identifier];
    }
    if (!predicate) return @[];

    NSArray<CNContact *> *contacts = [store unifiedContactsMatchingPredicate:predicate
                                                                  keysToFetch:PAContactKeys()
                                                                        error:errorOut];
    return [contacts sortedArrayUsingComparator:^NSComparisonResult(CNContact *left, CNContact *right) {
        NSString *a = [CNContactFormatter stringFromContact:left style:CNContactFormatterStyleFullName] ?: left.organizationName ?: @"";
        NSString *b = [CNContactFormatter stringFromContact:right style:CNContactFormatterStyleFullName] ?: right.organizationName ?: @"";
        return [a localizedCaseInsensitiveCompare:b];
    }];
}

static NSArray<PABookChoice *> *PALoadBookChoices(void) {
    CNContactStore *store = [CNContactStore new];
    NSError *error = nil;
    NSArray<CNContainer *> *containers = [store containersMatchingPredicate:nil error:&error];
    if (error || !containers.count) return @[];

    NSMutableArray<PABookChoice *> *result = [NSMutableArray array];
    NSArray<CNContainer *> *sorted = [containers sortedArrayUsingComparator:^NSComparisonResult(CNContainer *left, CNContainer *right) {
        return [left.name localizedCaseInsensitiveCompare:right.name];
    }];

    for (CNContainer *container in sorted) {
        PABookChoice *containerChoice = [PABookChoice new];
        containerChoice.identifier = container.identifier;
        containerChoice.title = container.name.length ? container.name : @"Contacts Account";
        containerChoice.kind = @"container";

        NSPredicate *groupPredicate = [CNGroup predicateForGroupsInContainerWithIdentifier:container.identifier];
        NSArray<CNGroup *> *groups = [store groupsMatchingPredicate:groupPredicate error:nil];
        NSMutableArray<PABookChoice *> *children = [NSMutableArray array];
        for (CNGroup *group in [groups sortedArrayUsingComparator:^NSComparisonResult(CNGroup *left, CNGroup *right) {
            return [left.name localizedCaseInsensitiveCompare:right.name];
        }]) {
            PABookChoice *groupChoice = [PABookChoice new];
            groupChoice.identifier = group.identifier;
            groupChoice.title = group.name.length ? group.name : @"Contact List";
            groupChoice.kind = @"group";
            [children addObject:groupChoice];
        }
        containerChoice.children = children;
        [result addObject:containerChoice];
    }
    return result;
}

static void PAUpdateButtonTitle(UIButton *button, NSString *title) {
    NSString *display = title.length ? title : @"All Contacts";
    if (button.configuration) {
        UIButtonConfiguration *configuration = button.configuration;
        configuration.title = display;
        configuration.image = [UIImage systemImageNamed:@"chevron.down"];
        configuration.imagePlacement = NSDirectionalRectEdgeTrailing;
        configuration.imagePadding = 6.0;
        button.configuration = configuration;
    } else {
        [button setTitle:[display stringByAppendingString:@"  ▾"] forState:UIControlStateNormal];
    }
    button.accessibilityLabel = [NSString stringWithFormat:@"Contact book: %@", display];
}

static NSArray *PAReadContactArray(id controller, NSString *key) {
    @try {
        id value = [controller valueForKey:key];
        return [value isKindOfClass:NSArray.class] ? value : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void PAWriteContactArray(id controller, NSString *key, NSArray *contacts) {
    @try {
        [controller setValue:contacts ?: @[] forKey:key];
    } @catch (__unused NSException *exception) {
    }
}

static void PACaptureMasterContacts(id controller) {
    NSArray *current = PAReadContactArray(controller, @"allContacts");
    if (current.count && !objc_getAssociatedObject(controller, PAMasterContactsAssociationKey)) {
        objc_setAssociatedObject(controller, PAMasterContactsAssociationKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void PAApplyChoice(UIViewController *controller, PABookChoice *choice, BOOL persist) {
    if (!controller || objc_getAssociatedObject(controller, PAApplyingAssociationKey)) return;
    objc_setAssociatedObject(controller, PAApplyingAssociationKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PACaptureMasterContacts(controller);

    UIButton *button = objc_getAssociatedObject(controller, PAButtonAssociationKey);
    NSString *title = choice.title.length ? choice.title : @"All Contacts";
    PAUpdateButtonTitle(button, title);

    if (persist) {
        NSString *selection = [choice.kind isEqualToString:@"all"]
            ? @"all"
            : [NSString stringWithFormat:@"%@:%@", choice.kind, choice.identifier ?: @""];
        PASetPreference(PASelectionKey, selection);
        PASetPreference(PASelectionLabelKey, title);
    }

    if ([choice.kind isEqualToString:@"all"]) {
        NSArray *master = objc_getAssociatedObject(controller, PAMasterContactsAssociationKey);
        if (master) {
            PAWriteContactArray(controller, @"allContacts", master);
            PAWriteContactArray(controller, @"filteredContacts", master);
            PAReloadTables(controller.view);
        }
        objc_setAssociatedObject(controller, PAApplyingAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSArray<CNContact *> *contacts = PAContactsForChoice(choice, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!error) {
                PAWriteContactArray(controller, @"allContacts", contacts);
                PAWriteContactArray(controller, @"filteredContacts", contacts);
                PAReloadTables(controller.view);
            } else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Contacts Unavailable"
                                                                               message:@"PhoneAura could not read this contact book. Check Contacts permission and try again."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [controller presentViewController:alert animated:YES completion:nil];
            }
            objc_setAssociatedObject(controller, PAApplyingAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        });
    });
}

static PABookChoice *PAChoiceForStoredSelection(NSArray<PABookChoice *> *choices) {
    NSString *selection = PASelectedIdentifier();
    if ([selection isEqualToString:@"all"]) {
        PABookChoice *all = [PABookChoice new];
        all.kind = @"all";
        all.title = @"All Contacts";
        return all;
    }

    NSArray<NSString *> *parts = [selection componentsSeparatedByString:@":"];
    if (parts.count < 2) return nil;
    NSString *kind = parts.firstObject;
    NSString *identifier = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@":"];
    for (PABookChoice *container in choices) {
        if ([kind isEqualToString:@"container"] && [container.identifier isEqualToString:identifier]) return container;
        for (PABookChoice *group in container.children) {
            if ([kind isEqualToString:@"group"] && [group.identifier isEqualToString:identifier]) return group;
        }
    }
    return nil;
}

static UIAction *PAActionForChoice(UIViewController *controller, PABookChoice *choice, NSString *storedSelection) {
    NSString *selection = [choice.kind isEqualToString:@"all"]
        ? @"all"
        : [NSString stringWithFormat:@"%@:%@", choice.kind, choice.identifier ?: @""];
    UIAction *action = [UIAction actionWithTitle:choice.title ?: @"Contacts"
                                          image:nil
                                     identifier:nil
                                        handler:^(__kindof UIAction *unusedAction) {
        PAApplyChoice(controller, choice, YES);
    }];
    action.state = [selection isEqualToString:storedSelection] ? UIMenuElementStateOn : UIMenuElementStateOff;
    return action;
}

static void PABuildMenu(UIViewController *controller, UIButton *button) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<PABookChoice *> *choices = PALoadBookChoices();
        NSString *stored = PASelectedIdentifier();
        dispatch_async(dispatch_get_main_queue(), ^{
            PABookChoice *all = [PABookChoice new];
            all.kind = @"all";
            all.title = @"All Contacts";
            NSMutableArray<UIMenuElement *> *elements = [NSMutableArray arrayWithObject:PAActionForChoice(controller, all, stored)];

            for (PABookChoice *container in choices) {
                NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];
                PABookChoice *containerAll = [PABookChoice new];
                containerAll.kind = @"container";
                containerAll.identifier = container.identifier;
                containerAll.title = [NSString stringWithFormat:@"All %@", container.title ?: @"Contacts"];
                [children addObject:PAActionForChoice(controller, containerAll, stored)];
                for (PABookChoice *group in container.children) {
                    [children addObject:PAActionForChoice(controller, group, stored)];
                }
                UIMenu *submenu = [UIMenu menuWithTitle:container.title ?: @"Contacts Account"
                                                  image:[UIImage systemImageNamed:@"person.crop.circle"]
                                             identifier:nil
                                                options:UIMenuOptionsDisplayInline
                                               children:children];
                [elements addObject:submenu];
            }

            UIAction *refresh = [UIAction actionWithTitle:@"Refresh Contact Books"
                                                    image:[UIImage systemImageNamed:@"arrow.clockwise"]
                                               identifier:nil
                                                  handler:^(__kindof UIAction *unusedAction) {
                PABuildMenu(controller, button);
            }];
            [elements addObject:[UIMenu menuWithTitle:@"" children:@[refresh]]];
            button.menu = [UIMenu menuWithTitle:@"Contact Books" children:elements];
            button.showsMenuAsPrimaryAction = YES;

            PABookChoice *storedChoice = PAChoiceForStoredSelection(choices);
            if (storedChoice && ![stored isEqualToString:@"all"]) {
                PAApplyChoice(controller, storedChoice, NO);
            }
        });
    });
}

static UIButton *PACreateSelectorButton(void) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *configuration = [UIButtonConfiguration tintedButtonConfiguration];
        configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        configuration.baseForegroundColor = UIColor.labelColor;
        configuration.baseBackgroundColor = [UIColor.secondarySystemFillColor colorWithAlphaComponent:0.92];
        configuration.contentInsets = NSDirectionalEdgeInsetsMake(6, 11, 6, 11);
        button.configuration = configuration;
    } else {
        button.backgroundColor = UIColor.secondarySystemFillColor;
        button.layer.cornerRadius = 15.0;
        button.contentEdgeInsets = UIEdgeInsetsMake(6, 11, 6, 11);
    }
    button.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    button.adjustsImageWhenHighlighted = YES;
    PAUpdateButtonTitle(button, PASelectedLabel());
    return button;
}

static void PAInstallSelector(UIViewController *controller) {
    if (!PABoolPreference(PASelectorEnabledKey, YES)) return;
    if (objc_getAssociatedObject(controller, PAButtonAssociationKey)) {
        PACaptureMasterContacts(controller);
        return;
    }

    PACaptureMasterContacts(controller);
    UIButton *button = PACreateSelectorButton();
    objc_setAssociatedObject(controller, PAButtonAssociationKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIView *header = PAFindViewNamed(controller.view, @"PAStudioHeaderView");
    if (header) {
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [header addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-14.0],
            [button.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-10.0],
            [button.heightAnchor constraintEqualToConstant:32.0],
            [button.widthAnchor constraintGreaterThanOrEqualToConstant:112.0],
            [button.widthAnchor constraintLessThanOrEqualToConstant:210.0]
        ]];
    } else if (controller.navigationItem) {
        controller.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:button];
    } else {
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [controller.view addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.trailingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.trailingAnchor constant:-14.0],
            [button.topAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.topAnchor constant:8.0],
            [button.heightAnchor constraintEqualToConstant:32.0]
        ]];
    }

    PABuildMenu(controller, button);
}

static void PAHookedViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (PAOriginalViewDidAppear) {
        ((void (*)(id, SEL, BOOL))PAOriginalViewDidAppear)(self, _cmd, animated);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self isKindOfClass:UIViewController.class]) {
            PAInstallSelector((UIViewController *)self);
        }
    });
}

static void PAHookedContactsRefresh(id self, SEL _cmd) {
    if (PAOriginalContactsRefresh) {
        ((void (*)(id, SEL))PAOriginalContactsRefresh)(self, _cmd);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self isKindOfClass:UIViewController.class]) {
            PACaptureMasterContacts(self);
            UIButton *button = objc_getAssociatedObject(self, PAButtonAssociationKey);
            if (button) PABuildMenu((UIViewController *)self, button);
        }
    });
}

static void PAHookedContactsChanged(id self, SEL _cmd, id notification) {
    if (PAOriginalContactsChanged) {
        ((void (*)(id, SEL, id))PAOriginalContactsChanged)(self, _cmd, notification);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self isKindOfClass:UIViewController.class]) {
            objc_setAssociatedObject(self, PAMasterContactsAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            PACaptureMasterContacts(self);
            UIButton *button = objc_getAssociatedObject(self, PAButtonAssociationKey);
            if (button) PABuildMenu((UIViewController *)self, button);
        }
    });
}

static IMP PAReplaceMethod(Class cls, SEL selector, IMP replacement) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NULL;
    const char *types = method_getTypeEncoding(method);
    IMP original = class_getMethodImplementation(cls, selector);
    class_replaceMethod(cls, selector, replacement, types);
    return original;
}

static BOOL PAInstallHooks(void) {
    NSArray<NSString *> *candidates = @[@"PAContactsDashboardV46", @"PAContactsDashboardView"];
    for (NSString *name in candidates) {
        Class cls = NSClassFromString(name);
        if (!cls) continue;
        PAOriginalViewDidAppear = PAReplaceMethod(cls, @selector(viewDidAppear:), (IMP)PAHookedViewDidAppear);
        PAOriginalContactsRefresh = PAReplaceMethod(cls, NSSelectorFromString(@"pa47_contactsRefresh"), (IMP)PAHookedContactsRefresh);
        PAOriginalContactsChanged = PAReplaceMethod(cls, NSSelectorFromString(@"pa47_contactsDidChange:"), (IMP)PAHookedContactsChanged);
        return PAOriginalViewDidAppear != NULL;
    }
    return NO;
}

static void PAScheduleHookAttempt(NSUInteger attempt) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!PAInstallHooks() && attempt < 30) {
            PAScheduleHookAttempt(attempt + 1);
        }
    });
}

__attribute__((constructor)) static void PhoneAuraNativeFeaturesInitialize(void) {
    @autoreleasepool {
        PAScheduleHookAttempt(0);
    }
}
