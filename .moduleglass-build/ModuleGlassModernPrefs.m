#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static CFStringRef const MGPrefsDomain = CFSTR("com.nextsolution.unlockvibrate");
static NSString * const MGPrefsChanged = @"com.nextsolution.unlockvibrate/preferences.changed";
static const void *MGInstalledKey = &MGInstalledKey;
static const void *MGBridgeKey = &MGBridgeKey;
static const void *MGSliderValueLabelKey = &MGSliderValueLabelKey;

@interface MGLicenseManager : NSObject
@property (nonatomic, readonly) NSString *deviceID;
@property (nonatomic, readonly, getter=isActive) BOOL active;
+ (instancetype)shared;
- (void)refreshWithCompletion:(void (^)(BOOL active))completion;
- (NSURL *)checkoutURL;
@end

static id MGSend0(id target, SEL sel) {
    if (!target || ![target respondsToSelector:sel]) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(target,sel);
}
static void MGSend1(id target, SEL sel, id arg) {
    if (target && [target respondsToSelector:sel]) ((void(*)(id,SEL,id))objc_msgSend)(target,sel,arg);
}

static id MGPref(NSString *key) {
    CFPreferencesAppSynchronize(MGPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, MGPrefsDomain);
    return value ? CFBridgingRelease(value) : nil;
}
static BOOL MGPrefBool(NSString *key, BOOL fallback) {
    id v = MGPref(key); return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : fallback;
}
static double MGPrefDouble(NSString *key, double fallback) {
    id v = MGPref(key); return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : fallback;
}
static void MGSetPref(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, MGPrefsDomain);
    CFPreferencesAppSynchronize(MGPrefsDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)MGPrefsChanged, NULL, NULL, true);
}

static UIColor *MGCardColor(void) { return [UIColor secondarySystemGroupedBackgroundColor]; }
static UIColor *MGLabelColor(void) { return [UIColor labelColor]; }
static UIColor *MGSubColor(void) { return [UIColor secondaryLabelColor]; }
static UIColor *MGBlue(void) { return [UIColor colorWithRed:0.18 green:0.49 blue:0.98 alpha:1.0]; }
static UIColor *MGPurple(void) { return [UIColor colorWithRed:0.42 green:0.32 blue:0.98 alpha:1.0]; }

static UIView *MGRoundedCard(CGRect frame, CGFloat radius) {
    UIView *v = [[UIView alloc] initWithFrame:frame];
    v.backgroundColor = MGCardColor();
    v.layer.cornerRadius = radius;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.borderWidth = 0.5;
    v.layer.borderColor = [UIColor separatorColor].CGColor;
    v.clipsToBounds = YES;
    return v;
}
static UILabel *MGLabel(NSString *text, UIFont *font, UIColor *color) {
    UILabel *l = [UILabel new]; l.text = text; l.font = font; l.textColor = color; l.numberOfLines = 0; return l;
}
static UIImage *MGSymbol(NSString *name, CGFloat point) {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:point weight:UIImageSymbolWeightRegular];
    return [[UIImage systemImageNamed:name] imageWithConfiguration:cfg];
}
static UIImageView *MGSymbolView(NSString *name, UIColor *tint) {
    UIImageView *iv = [[UIImageView alloc] initWithImage:MGSymbol(name, 16)];
    iv.tintColor = tint ?: [UIColor tertiaryLabelColor];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    return iv;
}

@class MGModernActionBridge;

@interface MGLicenseViewController : UIViewController
@property (nonatomic, weak) MGModernActionBridge *bridge;
@end

@interface MGModernActionBridge : NSObject
@property (nonatomic, weak) UIViewController *controller;
@property (nonatomic, weak) UIButton *statusButton;
@property (nonatomic, weak) UIButton *licenseButton;
@property (nonatomic, weak) UIScrollView *scroll;
- (void)refreshLicenseUI;
- (void)switchChanged:(UISwitch *)sender;
- (void)sliderChanged:(UISlider *)sender;
- (void)buttonTapped:(UIButton *)sender;
- (void)licenseAction:(UIButton *)sender;
- (void)showLicense:(id)sender;
@end

static id MGSpecifierForSlot(id controller, NSString *slot) {
    NSArray *specs = MGSend0(controller, NSSelectorFromString(@"specifiers"));
    if (![specs isKindOfClass:NSArray.class]) {
        @try { specs = [controller valueForKey:@"_specifiers"]; } @catch (__unused NSException *e) { specs = nil; }
    }
    for (id spec in specs) {
        id value = nil;
        SEL prop = NSSelectorFromString(@"propertyForKey:");
        if ([spec respondsToSelector:prop]) value = ((id(*)(id,SEL,id))objc_msgSend)(spec,prop,@"moduleSlot");
        if ([[value description] isEqualToString:slot]) return spec;
    }
    return nil;
}

static UIButton *MGRowButton(UIView *card, CGRect frame, NSString *symbol, NSString *title, NSString *subtitle, NSString *identifier, id target, SEL action) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = frame; b.accessibilityIdentifier = identifier; b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    UIImageView *icon = MGSymbolView(symbol, [UIColor colorWithRed:.54 green:.60 blue:.72 alpha:1]);
    icon.frame = CGRectMake(16, (frame.size.height-22)/2, 22, 22); [b addSubview:icon];
    UILabel *t = MGLabel(title, [UIFont systemFontOfSize:15 weight:UIFontWeightMedium], MGLabelColor());
    t.frame = CGRectMake(50, subtitle.length?8:(frame.size.height-20)/2, frame.size.width-86, 22); t.adjustsFontSizeToFitWidth = YES; t.minimumScaleFactor = .72; [b addSubview:t];
    if (subtitle.length) { UILabel *s = MGLabel(subtitle, [UIFont systemFontOfSize:12], MGSubColor()); s.frame=CGRectMake(50,29,frame.size.width-86,18); s.adjustsFontSizeToFitWidth=YES; [b addSubview:s]; }
    UIImageView *chev = MGSymbolView(@"chevron.right", [UIColor tertiaryLabelColor]); chev.frame = CGRectMake(frame.size.width-28,(frame.size.height-16)/2,10,16); [b addSubview:chev];
    [card addSubview:b]; return b;
}
static void MGDivider(UIView *card, CGFloat y, CGFloat inset) {
    UIView *d=[[UIView alloc] initWithFrame:CGRectMake(inset,y,card.bounds.size.width-inset,0.5)]; d.backgroundColor=[UIColor separatorColor]; [card addSubview:d];
}

static CGFloat MGSectionHeader(UIScrollView *scroll, CGFloat y, CGFloat width, NSString *symbol, NSString *title) {
    UIImageView *iv = MGSymbolView(symbol, [UIColor colorWithRed:.48 green:.55 blue:.67 alpha:1]); iv.frame=CGRectMake(19,y+2,20,20); [scroll addSubview:iv];
    UILabel *l=MGLabel(title,[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold],[UIColor secondaryLabelColor]); l.frame=CGRectMake(48,y,width-66,24); [scroll addSubview:l];
    return y+30;
}

static CGFloat MGAddSwitchRow(UIView *card, CGFloat y, CGFloat h, NSString *symbol, NSString *title, NSString *subtitle, NSString *key, BOOL fallback, id target) {
    UIImageView *iv=MGSymbolView(symbol,[UIColor colorWithRed:.56 green:.62 blue:.73 alpha:1]); iv.frame=CGRectMake(16,y+(h-22)/2,22,22); [card addSubview:iv];
    UILabel *t=MGLabel(title,[UIFont systemFontOfSize:15 weight:UIFontWeightMedium],MGLabelColor()); t.frame=CGRectMake(50,y+(subtitle.length?7:(h-22)/2),card.bounds.size.width-130,22); t.adjustsFontSizeToFitWidth=YES; [card addSubview:t];
    if (subtitle.length) { UILabel *s=MGLabel(subtitle,[UIFont systemFontOfSize:12],MGSubColor()); s.frame=CGRectMake(50,y+29,card.bounds.size.width-130,17); s.adjustsFontSizeToFitWidth=YES; [card addSubview:s]; }
    UISwitch *sw=[UISwitch new]; sw.on=MGPrefBool(key,fallback); sw.accessibilityIdentifier=[@"pref:" stringByAppendingString:key]; CGSize sz=sw.bounds.size; sw.frame=CGRectMake(card.bounds.size.width-sz.width-16,y+(h-sz.height)/2,sz.width,sz.height); [sw addTarget:target action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged]; [card addSubview:sw];
    return y+h;
}
static CGFloat MGAddSliderRow(UIView *card, CGFloat y, CGFloat h, NSString *symbol, NSString *title, NSString *key, double fallback, double min, double max, id target) {
    UIImageView *iv=MGSymbolView(symbol,MGBlue()); iv.frame=CGRectMake(16,y+13,21,21); [card addSubview:iv];
    UILabel *t=MGLabel(title,[UIFont systemFontOfSize:15 weight:UIFontWeightMedium],MGLabelColor()); t.frame=CGRectMake(50,y+9,card.bounds.size.width-120,22); t.adjustsFontSizeToFitWidth=YES; [card addSubview:t];
    UILabel *v=MGLabel(@"",[UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular],[UIColor tertiaryLabelColor]); v.textAlignment=NSTextAlignmentRight; v.frame=CGRectMake(card.bounds.size.width-62,y+9,48,22); [card addSubview:v];
    UISlider *sl=[UISlider new]; sl.minimumValue=min; sl.maximumValue=max; sl.value=MGPrefDouble(key,fallback); sl.accessibilityIdentifier=[@"pref:" stringByAppendingString:key]; sl.frame=CGRectMake(50,y+36,card.bounds.size.width-66,27); [sl addTarget:target action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged]; [card addSubview:sl]; objc_setAssociatedObject(sl,MGSliderValueLabelKey,v,OBJC_ASSOCIATION_ASSIGN); v.text=[NSString stringWithFormat:@"%.2f",sl.value];
    return y+h;
}

@implementation MGLicenseViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"License & Device";
    self.view.backgroundColor=[UIColor systemGroupedBackgroundColor];
    CGFloat w=self.view.bounds.size.width, m=18, y=24;
    UILabel *brand=MGLabel(@"Next Solution",[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold],MGPurple()); brand.frame=CGRectMake(m,y,w-2*m,24); [self.view addSubview:brand]; y+=34;
    UILabel *title=MGLabel(@"Module Glass License",[UIFont systemFontOfSize:28 weight:UIFontWeightBold],MGLabelColor()); title.frame=CGRectMake(m,y,w-2*m,38); [self.view addSubview:title]; y+=48;
    MGLicenseManager *lic=[MGLicenseManager shared];
    UIView *card=MGRoundedCard(CGRectMake(m,y,w-2*m,190),20); [self.view addSubview:card];
    UILabel *status=MGLabel(lic.active?@"Activated ✓":@"Not Activated",[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold],lic.active?[UIColor systemGreenColor]:[UIColor systemOrangeColor]); status.frame=CGRectMake(18,15,card.bounds.size.width-36,24); [card addSubview:status];
    UILabel *price=MGLabel(@"$1.00  •  One-device lifetime license",[UIFont systemFontOfSize:15 weight:UIFontWeightMedium],MGLabelColor()); price.frame=CGRectMake(18,51,card.bounds.size.width-36,24); [card addSubview:price];
    UILabel *idTitle=MGLabel(@"DEVICE ID",[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold],MGSubColor()); idTitle.frame=CGRectMake(18,89,card.bounds.size.width-36,18); [card addSubview:idTitle];
    UILabel *device=MGLabel(lic.deviceID,[UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightSemibold],MGLabelColor()); device.frame=CGRectMake(18,108,card.bounds.size.width-36,24); device.adjustsFontSizeToFitWidth=YES; [card addSubview:device];
    UIButton *copy=[UIButton buttonWithType:UIButtonTypeSystem]; copy.frame=CGRectMake(18,145,130,34); [copy setTitle:@"Copy Device ID" forState:UIControlStateNormal]; copy.layer.cornerRadius=12; copy.backgroundColor=[UIColor tertiarySystemGroupedBackgroundColor]; copy.accessibilityIdentifier=@"license:copy"; [copy addTarget:self.bridge action:@selector(licenseAction:) forControlEvents:UIControlEventTouchUpInside]; [card addSubview:copy];
    y+=210;
    UIButton *buy=[UIButton buttonWithType:UIButtonTypeSystem]; buy.frame=CGRectMake(m,y,w-2*m,50); buy.layer.cornerRadius=16; buy.backgroundColor=MGBlue(); [buy setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; [buy setTitle:@"Buy Activation — $1.00" forState:UIControlStateNormal]; buy.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]; buy.accessibilityIdentifier=@"license:buy"; [buy addTarget:self.bridge action:@selector(licenseAction:) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:buy]; y+=62;
    UIButton *refresh=[UIButton buttonWithType:UIButtonTypeSystem]; refresh.frame=CGRectMake(m,y,w-2*m,48); refresh.layer.cornerRadius=16; refresh.backgroundColor=MGCardColor(); [refresh setTitle:@"Refresh Activation Status" forState:UIControlStateNormal]; refresh.accessibilityIdentifier=@"license:refresh"; [refresh addTarget:self.bridge action:@selector(licenseAction:) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:refresh];
}
@end

@implementation MGModernActionBridge
- (void)switchChanged:(UISwitch *)sender {
    NSString *key=[sender.accessibilityIdentifier stringByReplacingOccurrencesOfString:@"pref:" withString:@""];
    if (key.length) MGSetPref(key,@(sender.on));
}
- (void)sliderChanged:(UISlider *)sender {
    NSString *key=[sender.accessibilityIdentifier stringByReplacingOccurrencesOfString:@"pref:" withString:@""];
    if (key.length) MGSetPref(key,@(sender.value));
    UILabel *v=objc_getAssociatedObject(sender,MGSliderValueLabelKey); v.text=[NSString stringWithFormat:@"%.2f",sender.value];
}
- (void)buttonTapped:(UIButton *)sender {
    NSString *ident=sender.accessibilityIdentifier ?: @"";
    if ([ident hasPrefix:@"module:"]) {
        NSString *slot=[ident substringFromIndex:7]; id spec=MGSpecifierForSlot(self.controller,slot); MGSend1(self.controller,NSSelectorFromString(@"configureCCModuleBackground:"),spec); return;
    }
    if ([ident isEqualToString:@"action:volumeColor"]) { MGSend1(self.controller,NSSelectorFromString(@"chooseVolumeIconColor:"),nil); return; }
    if ([ident isEqualToString:@"action:reset"]) { MGSend1(self.controller,NSSelectorFromString(@"resetAllCCModuleBackgrounds:"),nil); return; }
    if ([ident isEqualToString:@"action:apply"]) { MGSend1(self.controller,NSSelectorFromString(@"applyCCModuleBackgrounds:"),nil); return; }
    if ([ident isEqualToString:@"action:respring"]) { MGSend1(self.controller,NSSelectorFromString(@"respringDevice:"),nil); return; }
}
- (void)licenseAction:(UIButton *)sender {
    NSString *ident=sender.accessibilityIdentifier ?: @"";
    MGLicenseManager *lic=[MGLicenseManager shared];
    if ([ident isEqualToString:@"license:buy"]) {
        NSURL *url=lic.checkoutURL;
        if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        return;
    }
    if ([ident isEqualToString:@"license:copy"]) { UIPasteboard.generalPasteboard.string=lic.deviceID; return; }
    if ([ident isEqualToString:@"license:refresh"]) {
        sender.enabled=NO; [sender setTitle:@"Checking…" forState:UIControlStateNormal];
        __weak UIButton *weak=sender; __weak typeof(self) ws=self;
        [lic refreshWithCompletion:^(BOOL active){ weak.enabled=YES; [weak setTitle:active?@"Activated ✓":@"Refresh Activation Status" forState:UIControlStateNormal]; [ws refreshLicenseUI]; }];
        return;
    }
}
- (void)showLicense:(id)sender {
    MGLicenseViewController *vc=[MGLicenseViewController new]; vc.bridge=self; [self.controller.navigationController pushViewController:vc animated:YES];
}
- (void)refreshLicenseUI {
    BOOL active=[MGLicenseManager shared].active;
    [self.statusButton setTitle:active?@"Activated  ✓":@"Buy  $1" forState:UIControlStateNormal];
    [self.statusButton setTitleColor:active?[UIColor systemGreenColor]:MGBlue() forState:UIControlStateNormal];
    [self.licenseButton setTitle:active?@"License & Device":@"Activate • $1.00" forState:UIControlStateNormal];
}
@end

static void MGInstallModernUI(UIViewController *vc) {
    if (!vc || objc_getAssociatedObject(vc,MGInstalledKey)) return;
    NSString *title=vc.title ?: vc.navigationItem.title ?: @"";
    if (![title containsString:@"Module"] && ![title containsString:@"Glass"] && ![title containsString:@"Background"]) return;
    objc_setAssociatedObject(vc,MGInstalledKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([vc.view isKindOfClass:UITableView.class]) ((UITableView *)vc.view).scrollEnabled=NO;
    CGFloat w=vc.view.bounds.size.width;
    UIScrollView *scroll=[[UIScrollView alloc] initWithFrame:vc.view.bounds];
    scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    scroll.backgroundColor=[UIColor systemGroupedBackgroundColor];
    scroll.alwaysBounceVertical=YES; scroll.showsVerticalScrollIndicator=YES; scroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
    [vc.view addSubview:scroll];
    MGModernActionBridge *bridge=[MGModernActionBridge new]; bridge.controller=vc; bridge.scroll=scroll; objc_setAssociatedObject(vc,MGBridgeKey,bridge,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat m=14, cardW=w-2*m, y=12;

    UIView *hero=MGRoundedCard(CGRectMake(m,y,cardW,158),22); hero.backgroundColor=[UIColor colorWithRed:.91 green:.95 blue:1 alpha:1]; [scroll addSubview:hero];
    CAGradientLayer *grad=[CAGradientLayer layer]; grad.frame=hero.bounds; grad.colors=@[(id)[UIColor colorWithRed:.86 green:.96 blue:1 alpha:.85].CGColor,(id)[UIColor colorWithRed:.94 green:.91 blue:1 alpha:.82].CGColor]; grad.startPoint=CGPointMake(0,0); grad.endPoint=CGPointMake(1,1); [hero.layer insertSublayer:grad atIndex:0];
    NSBundle *bundle=[NSBundle bundleForClass:[vc class]];
    NSString *iconPath=[bundle pathForResource:@"NextAura-cc-module-backgrounds" ofType:@"png"];
    UIImage *icon=iconPath?[UIImage imageWithContentsOfFile:iconPath]:MGSymbol(@"square.grid.2x2.fill",48);
    UIImageView *app=[[UIImageView alloc] initWithImage:icon]; app.frame=CGRectMake(16,33,78,78); app.contentMode=UIViewContentModeScaleAspectFit; app.layer.cornerRadius=18; app.clipsToBounds=YES; [hero addSubview:app];
    UILabel *brand=MGLabel(@"✦  Next Solution",[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold],[UIColor colorWithRed:.32 green:.34 blue:.48 alpha:1]); brand.frame=CGRectMake(108,18,cardW-250,24); brand.adjustsFontSizeToFitWidth=YES; [hero addSubview:brand];
    UILabel *name=MGLabel(@"Module Glass",[UIFont systemFontOfSize:28 weight:UIFontWeightBold],UIColor.blackColor); name.frame=CGRectMake(108,46,cardW-240,38); name.adjustsFontSizeToFitWidth=YES; name.minimumScaleFactor=.72; [hero addSubview:name];
    UILabel *sub=MGLabel(@"Customize and elevate your\nControl Center experience.",[UIFont systemFontOfSize:14],[UIColor colorWithRed:.30 green:.34 blue:.42 alpha:1]); sub.frame=CGRectMake(108,87,cardW-225,44); sub.adjustsFontSizeToFitWidth=YES; [hero addSubview:sub];
    UIButton *status=[UIButton buttonWithType:UIButtonTypeSystem]; status.frame=CGRectMake(cardW-132,20,114,36); status.layer.cornerRadius=18; status.backgroundColor=[UIColor colorWithWhite:1 alpha:.70]; status.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightMedium]; [status addTarget:bridge action:@selector(showLicense:) forControlEvents:UIControlEventTouchUpInside]; [hero addSubview:status]; bridge.statusButton=status;
    UIButton *lic=[UIButton buttonWithType:UIButtonTypeSystem]; lic.frame=CGRectMake(cardW-188,76,170,40); lic.layer.cornerRadius=17; lic.backgroundColor=[UIColor colorWithWhite:1 alpha:.72]; lic.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightMedium]; [lic setTitleColor:UIColor.blackColor forState:UIControlStateNormal]; [lic addTarget:bridge action:@selector(showLicense:) forControlEvents:UIControlEventTouchUpInside]; [hero addSubview:lic]; bridge.licenseButton=lic;
    [bridge refreshLicenseUI]; y+=176;

    y=MGSectionHeader(scroll,y,w,@"paintpalette",@"APPEARANCE");
    CGFloat appearanceH=56*3+76*3;
    UIView *appearance=MGRoundedCard(CGRectMake(m,y,cardW,appearanceH),18); [scroll addSubview:appearance]; CGFloat ry=0;
    ry=MGAddSwitchRow(appearance,ry,56,@"circle.dotted",@"Remove Module Blur",@"Disable the blur behind modules.",@"CCModuleRemoveBlur",YES,bridge); MGDivider(appearance,ry,16);
    ry=MGAddSwitchRow(appearance,ry,56,@"sparkles",@"Enable Module Background Images",@"Use background images for modules.",@"CCModuleBackgroundsEnabled",NO,bridge); MGDivider(appearance,ry,16);
    ry=MGAddSwitchRow(appearance,ry,56,@"ear",@"Glow Module Icons & Labels",@"Add a subtle glow to icons and labels.",@"CCModuleControlGlowEnabled",YES,bridge); MGDivider(appearance,ry,16);
    ry=MGAddSliderRow(appearance,ry,76,@"sparkles",@"Icon & Label Glow Intensity",@"CCModuleControlGlowIntensity",.8,.1,1.0,bridge); MGDivider(appearance,ry,16);
    ry=MGAddSliderRow(appearance,ry,76,@"circle.dashed",@"Background Image Opacity",@"CCModuleBackgroundOpacity",1.0,.25,1.0,bridge); MGDivider(appearance,ry,16);
    ry=MGAddSliderRow(appearance,ry,76,@"arrow.up.left.and.arrow.down.right",@"Background Image Scale",@"CCModuleBackgroundScale",1.0,.5,4.0,bridge);
    y+=appearanceH+18;

    y=MGSectionHeader(scroll,y,w,@"speaker.wave.2",@"MEDIA & SLIDERS");
    UIView *media=MGRoundedCard(CGRectMake(m,y,cardW,56*4),18); [scroll addSubview:media];
    MGRowButton(media,CGRectMake(0,0,cardW,56),@"sun.max",@"Choose or Remove Brightness",nil,@"module:brightness",bridge,@selector(buttonTapped:)); MGDivider(media,56,16);
    MGRowButton(media,CGRectMake(0,56,cardW,56),@"speaker.wave.2",@"Choose or Remove Volume",nil,@"module:volume",bridge,@selector(buttonTapped:)); MGDivider(media,112,16);
    MGAddSwitchRow(media,112,56,@"paintpalette",@"Custom Volume Icon Color",nil,@"CCModuleVolumeIconColorEnabled",NO,bridge); MGDivider(media,168,16);
    MGRowButton(media,CGRectMake(0,168,cardW,56),@"drop",@"Volume Icon Color",nil,@"action:volumeColor",bridge,@selector(buttonTapped:));
    y+=56*4+18;

    y=MGSectionHeader(scroll,y,w,@"dot.radiowaves.left.and.right",@"CONNECTIVITY & MEDIA");
    UIView *connect=MGRoundedCard(CGRectMake(m,y,cardW,56*3),18); [scroll addSubview:connect];
    MGRowButton(connect,CGRectMake(0,0,cardW,56),@"antenna.radiowaves.left.and.right",@"Choose or Remove Connectivity",nil,@"module:connectivity",bridge,@selector(buttonTapped:)); MGDivider(connect,56,16);
    MGRowButton(connect,CGRectMake(0,56,cardW,56),@"music.note",@"Choose or Remove Now Playing",nil,@"module:media",bridge,@selector(buttonTapped:)); MGDivider(connect,112,16);
    MGRowButton(connect,CGRectMake(0,112,cardW,56),@"rectangle.on.rectangle",@"Choose or Remove Screen Mirroring",nil,@"module:screenmirroring",bridge,@selector(buttonTapped:));
    y+=56*3+18;

    y=MGSectionHeader(scroll,y,w,@"square.grid.2x2",@"UTILITY MODULES");
    CGFloat gap=12,colW=(cardW-gap)/2.0; CGFloat utilH=48*4;
    UIView *u1=MGRoundedCard(CGRectMake(m,y,colW,utilH),16), *u2=MGRoundedCard(CGRectMake(m+colW+gap,y,colW,48*3),16); [scroll addSubview:u1]; [scroll addSubview:u2];
    NSArray *ul=@[@[@"scope",@"Focus",@"focus"],@[@"flashlight.on.fill",@"Flashlight",@"flashlight"],@[@"timer",@"Timer",@"timer"],@[@"plus.forwardslash.minus",@"Calculator",@"calculator"]];
    NSArray *ur=@[@[@"camera",@"Camera",@"camera"],@[@"lock.rotation",@"Orientation Lock",@"orientation"],@[@"record.circle",@"Screen Recording",@"screenrecording"]];
    for(NSUInteger i=0;i<ul.count;i++){ NSArray *a=ul[i]; MGRowButton(u1,CGRectMake(0,i*48,colW,48),a[0],a[1],nil,[@"module:" stringByAppendingString:a[2]],bridge,@selector(buttonTapped:)); if(i+1<ul.count) MGDivider(u1,(i+1)*48,14); }
    for(NSUInteger i=0;i<ur.count;i++){ NSArray *a=ur[i]; MGRowButton(u2,CGRectMake(0,i*48,colW,48),a[0],a[1],nil,[@"module:" stringByAppendingString:a[2]],bridge,@selector(buttonTapped:)); if(i+1<ur.count) MGDivider(u2,(i+1)*48,14); }
    y+=utilH+18;

    y=MGSectionHeader(scroll,y,w,@"ellipsis.circle",@"OTHER MODULES");
    UIView *o1=MGRoundedCard(CGRectMake(m,y,colW,48*3),16), *o2=MGRoundedCard(CGRectMake(m+colW+gap,y,colW,48*3),16); [scroll addSubview:o1]; [scroll addSubview:o2];
    NSArray *ol=@[@[@"battery.25",@"Low Power Mode",@"lowpower"],@[@"moon",@"Dark Mode",@"darkmode"],@[@"ear",@"Hearing",@"hearing"]];
    NSArray *orr=@[@[@"note.text",@"Notes",@"notes"],@[@"house",@"Home",@"home"],@[@"cube",@"Other Modules",@"other"]];
    for(NSUInteger i=0;i<ol.count;i++){ NSArray *a=ol[i]; MGRowButton(o1,CGRectMake(0,i*48,colW,48),a[0],a[1],nil,[@"module:" stringByAppendingString:a[2]],bridge,@selector(buttonTapped:)); if(i+1<ol.count) MGDivider(o1,(i+1)*48,14); }
    for(NSUInteger i=0;i<orr.count;i++){ NSArray *a=orr[i]; MGRowButton(o2,CGRectMake(0,i*48,colW,48),a[0],a[1],nil,[@"module:" stringByAppendingString:a[2]],bridge,@selector(buttonTapped:)); if(i+1<orr.count) MGDivider(o2,(i+1)*48,14); }
    y+=48*3+18;

    y=MGSectionHeader(scroll,y,w,@"wrench",@"MAINTENANCE");
    UIView *danger=MGRoundedCard(CGRectMake(m,y,cardW,62),18); danger.backgroundColor=[[UIColor systemRedColor] colorWithAlphaComponent:.07]; danger.layer.borderColor=[[UIColor systemRedColor] colorWithAlphaComponent:.28].CGColor; [scroll addSubview:danger];
    UIButton *reset=MGRowButton(danger,CGRectMake(0,0,cardW,62),@"trash",@"Remove All Module Images",@"This will remove all custom module images.",@"action:reset",bridge,@selector(buttonTapped:));
    [reset setTintColor:[UIColor systemRedColor]];
    for(UIView *sv in reset.subviews) if([sv isKindOfClass:UILabel.class]) ((UILabel*)sv).textColor=[UIColor systemRedColor];
    y+=80;

    y=MGSectionHeader(scroll,y,w,@"arrow.clockwise",@"APPLY & RESTART");
    UIView *apply=MGRoundedCard(CGRectMake(m,y,cardW,56*2),18); [scroll addSubview:apply];
    MGRowButton(apply,CGRectMake(0,0,cardW,56),@"checkmark.circle",@"Apply Module Glass",nil,@"action:apply",bridge,@selector(buttonTapped:)); MGDivider(apply,56,16);
    MGRowButton(apply,CGRectMake(0,56,cardW,56),@"arrow.triangle.2.circlepath",@"Respring",nil,@"action:respring",bridge,@selector(buttonTapped:));
    y+=130;
    scroll.contentSize=CGSizeMake(w,y+16);
    [[MGLicenseManager shared] refreshWithCompletion:^(__unused BOOL active){ [bridge refreshLicenseUI]; }];
}

static void (*origViewDidAppear)(id,SEL,BOOL);
static void mg_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (origViewDidAppear) origViewDidAppear(self,_cmd,animated);
    dispatch_async(dispatch_get_main_queue(), ^{ if ([self isKindOfClass:UIViewController.class]) MGInstallModernUI((UIViewController *)self); });
}

static void MGHookController(void) {
    Class cls=NSClassFromString(@"AuraCategoryListController");
    if(!cls) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ MSHookMessageEx(cls,@selector(viewDidAppear:),(IMP)mg_viewDidAppear,(IMP *)&origViewDidAppear); });
}

@interface MGBundleWatcher : NSObject
+ (instancetype)shared;
- (void)didLoad:(NSNotification *)n;
@end
@implementation MGBundleWatcher
+ (instancetype)shared { static MGBundleWatcher *x; static dispatch_once_t once; dispatch_once(&once,^{x=[MGBundleWatcher new];}); return x; }
- (void)didLoad:(NSNotification *)n { MGHookController(); }
@end

__attribute__((constructor)) static void MGModernPrefsInit(void) {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserver:[MGBundleWatcher shared] selector:@selector(didLoad:) name:NSBundleDidLoadNotification object:nil];
        dispatch_async(dispatch_get_main_queue(), ^{ MGHookController(); });
    }
}
