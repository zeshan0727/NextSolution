#import "PAConceptDUI.h"
#import <Contacts/Contacts.h>
#import <ContactsUI/ContactsUI.h>
#import <objc/runtime.h>

static const void *PA410MenuButtonKey = &PA410MenuButtonKey;

static NSString *PA410CleanDialValue(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) return @"";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"+0123456789*#"];
    NSMutableString *clean = [NSMutableString string];
    for (NSUInteger index = 0; index < value.length; index++) {
        unichar character = [value characterAtIndex:index];
        if ([allowed characterIsMember:character]) [clean appendFormat:@"%C", character];
    }
    return clean;
}

static NSString *PA410DigitsOnly(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) return @"";
    NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
    NSMutableString *clean = [NSMutableString string];
    for (NSUInteger index = 0; index < value.length; index++) {
        unichar character = [value characterAtIndex:index];
        if ([digits characterIsMember:character]) [clean appendFormat:@"%C", character];
    }
    return clean;
}

static NSString *PA410ContactName(CNContact *contact) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (contact.givenName.length) [parts addObject:contact.givenName];
    if (contact.middleName.length) [parts addObject:contact.middleName];
    if (contact.familyName.length) [parts addObject:contact.familyName];
    NSString *name = [parts componentsJoinedByString:@" "];
    if (name.length) return name;
    if (contact.nickname.length) return contact.nickname;
    if (contact.organizationName.length) return contact.organizationName;
    return @"Contact";
}

@interface PAStudioKeypadView (PAContactMenuV410Private) <CNContactPickerDelegate, CNContactViewControllerDelegate>
@property(nonatomic,copy) NSString *dialValue;
- (void)updateNumberDisplay;
@end

@implementation PAStudioKeypadView (PAKeypadContactMenuV410)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class keypadClass = NSClassFromString(@"PAStudioKeypadView");
        if (!keypadClass) return;

        NSArray<NSArray<NSString *> *> *pairs = @[
            @[@"initWithFrame:", @"pa410_initWithFrame:"],
            @[@"layoutSubviews", @"pa410_layoutSubviews"]
        ];

        for (NSArray<NSString *> *pair in pairs) {
            Method original = class_getInstanceMethod(keypadClass, NSSelectorFromString(pair[0]));
            Method replacement = class_getInstanceMethod(keypadClass, NSSelectorFromString(pair[1]));
            if (original && replacement) method_exchangeImplementations(original, replacement);
        }
    });
}

- (instancetype)pa410_initWithFrame:(CGRect)frame {
    PAStudioKeypadView *view = [self pa410_initWithFrame:frame];
    if (view) [view pa410_installContactMenu];
    return view;
}

- (void)pa410_installContactMenu {
    if (objc_getAssociatedObject(self, PA410MenuButtonKey)) return;

    UIButton *menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
    menuButton.tintColor = UIColor.whiteColor;
    menuButton.backgroundColor = PAColorHex(0xFF7A1A, 0.92);
    menuButton.layer.cornerRadius = 15.0;
    menuButton.layer.cornerCurve = kCACornerCurveContinuous;
    menuButton.layer.shadowColor = PAColorHex(0xFF7A1A, 1.0).CGColor;
    menuButton.layer.shadowOpacity = 0.30;
    menuButton.layer.shadowRadius = 9.0;
    menuButton.layer.shadowOffset = CGSizeMake(0, 4);
    menuButton.accessibilityLabel = @"Number options";

    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightBold];
    [menuButton setImage:[UIImage systemImageNamed:@"ellipsis" withConfiguration:configuration]
                forState:UIControlStateNormal];

    __weak typeof(self) weakSelf = self;
    UIAction *newContact = [UIAction actionWithTitle:@"Create New Contact"
                                               image:[UIImage systemImageNamed:@"person.crop.circle.badge.plus"]
                                          identifier:nil
                                             handler:^(__kindof UIAction *action) {
        [weakSelf pa410_createNewContact];
    }];
    UIAction *existingContact = [UIAction actionWithTitle:@"Add to Existing Contact"
                                                    image:[UIImage systemImageNamed:@"person.badge.plus"]
                                               identifier:nil
                                                  handler:^(__kindof UIAction *action) {
        [weakSelf pa410_chooseExistingContact];
    }];
    UIAction *paste = [UIAction actionWithTitle:@"Paste Copied Number"
                                          image:[UIImage systemImageNamed:@"doc.on.clipboard.fill"]
                                     identifier:nil
                                        handler:^(__kindof UIAction *action) {
        [weakSelf pa410_pasteNumber];
    }];
    UIAction *clear = [UIAction actionWithTitle:@"Clear Number"
                                          image:[UIImage systemImageNamed:@"delete.left.fill"]
                                     identifier:nil
                                        handler:^(__kindof UIAction *action) {
        weakSelf.dialValue = @"";
        [weakSelf updateNumberDisplay];
    }];
    clear.attributes = UIMenuElementAttributesDestructive;

    menuButton.menu = [UIMenu menuWithTitle:@"Number Options"
                                      image:nil
                                 identifier:nil
                                    options:UIMenuOptionsDisplayInline
                                   children:@[newContact, existingContact, paste, clear]];
    menuButton.showsMenuAsPrimaryAction = YES;

    UIView *numberCard = nil;
    UIButton *oldAddButton = nil;
    @try {
        numberCard = [self valueForKey:@"numberCard"];
        oldAddButton = [self valueForKey:@"addNumberButton"];
    } @catch (__unused NSException *exception) {
    }

    oldAddButton.hidden = YES;
    oldAddButton.userInteractionEnabled = NO;
    if (numberCard) [numberCard addSubview:menuButton];
    else [self addSubview:menuButton];

    objc_setAssociatedObject(self, PA410MenuButtonKey, menuButton, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)pa410_layoutSubviews {
    [self pa410_layoutSubviews];

    UIView *numberCard = nil;
    UILabel *numberLabel = nil;
    UIButton *oldAddButton = nil;
    UIButton *pasteButton = nil;
    UIButton *menuButton = objc_getAssociatedObject(self, PA410MenuButtonKey);

    @try {
        numberCard = [self valueForKey:@"numberCard"];
        numberLabel = [self valueForKey:@"numberLabel"];
        oldAddButton = [self valueForKey:@"addNumberButton"];
    } @catch (__unused NSException *exception) {
    }

    for (UIView *subview in numberCard.subviews) {
        if ([subview isKindOfClass:UIButton.class] &&
            [[(UIButton *)subview titleForState:UIControlStateNormal] containsString:@"Paste"]) {
            pasteButton = (UIButton *)subview;
            break;
        }
    }

    oldAddButton.hidden = YES;
    oldAddButton.userInteractionEnabled = NO;

    CGFloat cardWidth = CGRectGetWidth(numberCard.bounds);
    if (numberLabel && cardWidth > 0) {
        numberLabel.frame = CGRectMake(14.0, 7.0, cardWidth - 70.0, 34.0);
    }
    if (menuButton && cardWidth > 0) {
        menuButton.frame = CGRectMake(cardWidth - 43.0, 7.0, 34.0, 34.0);
        menuButton.layer.cornerRadius = 15.0;
        [numberCard bringSubviewToFront:menuButton];
    }
    if (pasteButton && cardWidth > 0) {
        pasteButton.frame = CGRectMake(10.0, 42.0, cardWidth - 20.0, 26.0);
        [pasteButton setTitle:@"  Paste Copied Number" forState:UIControlStateNormal];
        [numberCard bringSubviewToFront:pasteButton];
    }
}

- (NSString *)pa410_currentNumber {
    return PA410CleanDialValue(self.dialValue ?: @"");
}

- (UIViewController *)pa410_presentingController {
    UIResponder *responder = self;
    UIViewController *controller = nil;
    while ((responder = responder.nextResponder)) {
        if ([responder isKindOfClass:UIViewController.class]) {
            controller = (UIViewController *)responder;
            break;
        }
    }

    if (!controller) controller = self.window.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    if ([controller isKindOfClass:UINavigationController.class]) {
        controller = ((UINavigationController *)controller).visibleViewController ?: controller;
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        controller = ((UITabBarController *)controller).selectedViewController ?: controller;
    }
    return controller;
}

- (void)pa410_createNewContact {
    NSString *number = [self pa410_currentNumber];
    if (number.length == 0) {
        [self pa410_showMessage:@"Enter a number first" success:NO];
        return;
    }

    CNMutableContact *contact = [[CNMutableContact alloc] init];
    contact.phoneNumbers = @[
        [CNLabeledValue labeledValueWithLabel:CNLabelPhoneNumberMobile
                                        value:[CNPhoneNumber phoneNumberWithStringValue:number]]
    ];

    CNContactViewController *contactController =
        [CNContactViewController viewControllerForNewContact:contact];
    contactController.delegate = self;
    contactController.allowsActions = NO;
    contactController.allowsEditing = YES;

    UINavigationController *navigationController =
        [[UINavigationController alloc] initWithRootViewController:contactController];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;

    UIViewController *presenter = [self pa410_presentingController];
    if (!presenter) {
        [self pa410_showMessage:@"Unable to open Contacts" success:NO];
        return;
    }

    if (self.hapticsEnabled) {
        UIImpactFeedbackGenerator *generator =
            [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [generator impactOccurred];
    }
    [presenter presentViewController:navigationController animated:YES completion:nil];
}

- (void)pa410_chooseExistingContact {
    NSString *number = [self pa410_currentNumber];
    if (number.length == 0) {
        [self pa410_showMessage:@"Enter a number first" success:NO];
        return;
    }

    CNContactPickerViewController *picker = [[CNContactPickerViewController alloc] init];
    picker.delegate = self;
    picker.predicateForEnablingContact = [NSPredicate predicateWithValue:YES];

    UIViewController *presenter = [self pa410_presentingController];
    if (!presenter) {
        [self pa410_showMessage:@"Unable to open Contacts" success:NO];
        return;
    }
    [presenter presentViewController:picker animated:YES completion:nil];
}

- (void)pa410_pasteNumber {
    NSString *clean = PA410CleanDialValue(UIPasteboard.generalPasteboard.string ?: @"");
    if (clean.length == 0) {
        [self pa410_showMessage:@"No phone number copied" success:NO];
        return;
    }
    self.dialValue = clean;
    [self updateNumberDisplay];
    if (self.hapticsEnabled) {
        UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
        [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
    }
}

- (void)contactPicker:(CNContactPickerViewController *)picker didSelectContact:(CNContact *)contact {
    NSString *number = [self pa410_currentNumber];
    if (number.length == 0 || contact.identifier.length == 0) return;

    CNContactStore *store = [[CNContactStore alloc] init];
    NSArray *keys = @[
        CNContactIdentifierKey,
        CNContactGivenNameKey,
        CNContactMiddleNameKey,
        CNContactFamilyNameKey,
        CNContactNicknameKey,
        CNContactOrganizationNameKey,
        CNContactPhoneNumbersKey
    ];
    NSError *fetchError = nil;
    CNContact *fresh = [store unifiedContactWithIdentifier:contact.identifier
                                               keysToFetch:keys
                                                     error:&fetchError];
    if (!fresh || fetchError) {
        [self pa410_showMessage:@"Could not load contact" success:NO];
        return;
    }

    NSString *targetDigits = PA410DigitsOnly(number);
    for (CNLabeledValue<CNPhoneNumber *> *value in fresh.phoneNumbers) {
        if ([PA410DigitsOnly(value.value.stringValue) isEqualToString:targetDigits]) {
            [self pa410_showMessage:@"Number already saved" success:NO];
            return;
        }
    }

    CNMutableContact *mutableContact = [fresh mutableCopy];
    NSMutableArray *phoneNumbers = [mutableContact.phoneNumbers mutableCopy] ?: [NSMutableArray array];
    [phoneNumbers addObject:[CNLabeledValue labeledValueWithLabel:CNLabelPhoneNumberMobile
                                                           value:[CNPhoneNumber phoneNumberWithStringValue:number]]];
    mutableContact.phoneNumbers = phoneNumbers;

    CNSaveRequest *request = [[CNSaveRequest alloc] init];
    [request updateContact:mutableContact];
    NSError *saveError = nil;
    BOOL saved = [store executeSaveRequest:request error:&saveError];
    if (saved && !saveError) {
        NSString *message = [NSString stringWithFormat:@"Added to %@", PA410ContactName(fresh)];
        [self pa410_showMessage:message success:YES];
    } else {
        [self pa410_showMessage:@"Could not save number" success:NO];
    }
}

- (void)contactViewController:(CNContactViewController *)viewController
       didCompleteWithContact:(CNContact *)contact {
    [viewController.navigationController dismissViewControllerAnimated:YES completion:^{
        if (contact) [self pa410_showMessage:@"Contact saved" success:YES];
    }];
}

- (void)pa410_showMessage:(NSString *)message success:(BOOL)success {
    UILabel *numberLabel = nil;
    @try { numberLabel = [self valueForKey:@"numberLabel"]; }
    @catch (__unused NSException *exception) { return; }
    if (!numberLabel) return;

    numberLabel.text = message;
    numberLabel.textColor = success ? PAColorHex(0xC7FFE0, 1.0) : PAColorHex(0xFFE0E1, 1.0);
    if (self.hapticsEnabled) {
        UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
        [generator notificationOccurred:success ? UINotificationFeedbackTypeSuccess : UINotificationFeedbackTypeWarning];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        numberLabel.textColor = UIColor.whiteColor;
        [self updateNumberDisplay];
    });
}

@end
