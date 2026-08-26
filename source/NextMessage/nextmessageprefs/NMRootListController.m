#import "NMRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <QuartzCore/QuartzCore.h>
#import <spawn.h>

extern char **environ;

static NSString * const NMDomain = @"com.nextsolution.nextmessage";
static NSString * const NMNotification = @"com.nextsolution.nextmessage/preferences.changed";
static NSString * const NMRepoURL = @"https://nextjailbreak.com/";

@implementation NMRootListController

- (PSSpecifier *)groupNamed:(NSString *)name {
    return [PSSpecifier groupSpecifierWithName:name];
}

- (PSSpecifier *)switchNamed:(NSString *)name key:(NSString *)key defaultValue:(BOOL)defaultValue {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
                                                            target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil
                                                              cell:PSSwitchCell
                                                              edit:nil];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:@(defaultValue) forKey:@"default"];
    return specifier;
}

- (PSSpecifier *)sliderNamed:(NSString *)name key:(NSString *)key defaultValue:(CGFloat)value min:(CGFloat)minimum max:(CGFloat)maximum {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
                                                            target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil
                                                              cell:PSSliderCell
                                                              edit:nil];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:@(value) forKey:@"default"];
    [specifier setProperty:@(minimum) forKey:@"min"];
    [specifier setProperty:@(maximum) forKey:@"max"];
    [specifier setProperty:@YES forKey:@"showValue"];
    return specifier;
}

- (PSSpecifier *)buttonNamed:(NSString *)name action:(SEL)action destructive:(BOOL)destructive {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
                                                            target:self
                                                               set:nil
                                                               get:nil
                                                            detail:nil
                                                              cell:PSButtonCell
                                                              edit:nil];
    [specifier setButtonAction:action];
    if (destructive) [specifier setProperty:@YES forKey:@"isDestructive"];
    return specifier;
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];

    [items addObject:[self groupNamed:@"NEXT MESSAGE"]];
    [items addObject:[self switchNamed:@"Enable Next Message" key:@"enabled" defaultValue:YES]];

    [items addObject:[self groupNamed:@"PHONEAURA-STYLE DESIGN"]];
    [items addObject:[self switchNamed:@"Conversation Cards" key:@"conversationCards" defaultValue:YES]];
    [items addObject:[self switchNamed:@"Dark Glass Background" key:@"glassBackground" defaultValue:YES]];
    [items addObject:[self switchNamed:@"Styled Message Bubbles" key:@"bubbleStyling" defaultValue:YES]];
    [items addObject:[self switchNamed:@"Glass Message Input" key:@"inputStyling" defaultValue:YES]];
    [items addObject:[self sliderNamed:@"Card Opacity" key:@"cardOpacity" defaultValue:0.96 min:0.68 max:1.0]];
    [items addObject:[self sliderNamed:@"Corner Radius" key:@"cornerRadius" defaultValue:18.0 min:12.0 max:28.0]];

    [items addObject:[self groupNamed:@"CONVERSATION ACTIONS"]];
    [items addObject:[self switchNamed:@"Details Swipe Action" key:@"detailsSwipe" defaultValue:YES]];
    [items addObject:[self switchNamed:@"Show Message Count" key:@"showMessageCount" defaultValue:YES]];
    [items addObject:[self switchNamed:@"Show First Message Date" key:@"showFirstDate" defaultValue:YES]];
    [items addObject:[self switchNamed:@"Delete from Details Card" key:@"deleteFromCard" defaultValue:YES]];

    [items addObject:[self groupNamed:@"BEHAVIOR"]];
    [items addObject:[self switchNamed:@"Haptic Feedback" key:@"haptics" defaultValue:YES]];
    [items addObject:[self switchNamed:@"Fluid Animations" key:@"animations" defaultValue:YES]];
    [items addObject:[self buttonNamed:@"Restart Messages App" action:@selector(restartMessagesApp) destructive:NO]];
    [items addObject:[self buttonNamed:@"Reset Next Message Settings" action:@selector(resetPreferences) destructive:YES]];

    [items addObject:[self groupNamed:@"CREDITS & MORE"]];
    [items addObject:[self buttonNamed:@"Know more about other tweaks" action:@selector(openSileoRepo) destructive:NO]];

    _specifiers = [items copy];
    return _specifiers;
}

- (UIImage *)nextSolutionLogo {
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *path = [bundle pathForResource:@"icon" ofType:@"png"];
    UIImage *image = path.length ? [UIImage imageWithContentsOfFile:path] : nil;
    return image ?: [UIImage systemImageNamed:@"message.fill"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Next Message";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 178)];
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 16, screenWidth - 48, 142)];
    card.layer.cornerRadius = 26;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.masksToBounds = YES;
    [header addSubview:card];

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[(id)[UIColor colorWithRed:1.0 green:0.35 blue:0.37 alpha:1].CGColor,
                        (id)[UIColor colorWithRed:0.42 green:0.38 blue:1.0 alpha:1].CGColor,
                        (id)[UIColor colorWithRed:0.05 green:0.78 blue:0.72 alpha:1].CGColor];
    gradient.startPoint = CGPointMake(0, 0.25);
    gradient.endPoint = CGPointMake(1, 0.8);
    gradient.frame = card.bounds;
    [card.layer insertSublayer:gradient atIndex:0];

    UIImageView *logo = [[UIImageView alloc] initWithFrame:CGRectMake(20, 24, 74, 74)];
    logo.image = [self nextSolutionLogo];
    logo.contentMode = UIViewContentModeScaleAspectFill;
    logo.clipsToBounds = YES;
    logo.layer.cornerRadius = 18;
    logo.layer.borderWidth = 2;
    logo.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.65].CGColor;
    logo.tintColor = UIColor.whiteColor;
    [card addSubview:logo];

    UILabel *brand = [[UILabel alloc] initWithFrame:CGRectMake(110, 24, CGRectGetWidth(card.bounds)-128, 36)];
    brand.text = @"Next Solution";
    brand.textColor = UIColor.whiteColor;
    brand.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
    brand.adjustsFontSizeToFitWidth = YES;
    brand.minimumScaleFactor = 0.72;
    [card addSubview:brand];

    UILabel *product = [[UILabel alloc] initWithFrame:CGRectMake(111, 61, CGRectGetWidth(card.bounds)-128, 24)];
    product.text = @"Next Message 1.1.0";
    product.textColor = [UIColor colorWithWhite:1 alpha:0.88];
    product.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [card addSubview:product];

    UILabel *credits = [[UILabel alloc] initWithFrame:CGRectMake(111, 88, CGRectGetWidth(card.bounds)-128, 22)];
    credits.text = @"Credits: zeshan0727";
    credits.textColor = [UIColor colorWithWhite:1 alpha:0.78];
    credits.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [card addSubview:credits];

    self.table.tableHeaderView = header;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return nil;
    CFPreferencesAppSynchronize((__bridge CFStringRef)NMDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                           (__bridge CFStringRef)NMDomain));
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)NMDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)NMDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)NMNotification,
                                         NULL,
                                         NULL,
                                         true);
}

- (void)openSileoRepo {
    NSURL *sileoURL = [NSURL URLWithString:[NSString stringWithFormat:@"sileo://source/%@", NMRepoURL]];
    NSURL *webURL = [NSURL URLWithString:NMRepoURL];
    [[UIApplication sharedApplication] openURL:sileoURL options:@{} completionHandler:^(BOOL success) {
        if (!success && webURL) [[UIApplication sharedApplication] openURL:webURL options:@{} completionHandler:nil];
    }];
}

- (void)resetPreferences {
    NSArray *keys = @[@"enabled", @"conversationCards", @"glassBackground", @"bubbleStyling",
                      @"inputStyling", @"cardOpacity", @"cornerRadius", @"detailsSwipe",
                      @"showMessageCount", @"showFirstDate", @"deleteFromCard", @"haptics", @"animations"];
    for (NSString *key in keys) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)NMDomain);
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)NMDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)NMNotification,
                                         NULL, NULL, true);
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)restartMessagesApp {
    pid_t pid = 0;
    const char *arguments[] = {"killall", "-9", "MobileSMS", NULL};
    posix_spawnp(&pid, "killall", NULL, NULL, (char * const *)arguments, environ);
}

@end
