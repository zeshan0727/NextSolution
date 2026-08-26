#import "PAConceptDUI.h"
#import <objc/runtime.h>

static const void *PA411PlaceholderLabelKey = &PA411PlaceholderLabelKey;

@interface PAStudioKeypadView (PAKeypadStableSuggestionsV411Private)
@property(nonatomic,copy) NSString *dialValue;
@end

static UIView *PA411SuggestionsCard(PAStudioKeypadView *keypad, UIView *numberCard) {
    for (UIView *candidate in keypad.subviews) {
        if (candidate == numberCard || candidate.hidden || candidate.subviews.count == 0) continue;

        NSUInteger suggestionButtonCount = 0;
        for (UIView *subview in candidate.subviews) {
            if (![subview isKindOfClass:UIButton.class]) continue;
            UIButton *button = (UIButton *)subview;
            if ((button.tag == 0 || button.tag == 1) && button.titleLabel.numberOfLines == 2) {
                suggestionButtonCount++;
            }
        }
        if (suggestionButtonCount >= 2) return candidate;
    }

    // The existing implementation can hide the card before this pass. Search hidden views too.
    for (UIView *candidate in keypad.subviews) {
        if (candidate == numberCard || candidate.subviews.count == 0) continue;

        NSUInteger suggestionButtonCount = 0;
        for (UIView *subview in candidate.subviews) {
            if (![subview isKindOfClass:UIButton.class]) continue;
            UIButton *button = (UIButton *)subview;
            if ((button.tag == 0 || button.tag == 1) && button.titleLabel.numberOfLines == 2) {
                suggestionButtonCount++;
            }
        }
        if (suggestionButtonCount >= 2) return candidate;
    }
    return nil;
}

static NSArray<UIButton *> *PA411SuggestionButtons(UIView *card) {
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    for (UIView *subview in card.subviews) {
        if (![subview isKindOfClass:UIButton.class]) continue;
        UIButton *button = (UIButton *)subview;
        if ((button.tag == 0 || button.tag == 1) && button.titleLabel.numberOfLines == 2) {
            [buttons addObject:button];
        }
    }
    [buttons sortUsingComparator:^NSComparisonResult(UIButton *left, UIButton *right) {
        if (left.tag < right.tag) return NSOrderedAscending;
        if (left.tag > right.tag) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return buttons;
}

@implementation PAStudioKeypadView (PAKeypadStableSuggestionsV411)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class keypadClass = NSClassFromString(@"PAStudioKeypadView");
        if (!keypadClass) return;

        Method original = class_getInstanceMethod(keypadClass, @selector(layoutSubviews));
        Method replacement = class_getInstanceMethod(keypadClass, @selector(pa411_layoutSubviews));
        if (original && replacement) method_exchangeImplementations(original, replacement);
    });
}

- (void)pa411_layoutSubviews {
    [self pa411_layoutSubviews];

    UIView *numberCard = nil;
    NSArray<UIView *> *keyButtons = nil;
    UIButton *callButton = nil;
    UIButton *deleteButton = nil;

    @try {
        numberCard = [self valueForKey:@"numberCard"];
        keyButtons = [self valueForKey:@"keyButtons"];
        callButton = [self valueForKey:@"callButton"];
        deleteButton = [self valueForKey:@"deleteButton"];
    } @catch (__unused NSException *exception) {
        return;
    }

    UIView *suggestionsCard = PA411SuggestionsCard(self, numberCard);
    if (!suggestionsCard || !numberCard || keyButtons.count == 0) return;

    NSArray<UIButton *> *suggestionButtons = PA411SuggestionButtons(suggestionsCard);
    UILabel *placeholderLabel = objc_getAssociatedObject(suggestionsCard, PA411PlaceholderLabelKey);
    if (!placeholderLabel) {
        placeholderLabel = [[UILabel alloc] init];
        placeholderLabel.textAlignment = NSTextAlignmentCenter;
        placeholderLabel.numberOfLines = 2;
        placeholderLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
        placeholderLabel.textColor = PAColorHex(0xB7C3DB, 1.0);
        placeholderLabel.adjustsFontSizeToFitWidth = YES;
        placeholderLabel.minimumScaleFactor = 0.82;
        placeholderLabel.userInteractionEnabled = NO;
        [suggestionsCard addSubview:placeholderLabel];
        objc_setAssociatedObject(suggestionsCard,
                                 PA411PlaceholderLabelKey,
                                 placeholderLabel,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSUInteger visibleMatches = 0;
    for (UIButton *button in suggestionButtons) {
        NSAttributedString *title = [button attributedTitleForState:UIControlStateNormal];
        if (!button.hidden && title.length > 0) visibleMatches++;
    }

    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat contentTop = CGRectGetMaxY(numberCard.frame) + 13.0;
    CGFloat suggestionsHeight = 68.0;

    // Always reserve the same suggestion area. It never collapses or moves the keypad.
    suggestionsCard.hidden = NO;
    suggestionsCard.frame = CGRectMake(22.0, contentTop, width - 44.0, suggestionsHeight);

    CGFloat inset = 7.0;
    CGFloat gap = 7.0;
    CGFloat available = CGRectGetWidth(suggestionsCard.bounds) - inset * 2.0;
    CGFloat buttonWidth = visibleMatches == 1 ? available : (available - gap) / 2.0;
    NSUInteger visibleIndex = 0;
    for (UIButton *button in suggestionButtons) {
        NSAttributedString *title = [button attributedTitleForState:UIControlStateNormal];
        if (button.hidden || title.length == 0) continue;
        button.frame = CGRectMake(inset + visibleIndex * (buttonWidth + gap),
                                  7.0,
                                  buttonWidth,
                                  suggestionsHeight - 14.0);
        visibleIndex++;
    }

    NSString *digits = @"";
    @try {
        NSString *dialValue = self.dialValue ?: @"";
        NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
        digits = [[dialValue componentsSeparatedByCharactersInSet:nonDigits] componentsJoinedByString:@""];
    } @catch (__unused NSException *exception) {
    }

    placeholderLabel.hidden = visibleMatches > 0;
    if (!placeholderLabel.hidden) {
        if (digits.length == 0) {
            placeholderLabel.text = @"Saved numbers will appear here";
        } else if (digits.length < 2) {
            placeholderLabel.text = @"Type one more digit to search";
        } else {
            placeholderLabel.text = @"Number not saved";
        }
        placeholderLabel.frame = CGRectInset(suggestionsCard.bounds, 12.0, 8.0);
        [suggestionsCard bringSubviewToFront:placeholderLabel];
    }

    contentTop = CGRectGetMaxY(suggestionsCard.frame) + 11.0;

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
}

@end
