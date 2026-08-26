#import "PAConceptDUI.h"
#import <objc/runtime.h>
#import <rootless.h>

static const void *PA412BrandButtonConfiguredKey = &PA412BrandButtonConfiguredKey;
static NSString * const PA412YouTubeURL = @"https://youtube.com/@zeshan0727?si=RZC_H_WyuZsqY4zm";

@interface PAStudioKeypadView (PAKeypadBrandButtonV412Private)
@property(nonatomic,assign) BOOL hapticsEnabled;
@end

static UIImage *PA412NextSolutionLogo(void) {
    static UIImage *logo;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *candidatePaths = @[
            ROOT_PATH_NS(@"/Library/Application Support/PhoneAura/NextSolutionLogo.png"),
            @"/var/jb/Library/Application Support/PhoneAura/NextSolutionLogo.png",
            @"/Library/Application Support/PhoneAura/NextSolutionLogo.png"
        ];
        for (NSString *path in candidatePaths) {
            UIImage *candidate = [UIImage imageWithContentsOfFile:path];
            if (candidate) {
                logo = [candidate imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
                break;
            }
        }
    });
    return logo;
}

static UIButton *PA412ExistingKeypadMenuButton(UIView *numberCard) {
    if (!numberCard) return nil;
    for (UIView *subview in numberCard.subviews.reverseObjectEnumerator) {
        if (![subview isKindOfClass:UIButton.class]) continue;
        UIButton *button = (UIButton *)subview;
        if (button.menu || button.showsMenuAsPrimaryAction ||
            [button.accessibilityLabel isEqualToString:@"Number options"] ||
            [button.accessibilityLabel isEqualToString:@"Open Next Solution YouTube channel"]) {
            return button;
        }
    }
    return nil;
}

@implementation PAStudioKeypadView (PAKeypadBrandButtonV412)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class keypadClass = NSClassFromString(@"PAStudioKeypadView");
        if (!keypadClass) return;

        Method original = class_getInstanceMethod(keypadClass, @selector(layoutSubviews));
        Method replacement = class_getInstanceMethod(keypadClass, @selector(pa412_layoutSubviews));
        if (original && replacement) method_exchangeImplementations(original, replacement);
    });
}

- (void)pa412_layoutSubviews {
    [self pa412_layoutSubviews];

    UIView *numberCard = nil;
    UILabel *numberLabel = nil;
    @try {
        numberCard = [self valueForKey:@"numberCard"];
        numberLabel = [self valueForKey:@"numberLabel"];
    } @catch (__unused NSException *exception) {
        return;
    }

    UIButton *brandButton = PA412ExistingKeypadMenuButton(numberCard);
    if (!brandButton || !numberCard) return;

    if (![objc_getAssociatedObject(brandButton, PA412BrandButtonConfiguredKey) boolValue]) {
        brandButton.menu = nil;
        brandButton.showsMenuAsPrimaryAction = NO;
        [brandButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
        [brandButton addTarget:self
                        action:@selector(pa412_openNextSolutionYouTube)
              forControlEvents:UIControlEventTouchUpInside];
        brandButton.accessibilityLabel = @"Open Next Solution YouTube channel";
        brandButton.accessibilityHint = @"Opens the Next Solution channel in YouTube";
        objc_setAssociatedObject(brandButton,
                                 PA412BrandButtonConfiguredKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIImage *logo = PA412NextSolutionLogo();
    if (logo) {
        [brandButton setImage:logo forState:UIControlStateNormal];
        brandButton.imageView.contentMode = UIViewContentModeScaleAspectFill;
        brandButton.imageEdgeInsets = UIEdgeInsetsMake(1.0, 1.0, 1.0, 1.0);
    } else {
        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:19.0
                                                             weight:UIImageSymbolWeightSemibold];
        [brandButton setImage:[UIImage systemImageNamed:@"play.circle.fill"
                                        withConfiguration:configuration]
                     forState:UIControlStateNormal];
        brandButton.tintColor = UIColor.whiteColor;
    }

    brandButton.backgroundColor = UIColor.clearColor;
    brandButton.layer.cornerRadius = 19.0;
    brandButton.layer.cornerCurve = kCACornerCurveContinuous;
    brandButton.layer.masksToBounds = YES;
    brandButton.layer.borderWidth = 1.0;
    brandButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.30].CGColor;
    brandButton.layer.shadowOpacity = 0.0;

    CGFloat cardWidth = CGRectGetWidth(numberCard.bounds);
    if (cardWidth > 0.0) {
        brandButton.frame = CGRectMake(cardWidth - 47.0, 5.0, 38.0, 38.0);
        if (numberLabel) numberLabel.frame = CGRectMake(14.0, 7.0, cardWidth - 72.0, 34.0);
        [numberCard bringSubviewToFront:brandButton];
    }
}

- (void)pa412_openNextSolutionYouTube {
    if (self.hapticsEnabled) {
        UIImpactFeedbackGenerator *generator =
            [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator impactOccurred];
    }

    NSURL *url = [NSURL URLWithString:PA412YouTubeURL];
    if (!url) return;
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

@end
