#import "PAStudioRootController.h"
#import <ContactsUI/ContactsUI.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <spawn.h>

extern char **environ;
static NSString * const PADomain = @"com.zeshan.phoneaura";
static NSString * const PANotification = @"com.zeshan.phoneaura/preferences.changed";
static NSString * const PARepoURL = @"https://nextjailbreak.com/";
static const void *PAControlKey = &PAControlKey;

@interface PAStudioRootController () <CNContactPickerDelegate>
@property(nonatomic,strong) NSArray<NSString *> *favoriteIdentifiers;
@end

@implementation PAStudioRootController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PhoneAura Studio";
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.035 blue:0.09 alpha:1.0];
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.tableView.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.favoriteIdentifiers = [self arrayPreference:@"favoriteIdentifiers"] ?: @[];
    [self buildHeader];
}

- (UIImage *)nextSolutionLogo {
    UIImage *image = [UIImage imageNamed:@"icon.png"];
    return image ?: [UIImage systemImageNamed:@"sparkles"];
}

- (void)buildHeader {
    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 184)];
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 18, screenWidth - 32, 146)];
    card.layer.cornerRadius = 26;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.masksToBounds = YES;
    [header addSubview:card];

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = card.bounds;
    gradient.colors = @[
        (id)[UIColor colorWithRed:1.0 green:0.34 blue:0.37 alpha:1].CGColor,
        (id)[UIColor colorWithRed:0.43 green:0.38 blue:1.0 alpha:1].CGColor,
        (id)[UIColor colorWithRed:0.04 green:0.74 blue:0.72 alpha:1].CGColor
    ];
    gradient.startPoint = CGPointMake(0, 0.15);
    gradient.endPoint = CGPointMake(1, 0.85);
    [card.layer insertSublayer:gradient atIndex:0];

    UIImageView *logo = [[UIImageView alloc] initWithFrame:CGRectMake(20, 24, 76, 76)];
    logo.image = [self nextSolutionLogo];
    logo.contentMode = UIViewContentModeScaleAspectFill;
    logo.clipsToBounds = YES;
    logo.layer.cornerRadius = 18;
    logo.layer.borderWidth = 2;
    logo.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.65].CGColor;
    logo.tintColor = UIColor.whiteColor;
    [card addSubview:logo];

    UILabel *brand = [[UILabel alloc] initWithFrame:CGRectMake(112, 24, CGRectGetWidth(card.bounds)-132, 38)];
    brand.text = @"Next Solution";
    brand.textColor = UIColor.whiteColor;
    brand.font = [UIFont systemFontOfSize:27 weight:UIFontWeightBold];
    brand.adjustsFontSizeToFitWidth = YES;
    brand.minimumScaleFactor = 0.72;
    [card addSubview:brand];

    UILabel *product = [[UILabel alloc] initWithFrame:CGRectMake(113, 64, CGRectGetWidth(card.bounds)-132, 23)];
    product.text = @"PhoneAura 0.4.8";
    product.textColor = [UIColor colorWithWhite:1 alpha:0.88];
    product.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [card addSubview:product];

    UILabel *credits = [[UILabel alloc] initWithFrame:CGRectMake(113, 91, CGRectGetWidth(card.bounds)-132, 22)];
    credits.text = @"Credits: zeshan0727";
    credits.textColor = [UIColor colorWithWhite:1 alpha:0.78];
    credits.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [card addSubview:credits];

    self.tableView.tableHeaderView = header;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 6; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 5;
        case 1: return 2;
        case 2: return 3;
        case 3: return 1;
        case 4: return 3;
        case 5: return 1;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"CUSTOM SURFACES", @"APPEARANCE", @"BEHAVIOR", @"FAVORITE CONTACTS", @"TOOLS", @"CREDITS & MORE"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return nil;
}

- (UITableViewCell *)switchCell:(NSString *)title key:(NSString *)key defaultValue:(BOOL)fallback {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.onTintColor = [UIColor colorWithRed:1 green:0.35 blue:0.38 alpha:1];
    toggle.on = [self boolPreference:key fallback:fallback];
    objc_setAssociatedObject(toggle, PAControlKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

- (UITableViewCell *)sliderCell:(NSString *)title key:(NSString *)key value:(CGFloat)value min:(CGFloat)minimum max:(CGFloat)maximum {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 155, 34)];
    slider.minimumValue = minimum;
    slider.maximumValue = maximum;
    slider.value = value;
    slider.minimumTrackTintColor = [UIColor colorWithRed:0.43 green:0.38 blue:1 alpha:1];
    objc_setAssociatedObject(slider, PAControlKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = slider;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        NSArray *titles = @[@"Enable PhoneAura", @"Replace Favorites", @"Replace Recents", @"Replace Contacts", @"Replace Keypad"];
        NSArray *keys = @[@"enabled", @"fullFavorites", @"fullRecents", @"fullContacts", @"fullKeypad"];
        return [self switchCell:titles[indexPath.row] key:keys[indexPath.row] defaultValue:YES];
    }

    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            return [self sliderCell:@"Card Opacity"
                                key:@"cardOpacity"
                              value:[self floatPreference:@"cardOpacity" fallback:0.96]
                                min:0.65
                                max:1.0];
        }
        return [self sliderCell:@"Corner Radius"
                            key:@"cornerRadius"
                          value:[self floatPreference:@"cornerRadius" fallback:16]
                            min:10
                            max:26];
    }

    if (indexPath.section == 2) {
        NSArray *titles = @[@"Header Subtitles", @"Haptic Feedback", @"Fluid Animations"];
        NSArray *keys = @[@"showSubtitles", @"haptics", @"animations"];
        return [self switchCell:titles[indexPath.row] key:keys[indexPath.row] defaultValue:YES];
    }

    if (indexPath.section == 3) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = @"Choose Favorite Contacts";
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (indexPath.section == 4) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = @[@"Restart Phone App", @"Open Phone App", @"Reset PhoneAura Settings"][indexPath.row];
        cell.textLabel.textColor = indexPath.row == 2 ? UIColor.systemRedColor : UIColor.labelColor;
        cell.accessoryType = indexPath.row == 1 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
        return cell;
    }

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = @"Know more about other tweaks";
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    cell.imageView.image = [UIImage systemImageNamed:@"shippingbox.fill"];
    cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.38 blue:1 alpha:1];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 3) {
        CNContactPickerViewController *picker = [[CNContactPickerViewController alloc] init];
        picker.delegate = self;
        picker.predicateForEnablingContact = [NSPredicate predicateWithFormat:@"phoneNumbers.@count > 0"];
        [self presentViewController:picker animated:YES completion:nil];
    } else if (indexPath.section == 4) {
        if (indexPath.row == 0) {
            [self restartPhone];
        } else if (indexPath.row == 1) {
            NSURL *url = [NSURL URLWithString:@"mobilephone://"];
            if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        } else {
            [self resetSettings];
        }
    } else if (indexPath.section == 5) {
        [self openSileoRepo];
    }
}

- (void)contactPicker:(CNContactPickerViewController *)picker didSelectContacts:(NSArray<CNContact *> *)contacts {
    NSMutableArray *identifiers = [NSMutableArray array];
    for (CNContact *contact in contacts) {
        if (contact.identifier.length) [identifiers addObject:contact.identifier];
        if (identifiers.count >= 4) break;
    }
    self.favoriteIdentifiers = identifiers;
    [self writeValue:identifiers key:@"favoriteIdentifiers"];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, PAControlKey);
    [self writeValue:@(sender.on) key:key];
}

- (void)sliderChanged:(UISlider *)sender {
    NSString *key = objc_getAssociatedObject(sender, PAControlKey);
    [self writeValue:@(sender.value) key:key];
}

- (id)preference:(NSString *)key {
    CFPreferencesAppSynchronize((__bridge CFStringRef)PADomain);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                       (__bridge CFStringRef)PADomain));
}

- (BOOL)boolPreference:(NSString *)key fallback:(BOOL)fallback {
    id value = [self preference:key];
    return value ? [value boolValue] : fallback;
}

- (CGFloat)floatPreference:(NSString *)key fallback:(CGFloat)fallback {
    id value = [self preference:key];
    return value ? [value doubleValue] : fallback;
}

- (NSArray *)arrayPreference:(NSString *)key {
    id value = [self preference:key];
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}

- (void)writeValue:(id)value key:(NSString *)key {
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)PADomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PADomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)PANotification,
                                         NULL,
                                         NULL,
                                         true);
}

- (void)openSileoRepo {
    NSString *sileoString = [NSString stringWithFormat:@"sileo://source/%@", PARepoURL];
    NSURL *sileoURL = [NSURL URLWithString:sileoString];
    NSURL *webURL = [NSURL URLWithString:PARepoURL];

    if (!sileoURL) {
        if (webURL) [UIApplication.sharedApplication openURL:webURL options:@{} completionHandler:nil];
        return;
    }

    [UIApplication.sharedApplication openURL:sileoURL
                                      options:@{}
                            completionHandler:^(BOOL success) {
        if (!success && webURL) {
            [UIApplication.sharedApplication openURL:webURL options:@{} completionHandler:nil];
        }
    }];
}

- (void)restartPhone {
    pid_t pid = 0;
    const char *arguments[] = {"killall", "-9", "MobilePhone", NULL};
    posix_spawnp(&pid, "killall", NULL, NULL, (char * const *)arguments, environ);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Phone App Restarted"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetSettings {
    NSArray *keys = @[@"enabled", @"fullFavorites", @"fullRecents", @"fullContacts", @"fullKeypad", @"cardOpacity", @"cornerRadius", @"showSubtitles", @"haptics", @"animations", @"favoriteIdentifiers"];
    for (NSString *key in keys) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                 NULL,
                                 (__bridge CFStringRef)PADomain);
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)PADomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)PANotification,
                                         NULL,
                                         NULL,
                                         true);
    self.favoriteIdentifiers = @[];
    [self.tableView reloadData];
}

@end
