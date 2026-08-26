#import "PAConceptDSurfaces.h"
#import "PAConceptDUI.h"
#import "PADataStore.h"
#import <QuartzCore/QuartzCore.h>

static NSString *PAContactName(CNContact *contact) {
    NSString *name = [CNContactFormatter stringFromContact:contact style:CNContactFormatterStyleFullName];
    if (name.length) return name;
    if (contact.organizationName.length) return contact.organizationName;
    return @"Contact";
}

static NSString *PAContactNumber(CNContact *contact) {
    CNLabeledValue<CNPhoneNumber *> *value = contact.phoneNumbers.firstObject;
    return value.value.stringValue ?: @"";
}

static UIImage *PAContactImage(CNContact *contact) {
    if (!contact.thumbnailImageData.length) return nil;
    return [UIImage imageWithData:contact.thumbnailImageData];
}

static void PAImpact(BOOL enabled) {
    if (!enabled) return;
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [generator impactOccurred];
}

@interface PAContactCard : UIControl
@property(nonatomic,strong) CAGradientLayer *gradient;
@property(nonatomic,strong) UIImageView *avatar;
@property(nonatomic,strong) UILabel *nameLabel;
@property(nonatomic,strong) UILabel *subtitleLabel;
@property(nonatomic,strong) UIButton *callButton;
@property(nonatomic,strong) CNContact *contact;
@property(nonatomic) BOOL compact;
@property(nonatomic,copy) void (^tapHandler)(CNContact *contact);
- (void)configureContact:(CNContact *)contact colors:(NSArray<UIColor *> *)colors compact:(BOOL)compact;
@end

@implementation PAContactCard

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 18.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 0.8;
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;

        _gradient = [CAGradientLayer layer];
        _gradient.startPoint = CGPointMake(0, 0);
        _gradient.endPoint = CGPointMake(1, 1);
        [self.layer insertSublayer:_gradient atIndex:0];

        _avatar = [[UIImageView alloc] init];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.17];
        _avatar.clipsToBounds = YES;
        [self addSubview:_avatar];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.textColor = UIColor.whiteColor;
        _nameLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
        _nameLabel.numberOfLines = 1;
        _nameLabel.adjustsFontSizeToFitWidth = YES;
        _nameLabel.minimumScaleFactor = 0.72;
        [self addSubview:_nameLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.textColor = [UIColor colorWithWhite:1 alpha:0.78];
        _subtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _subtitleLabel.adjustsFontSizeToFitWidth = YES;
        [self addSubview:_subtitleLabel];

        _callButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _callButton.tintColor = UIColor.whiteColor;
        _callButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.20];
        _callButton.layer.cornerRadius = 18.0;
        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
        [_callButton setImage:[UIImage systemImageNamed:@"phone.fill" withConfiguration:configuration] forState:UIControlStateNormal];
        [_callButton addTarget:self action:@selector(callTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_callButton];

        [self addTarget:self action:@selector(cardTapped) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)configureContact:(CNContact *)contact colors:(NSArray<UIColor *> *)colors compact:(BOOL)compact {
    self.contact = contact;
    self.compact = compact;
    self.nameLabel.text = PAContactName(contact);
    NSString *number = PAContactNumber(contact);
    self.subtitleLabel.text = number.length ? number : @"No phone number";
    UIImage *image = PAContactImage(contact);
    self.avatar.image = image;
    if (!image) {
        self.avatar.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
        self.avatar.tintColor = [UIColor colorWithWhite:1 alpha:0.92];
        self.avatar.contentMode = UIViewContentModeScaleAspectFit;
    } else {
        self.avatar.contentMode = UIViewContentModeScaleAspectFill;
    }
    NSMutableArray *cgColors = [NSMutableArray array];
    for (UIColor *color in colors) [cgColors addObject:(id)color.CGColor];
    self.gradient.colors = cgColors;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.gradient.frame = self.bounds;
    CGFloat avatarSize = self.compact ? 52.0 : 76.0;
    CGFloat x = self.compact ? 14.0 : 18.0;
    self.avatar.frame = CGRectMake(x, (CGRectGetHeight(self.bounds) - avatarSize) / 2.0, avatarSize, avatarSize);
    self.avatar.layer.cornerRadius = avatarSize / 2.0;
    CGFloat callSize = self.compact ? 34.0 : 40.0;
    self.callButton.frame = CGRectMake(CGRectGetWidth(self.bounds) - callSize - 14.0,
                                       CGRectGetHeight(self.bounds) - callSize - 12.0,
                                       callSize,
                                       callSize);
    self.callButton.layer.cornerRadius = callSize / 2.0;
    CGFloat textX = CGRectGetMaxX(self.avatar.frame) + 13.0;
    CGFloat textWidth = CGRectGetMinX(self.callButton.frame) - textX - 8.0;
    self.nameLabel.frame = CGRectMake(textX, self.compact ? 19.0 : 33.0, textWidth, 25.0);
    self.subtitleLabel.frame = CGRectMake(textX, CGRectGetMaxY(self.nameLabel.frame) + 1.0, textWidth, 18.0);
}

- (void)cardTapped {
    if (self.tapHandler && self.contact) self.tapHandler(self.contact);
}

- (void)callTapped {
    if (self.tapHandler && self.contact) self.tapHandler(self.contact);
}

@end

#pragma mark - Favorites

@interface PAFavoritesDashboardView ()
@property(nonatomic,strong) UIScrollView *scrollView;
@property(nonatomic,strong) UILabel *sectionTitle;
@property(nonatomic,strong) UILabel *emptyLabel;
@property(nonatomic,strong) UIButton *manageButton;
@property(nonatomic,strong) NSArray<PAContactCard *> *contactCards;
@property(nonatomic,strong) NSArray<UIButton *> *shortcutButtons;
@property(nonatomic,strong) NSArray<CNContact *> *contacts;
@end

@implementation PAFavoritesDashboardView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = PAColorHex(0x040817, 1.0);
        _scrollView = [[UIScrollView alloc] init];
        _scrollView.alwaysBounceVertical = YES;
        _scrollView.showsVerticalScrollIndicator = NO;
        [self addSubview:_scrollView];

        _sectionTitle = [[UILabel alloc] init];
        _sectionTitle.text = @"Smart Shortcuts";
        _sectionTitle.textColor = UIColor.whiteColor;
        _sectionTitle.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
        [_scrollView addSubview:_sectionTitle];

        _emptyLabel = [[UILabel alloc] init];
        _emptyLabel.text = @"Choose favorite contacts in PhoneAura Studio";
        _emptyLabel.textColor = PAColorHex(0xA7B2CA, 1.0);
        _emptyLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _emptyLabel.textAlignment = NSTextAlignmentCenter;
        _emptyLabel.numberOfLines = 2;
        [_scrollView addSubview:_emptyLabel];

        _manageButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_manageButton setTitle:@"Open PhoneAura Studio" forState:UIControlStateNormal];
        [_manageButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        _manageButton.backgroundColor = PAColorHex(0xFF5B61, 1.0);
        _manageButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        _manageButton.layer.cornerRadius = 15.0;
        [_manageButton addTarget:self action:@selector(manageTapped) forControlEvents:UIControlEventTouchUpInside];
        [_scrollView addSubview:_manageButton];

        NSArray *titles = @[@"Family Group", @"Work Line", @"Voicemail", @"Create Shortcut"];
        NSArray *subtitles = @[@"4 members", @"Quick call", @"New messages", @"Add action"];
        NSArray *icons = @[@"person.2.fill", @"briefcase.fill", @"recordingtape", @"plus"];
        NSArray *colors = @[PAColorHex(0x7C4DFF,1), PAColorHex(0xFF7A1A,1), PAColorHex(0x18C8B7,1), PAColorHex(0x202B49,1)];
        NSMutableArray *shortcuts = [NSMutableArray array];
        for (NSUInteger index = 0; index < titles.count; index++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.tag = index;
            button.backgroundColor = colors[index];
            button.tintColor = UIColor.whiteColor;
            button.layer.cornerRadius = 16.0;
            button.layer.cornerCurve = kCACornerCurveContinuous;
            button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            button.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 10);
            UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
            [button setImage:[UIImage systemImageNamed:icons[index] withConfiguration:configuration] forState:UIControlStateNormal];
            NSString *title = [NSString stringWithFormat:@"  %@\n  %@", titles[index], subtitles[index]];
            NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:title attributes:@{NSForegroundColorAttributeName:UIColor.whiteColor, NSFontAttributeName:[UIFont systemFontOfSize:12 weight:UIFontWeightBold]}];
            NSRange secondLine = [title rangeOfString:subtitles[index]];
            if (secondLine.location != NSNotFound) [attributed addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:10 weight:UIFontWeightMedium] range:secondLine];
            [button setAttributedTitle:attributed forState:UIControlStateNormal];
            button.titleLabel.numberOfLines = 2;
            [button addTarget:self action:@selector(shortcutTapped:) forControlEvents:UIControlEventTouchUpInside];
            [_scrollView addSubview:button];
            [shortcuts addObject:button];
        }
        _shortcutButtons = shortcuts;
    }
    return self;
}

- (void)reloadFavoriteIdentifiers:(NSArray<NSString *> *)identifiers {
    [[PADataStore sharedStore] favoriteContactsForIdentifiers:identifiers completion:^(NSArray<CNContact *> *contacts) {
        self.contacts = contacts;
        for (PAContactCard *card in self.contactCards) [card removeFromSuperview];
        NSMutableArray *cards = [NSMutableArray array];
        NSArray *palettes = @[
            @[PAColorHex(0xFF5B61,1), PAColorHex(0xFF774D,1)],
            @[PAColorHex(0x6F63FF,1), PAColorHex(0x3B82F6,1)],
            @[PAColorHex(0x18C8B7,1), PAColorHex(0x0F8B8D,1)],
            @[PAColorHex(0xFF7A1A,1), PAColorHex(0xFF3E88,1)]
        ];
        NSUInteger count = MIN(contacts.count, (NSUInteger)4);
        for (NSUInteger index = 0; index < count; index++) {
            PAContactCard *card = [[PAContactCard alloc] init];
            [card configureContact:contacts[index] colors:palettes[index] compact:(index > 0)];
            __weak typeof(self) weakSelf = self;
            card.tapHandler = ^(CNContact *contact) {
                PAImpact(weakSelf.hapticsEnabled);
                NSString *number = PAContactNumber(contact);
                if (number.length && weakSelf.callHandler) weakSelf.callHandler(number);
            };
            [self.scrollView addSubview:card];
            [cards addObject:card];
        }
        self.contactCards = cards;
        self.emptyLabel.hidden = count > 0;
        self.manageButton.hidden = count > 0;
        [self setNeedsLayout];
    }];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.scrollView.frame = self.bounds;
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat inset = 16.0;
    CGFloat y = self.safeAreaInsets.top + 10.0;

    if (self.contactCards.count == 0) {
        self.emptyLabel.frame = CGRectMake(32, y + 24, width - 64, 54);
        self.manageButton.frame = CGRectMake((width - 210) / 2.0, CGRectGetMaxY(self.emptyLabel.frame) + 12, 210, 48);
        y = CGRectGetMaxY(self.manageButton.frame) + 30;
    } else {
        PAContactCard *hero = self.contactCards.firstObject;
        hero.frame = CGRectMake(inset, y, width - inset * 2.0, 132.0);
        y = CGRectGetMaxY(hero.frame) + 12.0;
        CGFloat gap = 10.0;
        CGFloat half = (width - inset * 2.0 - gap) / 2.0;
        for (NSUInteger index = 1; index < self.contactCards.count; index++) {
            NSUInteger item = index - 1;
            NSUInteger row = item / 2;
            NSUInteger column = item % 2;
            PAContactCard *card = self.contactCards[index];
            card.frame = CGRectMake(inset + column * (half + gap), y + row * 108.0, half, 98.0);
        }
        NSUInteger compactCount = self.contactCards.count > 1 ? self.contactCards.count - 1 : 0;
        y += ceil(compactCount / 2.0) * 108.0 + 7.0;
    }

    self.sectionTitle.frame = CGRectMake(inset, y, width - inset * 2.0, 25.0);
    y += 34.0;
    CGFloat gap = 10.0;
    CGFloat buttonWidth = (width - inset * 2.0 - gap) / 2.0;
    for (NSUInteger index = 0; index < self.shortcutButtons.count; index++) {
        NSUInteger row = index / 2;
        NSUInteger column = index % 2;
        self.shortcutButtons[index].frame = CGRectMake(inset + column * (buttonWidth + gap), y + row * 66.0, buttonWidth, 56.0);
    }
    y += 142.0;
    self.scrollView.contentSize = CGSizeMake(width, MAX(y, CGRectGetHeight(self.bounds) + 1));
}

- (void)manageTapped {
    PAImpact(self.hapticsEnabled);
    if (self.settingsHandler) self.settingsHandler();
}

- (void)shortcutTapped:(UIButton *)sender {
    PAImpact(self.hapticsEnabled);
    if (sender.tag == 2) {
        NSURL *url = [NSURL URLWithString:@"mobilephone-voicemail://"];
        if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else if (sender.tag == 3) {
        if (self.settingsHandler) self.settingsHandler();
    }
}

@end

#pragma mark - Recents

@interface PARecentCell : UITableViewCell
@property(nonatomic,strong) UIView *card;
@property(nonatomic,strong) UIView *strip;
@property(nonatomic,strong) UIImageView *avatar;
@property(nonatomic,strong) UILabel *nameLabel;
@property(nonatomic,strong) UILabel *detailLabel;
@property(nonatomic,strong) UILabel *timeLabel;
@property(nonatomic,strong) UIButton *infoButton;
- (void)configureCall:(PARecentCall *)call index:(NSUInteger)index;
@end

@implementation PARecentCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _card = [[UIView alloc] init];
        _card.backgroundColor = PAColorHex(0x17213D, 0.98);
        _card.layer.cornerRadius = 16.0;
        _card.layer.cornerCurve = kCACornerCurveContinuous;
        _card.layer.borderWidth = 0.7;
        _card.layer.borderColor = PAColorHex(0x63708E, 0.20).CGColor;
        [self.contentView addSubview:_card];
        _strip = [[UIView alloc] init];
        [_card addSubview:_strip];
        _avatar = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
        _avatar.tintColor = PAColorHex(0xA7B2CA,1);
        _avatar.contentMode = UIViewContentModeScaleAspectFit;
        [_card addSubview:_avatar];
        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
        _nameLabel.textColor = UIColor.whiteColor;
        [_card addSubview:_nameLabel];
        _detailLabel = [[UILabel alloc] init];
        _detailLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _detailLabel.textColor = PAColorHex(0xA7B2CA,1);
        [_card addSubview:_detailLabel];
        _timeLabel = [[UILabel alloc] init];
        _timeLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _timeLabel.textColor = PAColorHex(0xA7B2CA,1);
        _timeLabel.textAlignment = NSTextAlignmentRight;
        [_card addSubview:_timeLabel];
        _infoButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _infoButton.tintColor = PAColorHex(0x6F63FF,1);
        [_infoButton setImage:[UIImage systemImageNamed:@"info.circle"] forState:UIControlStateNormal];
        _infoButton.userInteractionEnabled = NO;
        [_card addSubview:_infoButton];
    }
    return self;
}

- (void)configureCall:(PARecentCall *)call index:(NSUInteger)index {
    NSArray *colors = @[PAColorHex(0xFF5B61,1), PAColorHex(0x18C8B7,1), PAColorHex(0x3B82F6,1), PAColorHex(0x8B5CF6,1), PAColorHex(0x22C55E,1)];
    UIColor *color = call.missed ? colors[0] : colors[index % colors.count];
    self.strip.backgroundColor = color;
    self.nameLabel.text = call.displayName.length ? call.displayName : call.number;
    self.nameLabel.textColor = call.missed ? PAColorHex(0xFF6B70,1) : UIColor.whiteColor;
    self.detailLabel.text = call.outgoing ? @"Outgoing call" : (call.missed ? @"Missed call" : @"Incoming call");
    self.infoButton.tintColor = color;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.doesRelativeDateFormatting = YES;
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    self.timeLabel.text = [formatter stringFromDate:call.date];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.card.frame = CGRectInset(self.contentView.bounds, 14.0, 5.0);
    self.strip.frame = CGRectMake(0, 0, 5.0, CGRectGetHeight(self.card.bounds));
    self.strip.layer.cornerRadius = 2.5;
    self.avatar.frame = CGRectMake(16, 15, 38, 38);
    CGFloat right = CGRectGetWidth(self.card.bounds) - 14.0;
    self.infoButton.frame = CGRectMake(right - 26, 21, 24, 24);
    self.timeLabel.frame = CGRectMake(right - 122, 13, 90, 18);
    CGFloat textX = CGRectGetMaxX(self.avatar.frame) + 12.0;
    self.nameLabel.frame = CGRectMake(textX, 12, CGRectGetMinX(self.timeLabel.frame) - textX - 8, 23);
    self.detailLabel.frame = CGRectMake(textX, 36, CGRectGetMinX(self.infoButton.frame) - textX - 8, 18);
}

@end

@interface PARecentsDashboardView () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic,strong) UISegmentedControl *filterControl;
@property(nonatomic,strong) UITableView *tableView;
@property(nonatomic,strong) UILabel *emptyLabel;
@property(nonatomic,strong) NSArray<PARecentCall *> *calls;
@end

@implementation PARecentsDashboardView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = PAColorHex(0x040817,1);
        _filterControl = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Missed"]];
        _filterControl.selectedSegmentIndex = 0;
        _filterControl.selectedSegmentTintColor = PAColorHex(0x6F63FF,1);
        [_filterControl setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor, NSFontAttributeName:[UIFont systemFontOfSize:12 weight:UIFontWeightBold]} forState:UIControlStateNormal];
        [_filterControl addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
        [self addSubview:_filterControl];
        _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _tableView.backgroundColor = UIColor.clearColor;
        _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        _tableView.rowHeight = 72.0;
        _tableView.dataSource = self;
        _tableView.delegate = self;
        [_tableView registerClass:[PARecentCell class] forCellReuseIdentifier:@"recent"];
        [self addSubview:_tableView];
        _emptyLabel = [[UILabel alloc] init];
        _emptyLabel.text = @"Call history is unavailable.\nUse the stock Recents view from PhoneAura Studio.";
        _emptyLabel.textColor = PAColorHex(0xA7B2CA,1);
        _emptyLabel.textAlignment = NSTextAlignmentCenter;
        _emptyLabel.numberOfLines = 2;
        _emptyLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [self addSubview:_emptyLabel];
        [self refresh];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat top = self.safeAreaInsets.top + 8.0;
    self.filterControl.frame = CGRectMake(18, top, 190, 34);
    self.tableView.frame = CGRectMake(0, CGRectGetMaxY(self.filterControl.frame) + 8, CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds) - CGRectGetMaxY(self.filterControl.frame) - 8);
    self.emptyLabel.frame = CGRectMake(30, CGRectGetMidY(self.bounds) - 40, CGRectGetWidth(self.bounds) - 60, 80);
}

- (void)filterChanged {
    PAImpact(self.hapticsEnabled);
    [self refresh];
}

- (void)refresh {
    BOOL missedOnly = self.filterControl.selectedSegmentIndex == 1;
    [[PADataStore sharedStore] recentCallsMissedOnly:missedOnly limit:120 completion:^(NSArray<PARecentCall *> *calls) {
        self.calls = calls;
        self.emptyLabel.hidden = calls.count > 0;
        [self.tableView reloadData];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.calls.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PARecentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"recent" forIndexPath:indexPath];
    [cell configureCall:self.calls[indexPath.row] index:indexPath.row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PAImpact(self.hapticsEnabled);
    PARecentCall *call = self.calls[indexPath.row];
    if (call.number.length && self.callHandler) self.callHandler(call.number);
}

@end

#pragma mark - Contacts

@interface PAContactListCell : UITableViewCell
@property(nonatomic,strong) UIImageView *avatar;
@property(nonatomic,strong) UILabel *nameLabel;
@property(nonatomic,strong) UILabel *numberLabel;
@property(nonatomic,strong) UIButton *actionButton;
- (void)configureContact:(CNContact *)contact;
@end

@implementation PAContactListCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.contentView.backgroundColor = PAColorHex(0x152A38,0.94);
        self.contentView.layer.cornerRadius = 15;
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        _avatar = [[UIImageView alloc] init];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES;
        [self.contentView addSubview:_avatar];
        _nameLabel = [[UILabel alloc] init];
        _nameLabel.textColor = UIColor.whiteColor;
        _nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        [self.contentView addSubview:_nameLabel];
        _numberLabel = [[UILabel alloc] init];
        _numberLabel.textColor = PAColorHex(0xA7B2CA,1);
        _numberLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        [self.contentView addSubview:_numberLabel];
        _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _actionButton.tintColor = PAColorHex(0x18C8B7,1);
        [_actionButton setImage:[UIImage systemImageNamed:@"chevron.right"] forState:UIControlStateNormal];
        _actionButton.userInteractionEnabled = NO;
        [self.contentView addSubview:_actionButton];
    }
    return self;
}
- (void)configureContact:(CNContact *)contact {
    self.nameLabel.text = PAContactName(contact);
    self.numberLabel.text = PAContactNumber(contact).length ? PAContactNumber(contact) : @"No phone number";
    UIImage *image = PAContactImage(contact);
    self.avatar.image = image ?: [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.avatar.tintColor = PAColorHex(0x18C8B7,1);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.contentView.frame = CGRectInset(self.bounds, 14, 4);
    self.avatar.frame = CGRectMake(13, 10, 42, 42);
    self.avatar.layer.cornerRadius = 21;
    self.nameLabel.frame = CGRectMake(68, 9, CGRectGetWidth(self.contentView.bounds)-118, 23);
    self.numberLabel.frame = CGRectMake(68, 32, CGRectGetWidth(self.contentView.bounds)-118, 17);
    self.actionButton.frame = CGRectMake(CGRectGetWidth(self.contentView.bounds)-40, 19, 24, 24);
}
@end

@interface PAContactsDashboardView () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property(nonatomic,strong) UISearchBar *searchBar;
@property(nonatomic,strong) UITableView *tableView;
@property(nonatomic,strong) PAContactCard *heroCard;
@property(nonatomic,strong) NSArray<CNContact *> *allContacts;
@property(nonatomic,strong) NSArray<CNContact *> *filteredContacts;
@end

@implementation PAContactsDashboardView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = PAColorHex(0x040817,1);
        _searchBar = [[UISearchBar alloc] init];
        _searchBar.searchBarStyle = UISearchBarStyleMinimal;
        _searchBar.placeholder = @"Search contacts";
        _searchBar.delegate = self;
        _searchBar.searchTextField.backgroundColor = PAColorHex(0x17213D,0.98);
        _searchBar.searchTextField.textColor = UIColor.whiteColor;
        _searchBar.searchTextField.tintColor = PAColorHex(0x18C8B7,1);
        _searchBar.searchTextField.layer.cornerRadius = 14;
        _searchBar.searchTextField.clipsToBounds = YES;
        [self addSubview:_searchBar];
        _heroCard = [[PAContactCard alloc] init];
        __weak typeof(self) weakSelf = self;
        _heroCard.tapHandler = ^(CNContact *contact) {
            PAImpact(weakSelf.hapticsEnabled);
            if (weakSelf.contactHandler) weakSelf.contactHandler(contact);
        };
        [self addSubview:_heroCard];
        _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _tableView.backgroundColor = UIColor.clearColor;
        _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        _tableView.rowHeight = 70;
        _tableView.dataSource = self;
        _tableView.delegate = self;
        [_tableView registerClass:[PAContactListCell class] forCellReuseIdentifier:@"contact"];
        [self addSubview:_tableView];
        [self refresh];
    }
    return self;
}

- (void)refresh {
    [[PADataStore sharedStore] allContactsWithCompletion:^(NSArray<CNContact *> *contacts) {
        self.allContacts = contacts;
        self.filteredContacts = contacts;
        CNContact *hero = contacts.firstObject;
        self.heroCard.hidden = hero == nil;
        if (hero) [self.heroCard configureContact:hero colors:@[PAColorHex(0x18C8B7,1),PAColorHex(0x087B87,1)] compact:NO];
        [self.tableView reloadData];
    }];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat top = self.safeAreaInsets.top + 5;
    self.searchBar.frame = CGRectMake(12, top, CGRectGetWidth(self.bounds)-24, 46);
    CGFloat y = CGRectGetMaxY(self.searchBar.frame) + 7;
    if (!self.heroCard.hidden) {
        self.heroCard.frame = CGRectMake(16, y, CGRectGetWidth(self.bounds)-32, 112);
        y = CGRectGetMaxY(self.heroCard.frame) + 10;
    }
    self.tableView.frame = CGRectMake(0, y, CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds)-y);
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) self.filteredContacts = self.allContacts;
    else {
        NSString *needle = searchText.lowercaseString;
        self.filteredContacts = [self.allContacts filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CNContact *contact, NSDictionary *bindings) {
            return [PAContactName(contact).lowercaseString containsString:needle] || [PAContactNumber(contact) containsString:needle];
        }]];
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filteredContacts.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PAContactListCell *cell = [tableView dequeueReusableCellWithIdentifier:@"contact" forIndexPath:indexPath];
    [cell configureContact:self.filteredContacts[indexPath.row]];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PAImpact(self.hapticsEnabled);
    if (self.contactHandler) self.contactHandler(self.filteredContacts[indexPath.row]);
}

@end
