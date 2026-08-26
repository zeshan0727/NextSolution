#import "PAConceptDUI.h"
#import "PADataStore.h"
#import <Contacts/Contacts.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static const void *PA49ContactsKey = &PA49ContactsKey;
static const void *PA49MatchesKey = &PA49MatchesKey;
static const void *PA49SuggestionsCardKey = &PA49SuggestionsCardKey;
static const void *PA49SuggestionButtonsKey = &PA49SuggestionButtonsKey;
static const void *PA49PasteButtonKey = &PA49PasteButtonKey;

static NSString *PA49DigitsOnly(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) return @"";
    NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger index = 0; index < value.length; index++) {
        unichar character = [value characterAtIndex:index];
        if ([digits characterIsMember:character]) [result appendFormat:@"%C", character];
    }
    return result;
}

static NSString *PA49CleanDialValue(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) return @"";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"+0123456789*#"];
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger index = 0; index < value.length; index++) {
        unichar character = [value characterAtIndex:index];
        if ([allowed characterIsMember:character]) [result appendFormat:@"%C", character];
    }
    return result;
}

static NSString *PA49ContactName(CNContact *contact) {
    if (!contact) return @"Saved Contact";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (contact.givenName.length) [parts addObject:contact.givenName];
    if (contact.middleName.length) [parts addObject:contact.middleName];
    if (contact.familyName.length) [parts addObject:contact.familyName];
    NSString *name = [parts componentsJoinedByString:@" "];
    if (name.length) return name;
    if (contact.nickname.length) return contact.nickname;
    if (contact.organizationName.length) return contact.organizationName;
    return @"Saved Contact";
}

static NSInteger PA49MatchScore(NSString *savedNumber, NSString *needle) {
    if (savedNumber.length == 0 || needle.length == 0) return NSIntegerMax;
    if ([savedNumber isEqualToString:needle]) return 0;
    if ([savedNumber hasPrefix:needle]) return 1;

    NSString *localNumber = savedNumber.length > 8
        ? [savedNumber substringFromIndex:savedNumber.length - 8]
        : savedNumber;
    if ([localNumber hasPrefix:needle]) return 2;
    if ([savedNumber containsString:needle]) return 3;
    return NSIntegerMax;
}

@interface PAStudioKeypadView (PAKeypadV49Private)
@property(nonatomic,copy) NSString *dialValue;
- (void)updateNumberDisplay;
@end

@implementation PAStudioKeypadView (PAKeypadEnhancementsV49)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class keypadClass = NSClassFromString(@"PAStudioKeypadView");
        if (!keypadClass) return;

        NSArray<NSArray<NSString *> *> *pairs = @[
            @[@"initWithFrame:", @"pa49_initWithFrame:"],
            @[@"layoutSubviews", @"pa49_layoutSubviews"],
            @[@"updateNumberDisplay", @"pa49_updateNumberDisplay"]
        ];

        for (NSArray<NSString *> *pair in pairs) {
            Method original = class_getInstanceMethod(keypadClass, NSSelectorFromString(pair[0]));
            Method replacement = class_getInstanceMethod(keypadClass, NSSelectorFromString(pair[1]));
            if (original && replacement) method_exchangeImplementations(original, replacement);
        }
    });
}

- (instancetype)pa49_initWithFrame:(CGRect)frame {
    PAStudioKeypadView *view = [self pa49_initWithFrame:frame];
    if (view) [view pa49_installKeypadEnhancements];
    return view;
}

- (void)pa49_installKeypadEnhancements {
    if (objc_getAssociatedObject(self, PA49PasteButtonKey)) return;

    UIView *suggestionsCard = [[UIView alloc] init];
    suggestionsCard.backgroundColor = PAColorHex(0x111A33, 0.98);
    suggestionsCard.layer.cornerRadius = 17.0;
    suggestionsCard.layer.cornerCurve = kCACornerCurveContinuous;
    suggestionsCard.layer.borderWidth = 0.8;
    suggestionsCard.layer.borderColor = PAColorHex(0x18C8B7, 0.30).CGColor;
    suggestionsCard.layer.shadowColor = UIColor.blackColor.CGColor;
    suggestionsCard.layer.shadowOpacity = 0.25;
    suggestionsCard.layer.shadowRadius = 12.0;
    suggestionsCard.layer.shadowOffset = CGSizeMake(0, 5);
    suggestionsCard.hidden = YES;
    [self addSubview:suggestionsCard];
    objc_setAssociatedObject(self, PA49SuggestionsCardKey, suggestionsCard, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSMutableArray<UIButton *> *suggestionButtons = [NSMutableArray array];
    for (NSUInteger index = 0; index < 2; index++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = index;
        button.backgroundColor = PAColorHex(index == 0 ? 0x182744 : 0x162B3C, 1.0);
        button.layer.cornerRadius = 13.0;
        button.layer.cornerCurve = kCACornerCurveContinuous;
        button.layer.borderWidth = 0.7;
        button.layer.borderColor = PAColorHex(index == 0 ? 0x6F63FF : 0x18C8B7, 0.34).CGColor;
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.contentEdgeInsets = UIEdgeInsetsMake(5, 11, 5, 9);
        button.titleLabel.numberOfLines = 2;
        button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [button addTarget:self action:@selector(pa49_savedContactTapped:) forControlEvents:UIControlEventTouchUpInside];
        button.hidden = YES;
        [suggestionsCard addSubview:button];
        [suggestionButtons addObject:button];
    }
    objc_setAssociatedObject(self, PA49SuggestionButtonsKey, suggestionButtons, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIButton *pasteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    pasteButton.tintColor = UIColor.whiteColor;
    pasteButton.backgroundColor = PAColorHex(0x6F63FF, 0.33);
    pasteButton.layer.cornerRadius = 11.0;
    pasteButton.layer.cornerCurve = kCACornerCurveContinuous;
    pasteButton.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold];
    [pasteButton setTitle:@"  Paste" forState:UIControlStateNormal];
    [pasteButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:12.0 weight:UIImageSymbolWeightSemibold];
    [pasteButton setImage:[UIImage systemImageNamed:@"doc.on.clipboard.fill" withConfiguration:configuration]
                  forState:UIControlStateNormal];
    [pasteButton addTarget:self action:@selector(pa49_pasteCopiedNumber) forControlEvents:UIControlEventTouchUpInside];

    @try {
        UIView *numberCard = [self valueForKey:@"numberCard"];
        [numberCard addSubview:pasteButton];
    } @catch (__unused NSException *exception) {
        [self addSubview:pasteButton];
    }
    objc_setAssociatedObject(self, PA49PasteButtonKey, pasteButton, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    __weak typeof(self) weakSelf = self;
    [[PADataStore sharedStore] allContactsWithCompletion:^(NSArray<CNContact *> *contacts) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        objc_setAssociatedObject(self, PA49ContactsKey, contacts ?: @[], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self pa49_refreshSavedContactSuggestions];
    }];
}

- (void)pa49_updateNumberDisplay {
    [self pa49_updateNumberDisplay];
    [self pa49_refreshSavedContactSuggestions];
}

- (void)pa49_refreshSavedContactSuggestions {
    NSArray<CNContact *> *contacts = objc_getAssociatedObject(self, PA49ContactsKey) ?: @[];
    NSString *needle = PA49DigitsOnly(self.dialValue ?: @"");
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    if (needle.length >= 2) {
        for (CNContact *contact in contacts) {
            for (CNLabeledValue<CNPhoneNumber *> *phoneValue in contact.phoneNumbers) {
                NSString *rawNumber = phoneValue.value.stringValue ?: @"";
                NSString *normalized = PA49DigitsOnly(rawNumber);
                NSInteger score = PA49MatchScore(normalized, needle);
                if (score == NSIntegerMax) continue;

                NSString *identity = [NSString stringWithFormat:@"%@|%@", contact.identifier ?: @"", normalized];
                if ([seen containsObject:identity]) continue;
                [seen addObject:identity];

                [candidates addObject:@{
                    @"contact": contact,
                    @"name": PA49ContactName(contact),
                    @"number": rawNumber,
                    @"normalized": normalized,
                    @"score": @(score)
                }];
            }
        }
    }

    [candidates sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSInteger leftScore = [left[@"score"] integerValue];
        NSInteger rightScore = [right[@"score"] integerValue];
        if (leftScore < rightScore) return NSOrderedAscending;
        if (leftScore > rightScore) return NSOrderedDescending;
        return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
    }];

    NSArray<NSDictionary *> *matches = candidates.count > 2
        ? [candidates subarrayWithRange:NSMakeRange(0, 2)]
        : [candidates copy];
    objc_setAssociatedObject(self, PA49MatchesKey, matches, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIView *card = objc_getAssociatedObject(self, PA49SuggestionsCardKey);
    NSArray<UIButton *> *buttons = objc_getAssociatedObject(self, PA49SuggestionButtonsKey) ?: @[];
    card.hidden = matches.count == 0;

    [buttons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
        if (index >= matches.count) {
            button.hidden = YES;
            [button setAttributedTitle:nil forState:UIControlStateNormal];
            return;
        }

        NSDictionary *match = matches[index];
        NSString *name = match[@"name"] ?: @"Saved Contact";
        NSString *number = match[@"number"] ?: @"";
        NSString *title = [NSString stringWithFormat:@"%@\n%@", name, number];
        NSMutableAttributedString *styled = [[NSMutableAttributedString alloc] initWithString:title];
        NSRange nameRange = NSMakeRange(0, name.length);
        NSRange numberRange = NSMakeRange(MIN(name.length + 1, title.length), number.length);
        [styled addAttributes:@{
            NSForegroundColorAttributeName: UIColor.whiteColor,
            NSFontAttributeName: [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold]
        } range:nameRange];
        if (numberRange.location + numberRange.length <= title.length) {
            [styled addAttributes:@{
                NSForegroundColorAttributeName: PAColorHex(0xB7C3DB, 1.0),
                NSFontAttributeName: [UIFont monospacedDigitSystemFontOfSize:10.5 weight:UIFontWeightMedium]
            } range:numberRange];
        }
        button.hidden = NO;
        [button setAttributedTitle:styled forState:UIControlStateNormal];
    }];

    [self setNeedsLayout];
}

- (void)pa49_savedContactTapped:(UIButton *)sender {
    NSArray<NSDictionary *> *matches = objc_getAssociatedObject(self, PA49MatchesKey) ?: @[];
    if (sender.tag >= matches.count) return;
    NSString *number = matches[sender.tag][@"number"] ?: @"";
    if (number.length == 0) return;

    self.dialValue = number;
    [self updateNumberDisplay];
    if (self.hapticsEnabled) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [generator impactOccurred];
    }
}

- (void)pa49_pasteCopiedNumber {
    NSString *copied = UIPasteboard.generalPasteboard.string ?: @"";
    NSString *clean = PA49CleanDialValue(copied);
    if (clean.length == 0) {
        [self pa49_showTemporaryMessage:@"No phone number copied"];
        if (self.hapticsEnabled) {
            UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
            [generator notificationOccurred:UINotificationFeedbackTypeWarning];
        }
        return;
    }

    self.dialValue = clean;
    [self updateNumberDisplay];
    if (self.hapticsEnabled) {
        UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
        [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
    }
}

- (void)pa49_showTemporaryMessage:(NSString *)message {
    UILabel *numberLabel = nil;
    @try { numberLabel = [self valueForKey:@"numberLabel"]; }
    @catch (__unused NSException *exception) { return; }
    if (!numberLabel) return;

    numberLabel.text = message;
    numberLabel.textColor = PAColorHex(0xFFE0E1, 1.0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        numberLabel.textColor = UIColor.whiteColor;
        [self updateNumberDisplay];
    });
}

- (void)pa49_layoutSubviews {
    [self pa49_layoutSubviews];

    UIView *numberCard = nil;
    UILabel *numberLabel = nil;
    UIButton *addNumberButton = nil;
    NSArray<UIView *> *keyButtons = nil;
    UIButton *callButton = nil;
    UIButton *deleteButton = nil;

    @try {
        numberCard = [self valueForKey:@"numberCard"];
        numberLabel = [self valueForKey:@"numberLabel"];
        addNumberButton = [self valueForKey:@"addNumberButton"];
        keyButtons = [self valueForKey:@"keyButtons"];
        callButton = [self valueForKey:@"callButton"];
        deleteButton = [self valueForKey:@"deleteButton"];
    } @catch (__unused NSException *exception) {
        return;
    }

    UIView *suggestionsCard = objc_getAssociatedObject(self, PA49SuggestionsCardKey);
    NSArray<UIButton *> *suggestionButtons = objc_getAssociatedObject(self, PA49SuggestionButtonsKey) ?: @[];
    UIButton *pasteButton = objc_getAssociatedObject(self, PA49PasteButtonKey);
    NSArray *matches = objc_getAssociatedObject(self, PA49MatchesKey) ?: @[];

    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat top = MAX(safe.top + 7.0, 7.0);
    CGFloat cardX = 22.0;
    CGFloat cardWidth = width - 44.0;
    CGFloat cardHeight = 76.0;

    numberCard.frame = CGRectMake(cardX, top, cardWidth, cardHeight);
    numberLabel.frame = CGRectMake(14.0, 7.0, cardWidth - 28.0, 34.0);

    CGFloat lowerWidth = (cardWidth - 30.0) / 2.0;
    addNumberButton.frame = CGRectMake(10.0, 42.0, lowerWidth, 26.0);
    pasteButton.frame = CGRectMake(CGRectGetMaxX(addNumberButton.frame) + 10.0, 42.0, lowerWidth, 26.0);

    CGFloat contentTop = CGRectGetMaxY(numberCard.frame) + 13.0;
    if (matches.count > 0) {
        CGFloat suggestionsHeight = 68.0;
        suggestionsCard.hidden = NO;
        suggestionsCard.frame = CGRectMake(22.0, contentTop, width - 44.0, suggestionsHeight);

        CGFloat inset = 7.0;
        CGFloat gap = 7.0;
        CGFloat available = CGRectGetWidth(suggestionsCard.bounds) - inset * 2.0;
        CGFloat buttonWidth = matches.count == 1 ? available : (available - gap) / 2.0;
        [suggestionButtons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
            if (index >= matches.count) return;
            button.frame = CGRectMake(inset + index * (buttonWidth + gap), 7.0, buttonWidth, suggestionsHeight - 14.0);
        }];
        contentTop = CGRectGetMaxY(suggestionsCard.frame) + 11.0;
    } else {
        suggestionsCard.hidden = YES;
        suggestionsCard.frame = CGRectZero;
    }

    CGFloat horizontalMargin = 36.0;
    CGFloat horizontalGap = 12.0;
    CGFloat keyWidth = floor((width - horizontalMargin * 2.0 - horizontalGap * 2.0) / 3.0);
    CGFloat verticalGap = 9.0;
    CGFloat actionHeight = 56.0;
    CGFloat bottomAllowance = actionHeight + 22.0;
    CGFloat availableGridHeight = height - safe.bottom - bottomAllowance - contentTop;
    CGFloat keyHeight = floor((availableGridHeight - verticalGap * 3.0) / 4.0);
    keyHeight = MAX(44.0, MIN(58.0, keyHeight));

    [keyButtons enumerateObjectsUsingBlock:^(UIView *button, NSUInteger index, BOOL *stop) {
        NSUInteger row = index / 3;
        NSUInteger column = index % 3;
        button.frame = CGRectMake(horizontalMargin + column * (keyWidth + horizontalGap),
                                  contentTop + row * (keyHeight + verticalGap),
                                  keyWidth,
                                  keyHeight);
    }];

    CGFloat gridBottom = contentTop + 4.0 * keyHeight + 3.0 * verticalGap;
    CGFloat actionWidth = 92.0;
    CGFloat actionY = MIN(gridBottom + 11.0, height - safe.bottom - actionHeight - 6.0);
    callButton.frame = CGRectMake((width - actionWidth) / 2.0, actionY, actionWidth, actionHeight);
    callButton.layer.cornerRadius = MIN(self.studioCornerRadius + 5.0, actionHeight / 2.0);
    deleteButton.frame = CGRectMake(CGRectGetMaxX(callButton.frame) + 25.0,
                                    actionY + 6.0,
                                    50.0,
                                    44.0);

    [self bringSubviewToFront:suggestionsCard];
    [numberCard bringSubviewToFront:pasteButton];
}

@end
