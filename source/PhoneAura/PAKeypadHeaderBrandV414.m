#import "PhoneAuraManager.h"
#import "PAConceptDUI.h"
#import <objc/runtime.h>
#import <rootless.h>

static NSString * const PA414YouTubeURL = @"https://youtube.com/@zeshan0727?si=RZC_H_WyuZsqY4zm";

@interface PhoneAuraManager (PAKeypadHeaderBrandV414Private)
- (void)configureChromeForIndex:(NSUInteger)index animated:(BOOL)animated;
- (void)headerAction;
@end

static id PA414SafeValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try { return [object valueForKey:key]; }
    @catch (__unused NSException *exception) { return nil; }
}

static UIImage *PA414NextSolutionLogo(void) {
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

static UIButton *PA414HeaderActionButton(id manager) {
    id header = PA414SafeValue(manager, @"header");
    id button = PA414SafeValue(header, @"actionButton");
    return [button isKindOfClass:UIButton.class] ? button : nil;
}

static void PA414ApplyKeypadLogo(id manager) {
    UIButton *button = PA414HeaderActionButton(manager);
    if (!button) return;

    UIImage *logo = PA414NextSolutionLogo();
    if (logo) {
        [button setImage:logo forState:UIControlStateNormal];
        button.imageView.contentMode = UIViewContentModeScaleAspectFill;
        button.imageEdgeInsets = UIEdgeInsetsMake(1.5, 1.5, 1.5, 1.5);
    } else {
        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:20.0
                                                             weight:UIImageSymbolWeightSemibold];
        [button setImage:[UIImage systemImageNamed:@"play.circle.fill"
                                  withConfiguration:configuration]
               forState:UIControlStateNormal];
        button.tintColor = UIColor.whiteColor;
        button.imageEdgeInsets = UIEdgeInsetsZero;
    }

    button.backgroundColor = UIColor.clearColor;
    button.layer.cornerRadius = 22.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.masksToBounds = YES;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.30].CGColor;
    button.layer.shadowOpacity = 0.0;
    button.accessibilityLabel = @"Open Next Solution YouTube channel";
    button.accessibilityHint = @"Opens the Next Solution channel in YouTube";
}

@implementation PhoneAuraManager (PAKeypadHeaderBrandV414)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class managerClass = NSClassFromString(@"PhoneAuraManager");
        if (!managerClass) return;

        Method originalConfigure = class_getInstanceMethod(managerClass, NSSelectorFromString(@"configureChromeForIndex:animated:"));
        Method replacementConfigure = class_getInstanceMethod(managerClass, @selector(pa414_configureChromeForIndex:animated:));
        if (originalConfigure && replacementConfigure) method_exchangeImplementations(originalConfigure, replacementConfigure);

        Method originalAction = class_getInstanceMethod(managerClass, NSSelectorFromString(@"headerAction"));
        Method replacementAction = class_getInstanceMethod(managerClass, @selector(pa414_headerAction));
        if (originalAction && replacementAction) method_exchangeImplementations(originalAction, replacementAction);
    });
}

- (void)pa414_configureChromeForIndex:(NSUInteger)index animated:(BOOL)animated {
    [self pa414_configureChromeForIndex:index animated:animated];

    UIButton *button = PA414HeaderActionButton(self);
    if (index == 3) {
        PA414ApplyKeypadLogo(self);
    } else if (button) {
        button.imageEdgeInsets = UIEdgeInsetsZero;
        button.imageView.contentMode = UIViewContentModeScaleAspectFit;
        button.layer.cornerRadius = 14.0;
        button.layer.cornerCurve = kCACornerCurveContinuous;
        button.layer.masksToBounds = NO;
        button.layer.borderWidth = 0.0;
        button.accessibilityLabel = nil;
        button.accessibilityHint = nil;
    }
}

- (void)pa414_headerAction {
    NSInteger auxiliaryMode = [PA414SafeValue(self, @"auxiliaryMode") integerValue];
    UITabBarController *tabController = PA414SafeValue(self, @"tabController");
    NSUInteger index = MIN(tabController.selectedIndex, (NSUInteger)4);

    if (auxiliaryMode == 0 && index == 3) {
        BOOL hapticsEnabled = [PA414SafeValue(self, @"haptics") boolValue];
        if (hapticsEnabled) {
            UIImpactFeedbackGenerator *generator =
                [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [generator impactOccurred];
        }
        NSURL *url = [NSURL URLWithString:PA414YouTubeURL];
        if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        return;
    }

    [self pa414_headerAction];
}

@end
