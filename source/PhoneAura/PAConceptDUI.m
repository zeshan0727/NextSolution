#import "PAConceptDUI.h"
#import <QuartzCore/QuartzCore.h>

UIColor *PAColorHex(uint32_t hex, CGFloat alpha) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:alpha];
}

UIColor *PAAccentForIndex(NSUInteger index) {
    switch (index) {
        case 0: return PAColorHex(0xFF5B61, 1.0); // coral
        case 1: return PAColorHex(0x6F63FF, 1.0); // indigo
        case 2: return PAColorHex(0x18C8B7, 1.0); // teal
        case 3: return PAColorHex(0xFF7A1A, 1.0); // orange
        case 4: return PAColorHex(0xFF3E88, 1.0); // pink
        default: return PAColorHex(0x6F63FF, 1.0);
    }
}

NSArray<UIColor *> *PAPaletteForIndex(NSUInteger index) {
    switch (index) {
        case 0:
            return @[PAColorHex(0xFF5B61,1), PAColorHex(0x7C4DFF,1), PAColorHex(0x17B8B5,1), PAColorHex(0xFF7A1A,1)];
        case 1:
            return @[PAColorHex(0xFF5B61,1), PAColorHex(0x18C8B7,1), PAColorHex(0x3B82F6,1), PAColorHex(0x8B5CF6,1), PAColorHex(0x22C55E,1)];
        case 2:
            return @[PAColorHex(0x18C8B7,1), PAColorHex(0x14B8A6,1), PAColorHex(0x0EA5E9,1)];
        case 4:
            return @[PAColorHex(0xFF3E88,1), PAColorHex(0xFF8A1F,1), PAColorHex(0x8B5CF6,1)];
        default:
            return @[PAAccentForIndex(index)];
    }
}

#pragma mark - Header

@interface PAStudioHeaderView ()
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *subtitleLabel;
@property(nonatomic,strong) UIButton *actionButton;
@property(nonatomic,strong) CAGradientLayer *glowLayer;
@end

@implementation PAStudioHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = YES;

        _glowLayer = [CAGradientLayer layer];
        _glowLayer.startPoint = CGPointMake(0.0, 0.5);
        _glowLayer.endPoint = CGPointMake(1.0, 0.5);
        _glowLayer.opacity = 0.32;
        [self.layer insertSublayer:_glowLayer atIndex:0];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:35.0 weight:UIFontWeightBold];
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.72;
        [self addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
        _subtitleLabel.textColor = PAColorHex(0xA7B2CA, 1.0);
        _subtitleLabel.adjustsFontSizeToFitWidth = YES;
        _subtitleLabel.minimumScaleFactor = 0.78;
        [self addSubview:_subtitleLabel];

        _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _actionButton.tintColor = UIColor.whiteColor;
        _actionButton.layer.cornerRadius = 14.0;
        _actionButton.layer.cornerCurve = kCACornerCurveContinuous;
        _actionButton.layer.shadowOpacity = 0.28;
        _actionButton.layer.shadowRadius = 12.0;
        _actionButton.layer.shadowOffset = CGSizeMake(0, 5);
        [_actionButton addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_actionButton];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat buttonSize = 44.0;
    self.actionButton.frame = CGRectMake(CGRectGetWidth(self.bounds) - buttonSize, 8.0, buttonSize, buttonSize);
    CGFloat textWidth = CGRectGetMinX(self.actionButton.frame) - 12.0;
    self.titleLabel.frame = CGRectMake(0, -1.0, textWidth, 43.0);
    self.subtitleLabel.frame = CGRectMake(1.0, 41.0, textWidth, 21.0);
    self.glowLayer.frame = CGRectMake(-26.0, -4.0, CGRectGetWidth(self.bounds) * 0.76, 72.0);
}

- (void)configureTitle:(NSString *)title
              subtitle:(NSString *)subtitle
                  icon:(NSString *)icon
                accent:(UIColor *)accent
          showSubtitle:(BOOL)showSubtitle {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.subtitleLabel.hidden = !showSubtitle;

    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:18.0
                                                                                                   weight:UIImageSymbolWeightBold];
    [self.actionButton setImage:[UIImage systemImageNamed:icon withConfiguration:configuration]
                       forState:UIControlStateNormal];
    self.actionButton.backgroundColor = [accent colorWithAlphaComponent:0.94];
    self.actionButton.layer.shadowColor = accent.CGColor;
    self.glowLayer.colors = @[(id)[accent colorWithAlphaComponent:0.28].CGColor,
                              (id)[accent colorWithAlphaComponent:0.0].CGColor];
    [self setNeedsLayout];
}

- (void)actionTapped {
    if (self.actionHandler) self.actionHandler();
}

@end

#pragma mark - Dock

@interface PAStudioDockButton : UIControl
@property(nonatomic,strong) UIView *selectionBubble;
@property(nonatomic,strong) UIImageView *iconView;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UIColor *accent;
@property(nonatomic) NSUInteger itemIndex;
- (void)configureTitle:(NSString *)title icon:(NSString *)icon index:(NSUInteger)index;
- (void)setStudioSelected:(BOOL)selected animated:(BOOL)animated;
@end

@implementation PAStudioDockButton

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _selectionBubble = [[UIView alloc] init];
        _selectionBubble.userInteractionEnabled = NO;
        _selectionBubble.alpha = 0.0;
        _selectionBubble.layer.cornerRadius = 18.0;
        _selectionBubble.layer.cornerCurve = kCACornerCurveContinuous;
        [self addSubview:_selectionBubble];

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.tintColor = PAColorHex(0xA7B2CA, 1.0);
        [self addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:9.8 weight:UIFontWeightSemibold];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.textColor = PAColorHex(0xA7B2CA, 1.0);
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.65;
        [self addSubview:_titleLabel];
    }
    return self;
}

- (void)configureTitle:(NSString *)title icon:(NSString *)icon index:(NSUInteger)index {
    self.itemIndex = index;
    self.accent = PAAccentForIndex(index);
    self.titleLabel.text = title;
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:18.0
                                                                                                   weight:UIImageSymbolWeightSemibold];
    self.iconView.image = [UIImage systemImageNamed:icon withConfiguration:configuration];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat centerX = CGRectGetMidX(self.bounds);
    self.selectionBubble.frame = CGRectMake(centerX - 18.0, 4.0, 36.0, 36.0);
    self.iconView.frame = CGRectMake(centerX - 11.5, 10.5, 23.0, 23.0);
    self.titleLabel.frame = CGRectMake(2.0, 42.0, CGRectGetWidth(self.bounds) - 4.0, 15.0);
}

- (void)setStudioSelected:(BOOL)selected animated:(BOOL)animated {
    void (^changes)(void) = ^{
        self.selectionBubble.alpha = selected ? 1.0 : 0.0;
        self.selectionBubble.backgroundColor = [self.accent colorWithAlphaComponent:0.25];
        self.iconView.tintColor = selected ? self.accent : PAColorHex(0xA7B2CA, 1.0);
        self.titleLabel.textColor = selected ? self.accent : PAColorHex(0xA7B2CA, 1.0);
        self.iconView.transform = selected ? CGAffineTransformMakeScale(1.10, 1.10) : CGAffineTransformIdentity;
    };

    if (animated) {
        [UIView animateWithDuration:0.24
                              delay:0
             usingSpringWithDamping:0.72
              initialSpringVelocity:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:changes
                         completion:nil];
    } else {
        changes();
    }
}

@end

@interface PAStudioDock ()
@property(nonatomic,strong) UIVisualEffectView *blurView;
@property(nonatomic,strong) UIView *borderView;
@property(nonatomic,strong) NSArray<PAStudioDockButton *> *buttons;
@end

@implementation PAStudioDock

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 23.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.42;
        self.layer.shadowRadius = 20.0;
        self.layer.shadowOffset = CGSizeMake(0, 8);

        UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
        _blurView = [[UIVisualEffectView alloc] initWithEffect:effect];
        _blurView.clipsToBounds = YES;
        _blurView.layer.cornerRadius = 23.0;
        _blurView.layer.cornerCurve = kCACornerCurveContinuous;
        _blurView.backgroundColor = PAColorHex(0x111A33, 0.84);
        [self addSubview:_blurView];

        _borderView = [[UIView alloc] init];
        _borderView.userInteractionEnabled = NO;
        _borderView.layer.cornerRadius = 23.0;
        _borderView.layer.cornerCurve = kCACornerCurveContinuous;
        _borderView.layer.borderWidth = 0.8;
        _borderView.layer.borderColor = PAColorHex(0x8792AE, 0.28).CGColor;
        [self addSubview:_borderView];

        NSArray<NSString *> *titles = @[@"Favorites", @"Recents", @"Contacts", @"Keypad", @"Voicemail"];
        NSArray<NSString *> *icons = @[@"star.fill", @"clock.fill", @"person.fill", @"circle.grid.3x3.fill", @"recordingtape"];
        NSMutableArray *buttons = [NSMutableArray array];
        for (NSUInteger index = 0; index < titles.count; index++) {
            PAStudioDockButton *button = [[PAStudioDockButton alloc] init];
            [button configureTitle:titles[index] icon:icons[index] index:index];
            [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:button];
            [buttons addObject:button];
        }
        _buttons = buttons;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.blurView.frame = self.bounds;
    self.borderView.frame = self.bounds;
    CGFloat itemWidth = CGRectGetWidth(self.bounds) / MAX(self.buttons.count, 1);
    [self.buttons enumerateObjectsUsingBlock:^(PAStudioDockButton *button, NSUInteger index, BOOL *stop) {
        button.frame = CGRectMake(itemWidth * index, 0, itemWidth, CGRectGetHeight(self.bounds));
    }];
}

- (void)buttonTapped:(PAStudioDockButton *)sender {
    if (self.selectionHandler) self.selectionHandler(sender.itemIndex);
}

- (void)updateSelectedIndex:(NSUInteger)selectedIndex animated:(BOOL)animated {
    [self.buttons enumerateObjectsUsingBlock:^(PAStudioDockButton *button, NSUInteger index, BOOL *stop) {
        [button setStudioSelected:(index == selectedIndex) animated:animated];
    }];
}

@end

#pragma mark - Card background

@interface PAStudioCardBackgroundView ()
@property(nonatomic,strong) UIView *cardView;
@property(nonatomic,strong) UIView *accentStrip;
@property(nonatomic,strong) CAGradientLayer *gradientLayer;
@property(nonatomic) CGFloat currentCornerRadius;
@end

@implementation PAStudioCardBackgroundView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;

        _cardView = [[UIView alloc] init];
        _cardView.layer.cornerCurve = kCACornerCurveContinuous;
        _cardView.layer.borderWidth = 0.75;
        _cardView.layer.shadowColor = UIColor.blackColor.CGColor;
        _cardView.layer.shadowOpacity = 0.24;
        _cardView.layer.shadowRadius = 9.0;
        _cardView.layer.shadowOffset = CGSizeMake(0, 4);
        [self addSubview:_cardView];

        _gradientLayer = [CAGradientLayer layer];
        _gradientLayer.startPoint = CGPointMake(0.0, 0.5);
        _gradientLayer.endPoint = CGPointMake(1.0, 0.5);
        [_cardView.layer insertSublayer:_gradientLayer atIndex:0];

        _accentStrip = [[UIView alloc] init];
        [_cardView addSubview:_accentStrip];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.cardView.frame = CGRectInset(self.bounds, 11.0, 4.0);
    self.cardView.layer.cornerRadius = self.currentCornerRadius;
    self.gradientLayer.frame = self.cardView.bounds;
    self.gradientLayer.cornerRadius = self.currentCornerRadius;
    self.accentStrip.frame = CGRectMake(0, 0, 4.5, CGRectGetHeight(self.cardView.bounds));
    self.accentStrip.layer.cornerRadius = 2.25;
}

- (void)configureForTab:(NSUInteger)tabIndex
                    row:(NSUInteger)row
                opacity:(CGFloat)opacity
           cornerRadius:(CGFloat)cornerRadius {
    NSArray<UIColor *> *palette = PAPaletteForIndex(tabIndex);
    UIColor *accent = palette[row % palette.count];
    self.currentCornerRadius = cornerRadius;

    BOOL heroFavorite = (tabIndex == 0 && row == 0);
    BOOL heroContact = (tabIndex == 2 && row == 0);
    BOOL voicemailCard = (tabIndex == 4);

    UIColor *startColor = nil;
    UIColor *endColor = nil;
    if (heroFavorite) {
        startColor = [PAColorHex(0xFF5B61, 1.0) colorWithAlphaComponent:0.92 * opacity];
        endColor = [PAColorHex(0xFF7958, 1.0) colorWithAlphaComponent:0.72 * opacity];
    } else if (heroContact) {
        startColor = [PAColorHex(0x14B8A6, 1.0) colorWithAlphaComponent:0.78 * opacity];
        endColor = [PAColorHex(0x123A46, 1.0) colorWithAlphaComponent:0.94 * opacity];
    } else if (voicemailCard) {
        startColor = [accent colorWithAlphaComponent:0.70 * opacity];
        endColor = [PAColorHex(0x18213D, 1.0) colorWithAlphaComponent:0.94 * opacity];
    } else {
        startColor = [accent colorWithAlphaComponent:0.16 * opacity];
        endColor = [PAColorHex(0x151F3A, 1.0) colorWithAlphaComponent:0.96 * opacity];
    }

    self.gradientLayer.colors = @[(id)startColor.CGColor, (id)endColor.CGColor];
    self.cardView.layer.borderColor = [accent colorWithAlphaComponent:(heroFavorite || heroContact || voicemailCard) ? 0.42 : 0.20].CGColor;
    self.cardView.layer.shadowColor = [accent colorWithAlphaComponent:0.42].CGColor;
    self.accentStrip.backgroundColor = accent;
    self.accentStrip.hidden = heroFavorite || heroContact;
    [self setNeedsLayout];
}

@end

#pragma mark - Smart shortcuts

@interface PAStudioShortcutsView ()
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UIButton *editButton;
@property(nonatomic,strong) NSArray<UIButton *> *buttons;
@end

@implementation PAStudioShortcutsView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = @"Smart Shortcuts";
        _titleLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightBold];
        _titleLabel.textColor = UIColor.whiteColor;
        [self addSubview:_titleLabel];

        _editButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_editButton setTitle:@"Edit" forState:UIControlStateNormal];
        [_editButton setTitleColor:PAColorHex(0xFF5B61, 1.0) forState:UIControlStateNormal];
        _editButton.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        [self addSubview:_editButton];

        NSArray<NSString *> *titles = @[@"Family Group", @"Work Line", @"Voicemail", @"Create Shortcut"];
        NSArray<NSString *> *subtitles = @[@"4 members", @"Quick call", @"New messages", @"Add action"];
        NSArray<NSString *> *icons = @[@"person.2.fill", @"briefcase.fill", @"recordingtape", @"plus"];
        NSArray<UIColor *> *colors = @[PAColorHex(0x7C4DFF,1), PAColorHex(0xFF7A1A,1), PAColorHex(0x16C7B7,1), PAColorHex(0x26304D,1)];

        NSMutableArray *buttons = [NSMutableArray array];
        for (NSUInteger index = 0; index < titles.count; index++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.tag = index;
            button.tintColor = UIColor.whiteColor;
            button.backgroundColor = colors[index];
            button.layer.cornerRadius = 13.0;
            button.layer.cornerCurve = kCACornerCurveContinuous;
            button.layer.shadowColor = colors[index].CGColor;
            button.layer.shadowOpacity = 0.18;
            button.layer.shadowRadius = 8.0;
            button.layer.shadowOffset = CGSizeMake(0, 4);
            button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            button.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 7);
            button.titleLabel.numberOfLines = 2;
            button.titleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
            UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:14.0
                                                                                                           weight:UIImageSymbolWeightBold];
            [button setImage:[UIImage systemImageNamed:icons[index] withConfiguration:configuration]
                    forState:UIControlStateNormal];
            NSString *title = [NSString stringWithFormat:@"  %@\n  %@", titles[index], subtitles[index]];
            [button setTitle:title forState:UIControlStateNormal];
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            [button addTarget:self action:@selector(shortcutTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:button];
            [buttons addObject:button];
        }
        _buttons = buttons;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.titleLabel.frame = CGRectMake(16.0, 5.0, CGRectGetWidth(self.bounds) - 90.0, 24.0);
    self.editButton.frame = CGRectMake(CGRectGetWidth(self.bounds) - 62.0, 4.0, 46.0, 26.0);

    CGFloat gap = 9.0;
    CGFloat width = (CGRectGetWidth(self.bounds) - 32.0 - gap) / 2.0;
    CGFloat height = 50.0;
    [self.buttons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
        NSUInteger row = index / 2;
        NSUInteger column = index % 2;
        button.frame = CGRectMake(16.0 + column * (width + gap), 35.0 + row * (height + gap), width, height);
    }];
}

- (void)shortcutTapped:(UIButton *)sender {
    if (self.tapHandler) self.tapHandler(sender.tag);
}

@end

#pragma mark - Custom keypad

@interface PAStudioKeyButton : UIControl
@property(nonatomic,strong) UILabel *digitLabel;
@property(nonatomic,strong) UILabel *lettersLabel;
@property(nonatomic,strong) UIView *surfaceView;
@property(nonatomic,copy) NSString *value;
- (void)configureDigit:(NSString *)digit letters:(NSString *)letters;
@end

@implementation PAStudioKeyButton

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _surfaceView = [[UIView alloc] init];
        _surfaceView.userInteractionEnabled = NO;
        _surfaceView.backgroundColor = PAColorHex(0x1A2440, 0.98);
        _surfaceView.layer.cornerRadius = 15.0;
        _surfaceView.layer.cornerCurve = kCACornerCurveContinuous;
        _surfaceView.layer.borderWidth = 0.8;
        _surfaceView.layer.borderColor = PAColorHex(0x61708E, 0.26).CGColor;
        _surfaceView.layer.shadowColor = UIColor.blackColor.CGColor;
        _surfaceView.layer.shadowOpacity = 0.25;
        _surfaceView.layer.shadowRadius = 8.0;
        _surfaceView.layer.shadowOffset = CGSizeMake(0, 4);
        [self addSubview:_surfaceView];

        _digitLabel = [[UILabel alloc] init];
        _digitLabel.textColor = UIColor.whiteColor;
        _digitLabel.font = [UIFont systemFontOfSize:29.0 weight:UIFontWeightSemibold];
        _digitLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_digitLabel];

        _lettersLabel = [[UILabel alloc] init];
        _lettersLabel.textColor = PAColorHex(0xC8D0E2, 1.0);
        _lettersLabel.font = [UIFont systemFontOfSize:9.0 weight:UIFontWeightBold];
        _lettersLabel.textAlignment = NSTextAlignmentCenter;
        _lettersLabel.layer.opacity = 0.92;
        [self addSubview:_lettersLabel];

        [self addTarget:self action:@selector(touchDown) forControlEvents:UIControlEventTouchDown];
        [self addTarget:self action:@selector(touchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    }
    return self;
}

- (void)configureDigit:(NSString *)digit letters:(NSString *)letters {
    self.value = digit;
    self.digitLabel.text = digit;
    self.lettersLabel.text = letters;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.surfaceView.frame = self.bounds;
    CGFloat digitY = self.lettersLabel.text.length > 0 ? 5.0 : 10.0;
    self.digitLabel.frame = CGRectMake(0, digitY, CGRectGetWidth(self.bounds), 36.0);
    self.lettersLabel.frame = CGRectMake(0, 37.0, CGRectGetWidth(self.bounds), 14.0);
}

- (void)touchDown {
    [UIView animateWithDuration:0.10 animations:^{
        self.transform = CGAffineTransformMakeScale(0.94, 0.94);
        self.surfaceView.backgroundColor = PAColorHex(0x2A3657, 1.0);
    }];
}

- (void)touchUp {
    [UIView animateWithDuration:0.14 animations:^{
        self.transform = CGAffineTransformIdentity;
        self.surfaceView.backgroundColor = PAColorHex(0x1A2440, 0.98);
    }];
}

@end

@interface PAStudioKeypadView ()
@property(nonatomic,strong) UIView *numberCard;
@property(nonatomic,strong) CAGradientLayer *numberGradient;
@property(nonatomic,strong) UILabel *numberLabel;
@property(nonatomic,strong) UIButton *addNumberButton;
@property(nonatomic,strong) NSArray<PAStudioKeyButton *> *keyButtons;
@property(nonatomic,strong) UIButton *callButton;
@property(nonatomic,strong) UIButton *deleteButton;
@property(nonatomic,copy) NSString *dialValue;
@end

@implementation PAStudioKeypadView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;
        _dialValue = @"";
        _studioCornerRadius = 16.0;

        _numberCard = [[UIView alloc] init];
        _numberCard.layer.cornerCurve = kCACornerCurveContinuous;
        _numberCard.layer.shadowColor = PAColorHex(0xFF7A1A, 1.0).CGColor;
        _numberCard.layer.shadowOpacity = 0.28;
        _numberCard.layer.shadowRadius = 15.0;
        _numberCard.layer.shadowOffset = CGSizeMake(0, 6);
        [self addSubview:_numberCard];

        _numberGradient = [CAGradientLayer layer];
        _numberGradient.startPoint = CGPointMake(0.0, 0.5);
        _numberGradient.endPoint = CGPointMake(1.0, 0.5);
        _numberGradient.colors = @[(id)PAColorHex(0xFF4F4F, 1.0).CGColor,
                                   (id)PAColorHex(0xFF7A1A, 1.0).CGColor];
        [_numberCard.layer insertSublayer:_numberGradient atIndex:0];

        _numberLabel = [[UILabel alloc] init];
        _numberLabel.text = @"Enter number";
        _numberLabel.textAlignment = NSTextAlignmentCenter;
        _numberLabel.textColor = UIColor.whiteColor;
        _numberLabel.font = [UIFont monospacedDigitSystemFontOfSize:25.0 weight:UIFontWeightBold];
        _numberLabel.adjustsFontSizeToFitWidth = YES;
        _numberLabel.minimumScaleFactor = 0.62;
        [_numberCard addSubview:_numberLabel];

        _addNumberButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_addNumberButton setTitle:@"Add Number" forState:UIControlStateNormal];
        [_addNumberButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.92] forState:UIControlStateNormal];
        _addNumberButton.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
        [_addNumberButton addTarget:self action:@selector(addNumberTapped) forControlEvents:UIControlEventTouchUpInside];
        [_numberCard addSubview:_addNumberButton];

        NSArray<NSString *> *digits = @[@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"*", @"0", @"#"];
        NSArray<NSString *> *letters = @[@"", @"ABC", @"DEF", @"GHI", @"JKL", @"MNO", @"PQRS", @"TUV", @"WXYZ", @"", @"+", @""];
        NSMutableArray *keys = [NSMutableArray array];
        for (NSUInteger index = 0; index < digits.count; index++) {
            PAStudioKeyButton *button = [[PAStudioKeyButton alloc] init];
            [button configureDigit:digits[index] letters:letters[index]];
            button.tag = index;
            [button addTarget:self action:@selector(keyTapped:) forControlEvents:UIControlEventTouchUpInside];
            if ([digits[index] isEqualToString:@"0"]) {
                UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(zeroLongPressed:)];
                [button addGestureRecognizer:longPress];
            }
            [self addSubview:button];
            [keys addObject:button];
        }
        _keyButtons = keys;

        _callButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _callButton.tintColor = UIColor.whiteColor;
        _callButton.backgroundColor = PAColorHex(0x31C85A, 1.0);
        _callButton.layer.cornerRadius = 22.0;
        _callButton.layer.cornerCurve = kCACornerCurveContinuous;
        _callButton.layer.shadowColor = PAColorHex(0x31C85A, 1.0).CGColor;
        _callButton.layer.shadowOpacity = 0.42;
        _callButton.layer.shadowRadius = 18.0;
        _callButton.layer.shadowOffset = CGSizeMake(0, 7);
        UIImageSymbolConfiguration *callConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:25.0 weight:UIImageSymbolWeightBold];
        [_callButton setImage:[UIImage systemImageNamed:@"phone.fill" withConfiguration:callConfiguration]
                     forState:UIControlStateNormal];
        [_callButton addTarget:self action:@selector(callTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_callButton];

        _deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _deleteButton.tintColor = PAColorHex(0xC7D0E3, 1.0);
        _deleteButton.backgroundColor = PAColorHex(0x1A2440, 0.96);
        _deleteButton.layer.cornerRadius = 15.0;
        _deleteButton.layer.cornerCurve = kCACornerCurveContinuous;
        UIImageSymbolConfiguration *deleteConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:21.0 weight:UIImageSymbolWeightBold];
        [_deleteButton setImage:[UIImage systemImageNamed:@"delete.left.fill" withConfiguration:deleteConfiguration]
                       forState:UIControlStateNormal];
        [_deleteButton addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *clearPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(deleteLongPressed:)];
        [_deleteButton addGestureRecognizer:clearPress];
        [self addSubview:_deleteButton];
    }
    return self;
}

- (void)setStudioCornerRadius:(CGFloat)studioCornerRadius {
    _studioCornerRadius = MAX(10.0, MIN(studioCornerRadius, 24.0));
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    UIEdgeInsets safe = self.safeAreaInsets;

    CGFloat availableTop = MAX(safe.top + 7.0, 7.0);
    CGFloat cardX = 22.0;
    CGFloat cardWidth = width - 44.0;
    CGFloat cardHeight = 72.0;
    self.numberCard.frame = CGRectMake(cardX, availableTop, cardWidth, cardHeight);
    self.numberCard.layer.cornerRadius = self.studioCornerRadius;
    self.numberGradient.frame = self.numberCard.bounds;
    self.numberGradient.cornerRadius = self.studioCornerRadius;
    self.numberLabel.frame = CGRectMake(14.0, 8.0, cardWidth - 28.0, 34.0);
    self.addNumberButton.frame = CGRectMake(12.0, 40.0, cardWidth - 24.0, 24.0);

    CGFloat horizontalMargin = 36.0;
    CGFloat horizontalGap = 12.0;
    CGFloat keyWidth = floor((width - horizontalMargin * 2.0 - horizontalGap * 2.0) / 3.0);
    CGFloat keyHeight = 58.0;
    CGFloat verticalGap = 12.0;
    CGFloat gridTop = CGRectGetMaxY(self.numberCard.frame) + 18.0;

    [self.keyButtons enumerateObjectsUsingBlock:^(PAStudioKeyButton *button, NSUInteger index, BOOL *stop) {
        NSUInteger row = index / 3;
        NSUInteger column = index % 3;
        button.frame = CGRectMake(horizontalMargin + column * (keyWidth + horizontalGap),
                                  gridTop + row * (keyHeight + verticalGap),
                                  keyWidth,
                                  keyHeight);
        button.surfaceView.layer.cornerRadius = MIN(self.studioCornerRadius, 17.0);
    }];

    CGFloat gridBottom = gridTop + 4.0 * keyHeight + 3.0 * verticalGap;
    CGFloat actionHeight = 58.0;
    CGFloat actionWidth = 92.0;
    CGFloat actionY = MIN(gridBottom + 19.0, height - safe.bottom - actionHeight - 11.0);
    self.callButton.frame = CGRectMake((width - actionWidth) / 2.0, actionY, actionWidth, actionHeight);
    self.callButton.layer.cornerRadius = MIN(self.studioCornerRadius + 5.0, actionHeight / 2.0);
    self.deleteButton.frame = CGRectMake(CGRectGetMaxX(self.callButton.frame) + 25.0,
                                         actionY + 7.0,
                                         50.0,
                                         44.0);
    self.deleteButton.layer.cornerRadius = MIN(self.studioCornerRadius, 15.0);
}

- (void)keyTapped:(PAStudioKeyButton *)sender {
    if (self.hapticsEnabled) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator impactOccurred];
    }
    self.dialValue = [self.dialValue stringByAppendingString:sender.value ?: @""];
    [self updateNumberDisplay];
}

- (void)zeroLongPressed:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    self.dialValue = [self.dialValue stringByAppendingString:@"+"];
    [self updateNumberDisplay];
    if (self.hapticsEnabled) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [generator impactOccurred];
    }
}

- (void)deleteTapped {
    if (self.dialValue.length == 0) return;
    self.dialValue = [self.dialValue substringToIndex:self.dialValue.length - 1];
    [self updateNumberDisplay];
    if (self.hapticsEnabled) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator impactOccurred];
    }
}

- (void)deleteLongPressed:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    [self clearNumber];
    if (self.hapticsEnabled) {
        UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
        [generator notificationOccurred:UINotificationFeedbackTypeWarning];
    }
}

- (void)callTapped {
    if (self.dialValue.length == 0) return;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"+0123456789*#"];
    NSMutableString *clean = [NSMutableString string];
    for (NSUInteger index = 0; index < self.dialValue.length; index++) {
        NSString *character = [self.dialValue substringWithRange:NSMakeRange(index, 1)];
        if ([character rangeOfCharacterFromSet:allowed].location != NSNotFound) {
            [clean appendString:character];
        }
    }
    if (clean.length == 0) return;

    NSString *escaped = [clean stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"tel://%@", escaped ?: clean]];
    if (!url) return;

    if (self.hapticsEnabled) {
        UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
        [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
    }
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)addNumberTapped {
    if (self.dialValue.length == 0) return;
    NSString *escaped = [self.dialValue stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"contacts://add?phone=%@", escaped ?: @""]];
    if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)updateNumberDisplay {
    self.numberLabel.text = self.dialValue.length > 0 ? self.dialValue : @"Enter number";
    self.addNumberButton.alpha = self.dialValue.length > 0 ? 1.0 : 0.70;
    if (self.animationsEnabled) {
        self.numberLabel.transform = CGAffineTransformMakeScale(0.98, 0.98);
        [UIView animateWithDuration:0.16 animations:^{
            self.numberLabel.transform = CGAffineTransformIdentity;
        }];
    }
}

- (void)clearNumber {
    self.dialValue = @"";
    [self updateNumberDisplay];
}

@end
