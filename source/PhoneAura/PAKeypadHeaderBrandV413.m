#import "PAConceptDUI.h"
#import <objc/runtime.h>
#import <rootless.h>

static const void *PA413KeypadHeaderKey = &PA413KeypadHeaderKey;
static NSString * const PA413YouTubeURL = @"https://youtube.com/@zeshan0727?si=RZC_H_WyuZsqY4zm";

@interface PAStudioHeaderView (PAKeypadHeaderBrandV413Private)
- (void)actionTapped;
@end

static UIImage *PA413NextSolutionLogo(void) {
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

@implementation PAStudioHeaderView (PAKeypadHeaderBrandV413)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class headerClass = NSClassFromString(@"PAStudioHeaderView");
        if (!headerClass) return;

        SEL originalSelector = @selector(configureTitle:subtitle:icon:accent:showSubtitle:);
        SEL replacementSelector = @selector(pa413_configureTitle:subtitle:icon:accent:showSubtitle:);
        Method original = class_getInstanceMethod(headerClass, originalSelector);
        Method replacement = class_getInstanceMethod(headerClass, replacementSelector);
        if (original && replacement) method_exchangeImplementations(original, replacement);
    });
}

- (void)pa413_configureTitle:(NSString *)title
                   subtitle:(NSString *)subtitle
                       icon:(NSString *)icon
                     accent:(UIColor *)accent
               showSubtitle:(BOOL)showSubtitle {
    [self pa413_configureTitle:title
                     subtitle:subtitle
                         icon:icon
                       accent:accent
                 showSubtitle:showSubtitle];

    UIButton *actionButton = nil;
    @try {
        actionButton = [self valueForKey:@"actionButton"];
    } @catch (__unused NSException *exception) {
        return;
    }
    if (!actionButton) return;

    BOOL isKeypad = [title isEqualToString:@"Keypad"];
    objc_setAssociatedObject(self,
                             PA413KeypadHeaderKey,
                             @(isKeypad),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [actionButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];

    if (!isKeypad) {
        [actionButton addTarget:self
                         action:@selector(actionTapped)
               forControlEvents:UIControlEventTouchUpInside];
        actionButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
        actionButton.imageEdgeInsets = UIEdgeInsetsZero;
        actionButton.layer.cornerRadius = 14.0;
        actionButton.layer.cornerCurve = kCACornerCurveContinuous;
        actionButton.layer.masksToBounds = NO;
        actionButton.layer.borderWidth = 0.0;
        actionButton.accessibilityLabel = nil;
        actionButton.accessibilityHint = nil;
        return;
    }

    [actionButton addTarget:self
                     action:@selector(pa413_openNextSolutionYouTube)
           forControlEvents:UIControlEventTouchUpInside];
    actionButton.accessibilityLabel = @"Open Next Solution YouTube channel";
    actionButton.accessibilityHint = @"Opens the Next Solution channel in YouTube";

    UIImage *logo = PA413NextSolutionLogo();
    if (logo) {
        [actionButton setImage:logo forState:UIControlStateNormal];
        actionButton.imageView.contentMode = UIViewContentModeScaleAspectFill;
        actionButton.imageEdgeInsets = UIEdgeInsetsMake(1.0, 1.0, 1.0, 1.0);
        actionButton.backgroundColor = UIColor.clearColor;
    } else {
        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                             weight:UIImageSymbolWeightSemibold];
        [actionButton setImage:[UIImage systemImageNamed:@"play.circle.fill"
                                            withConfiguration:configuration]
                       forState:UIControlStateNormal];
        actionButton.tintColor = UIColor.whiteColor;
        actionButton.backgroundColor = [accent colorWithAlphaComponent:0.94];
    }

    actionButton.layer.cornerRadius = 22.0;
    actionButton.layer.cornerCurve = kCACornerCurveContinuous;
    actionButton.layer.masksToBounds = YES;
    actionButton.layer.borderWidth = 1.0;
    actionButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.32].CGColor;
    actionButton.layer.shadowOpacity = 0.0;
}

- (void)pa413_openNextSolutionYouTube {
    NSURL *url = [NSURL URLWithString:PA413YouTubeURL];
    if (!url) return;

    UIImpactFeedbackGenerator *generator =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [generator impactOccurred];

    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

@end
