#import "PAContactFlowV46.h"
#import "PAConceptDUI.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - Safe contact helpers

static NSString *PA46ContactName(CNContact *contact) {
    if (!contact) return @"Contact";
    @try {
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        if (contact.givenName.length) [parts addObject:contact.givenName];
        if (contact.middleName.length) [parts addObject:contact.middleName];
        if (contact.familyName.length) [parts addObject:contact.familyName];
        NSString *name = [parts componentsJoinedByString:@" "];
        if (name.length) return name;
        if (contact.nickname.length) return contact.nickname;
        if (contact.organizationName.length) return contact.organizationName;
    } @catch (__unused NSException *exception) {
    }
    return @"Contact";
}

static NSArray<NSString *> *PA46ContactNumbers(CNContact *contact) {
    if (!contact) return @[];
    NSMutableArray<NSString *> *numbers = [NSMutableArray array];
    @try {
        for (CNLabeledValue<CNPhoneNumber *> *value in contact.phoneNumbers) {
            NSString *number = value.value.stringValue;
            if (number.length && ![numbers containsObject:number]) [numbers addObject:number];
        }
    } @catch (__unused NSException *exception) {
    }
    return [numbers copy];
}

static NSString *PA46PrimaryNumber(CNContact *contact) {
    return PA46ContactNumbers(contact).firstObject ?: @"";
}

static UIImage *PA46ContactImage(CNContact *contact) {
    if (!contact) return nil;
    @try {
        if (contact.thumbnailImageData.length) return [UIImage imageWithData:contact.thumbnailImageData];
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static void PA46Impact(BOOL enabled) {
    if (!enabled) return;
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [generator impactOccurred];
}

static NSArray<id<CNKeyDescriptor>> *PA46ContactKeys(void) {
    return @[
        CNContactIdentifierKey,
        CNContactGivenNameKey,
        CNContactMiddleNameKey,
        CNContactFamilyNameKey,
        CNContactNamePrefixKey,
        CNContactNameSuffixKey,
        CNContactNicknameKey,
        CNContactOrganizationNameKey,
        CNContactPhoneNumbersKey,
        CNContactThumbnailImageDataKey,
        CNContactImageDataAvailableKey
    ];
}

#pragma mark - Directory

@interface PAContactDirectoryV46 : NSObject
@property(nonatomic,strong) CNContactStore *store;
@property(nonatomic) dispatch_queue_t queue;
+ (instancetype)sharedDirectory;
- (void)allContacts:(void (^)(NSArray<CNContact *> *contacts))completion;
- (void)contactsForIdentifiers:(NSArray<NSString *> *)identifiers completion:(void (^)(NSArray<CNContact *> *contacts))completion;
- (void)myCard:(void (^)(CNContact * _Nullable contact))completion;
@end

@implementation PAContactDirectoryV46

+ (instancetype)sharedDirectory {
    static PAContactDirectoryV46 *directory;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ directory = [[self alloc] init]; });
    return directory;
}

- (instancetype)init {
    if ((self = [super init])) {
        _store = [[CNContactStore alloc] init];
        _queue = dispatch_queue_create("com.zeshan.phoneaura.contacts.v46", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)canRead {
    CNAuthorizationStatus status = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
    return status != CNAuthorizationStatusDenied && status != CNAuthorizationStatusRestricted;
}

- (void)finishArray:(NSArray<CNContact *> *)contacts completion:(void (^)(NSArray<CNContact *> *))completion {
    NSArray<CNContact *> *snapshot = [contacts copy] ?: @[];
    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(snapshot); });
}

- (void)allContacts:(void (^)(NSArray<CNContact *> *contacts))completion {
    if (![self canRead]) { [self finishArray:@[] completion:completion]; return; }
    dispatch_async(self.queue, ^{
        @autoreleasepool {
            NSMutableArray<CNContact *> *contacts = [NSMutableArray array];
            @try {
                CNContactFetchRequest *request = [[CNContactFetchRequest alloc] initWithKeysToFetch:PA46ContactKeys()];
                request.sortOrder = CNContactSortOrderUserDefault;
                request.unifyResults = YES;
                request.mutableObjects = NO;
                NSError *error = nil;
                BOOL success = [self.store enumerateContactsWithFetchRequest:request error:&error usingBlock:^(CNContact *contact, BOOL *stop) {
                    if (PA46ContactName(contact).length && ![PA46ContactName(contact) isEqualToString:@"Contact"]) [contacts addObject:contact];
                    if (contacts.count >= 1600) *stop = YES;
                }];
                if (!success || error) [contacts removeAllObjects];
            } @catch (__unused NSException *exception) {
                [contacts removeAllObjects];
            }
            [self finishArray:contacts completion:completion];
        }
    });
}

- (void)contactsForIdentifiers:(NSArray<NSString *> *)identifiers completion:(void (^)(NSArray<CNContact *> *contacts))completion {
    NSArray<NSString *> *safeIdentifiers = [identifiers isKindOfClass:[NSArray class]] ? [identifiers copy] : @[];
    if (![self canRead] || safeIdentifiers.count == 0) { [self finishArray:@[] completion:completion]; return; }
    dispatch_async(self.queue, ^{
        @autoreleasepool {
            NSMutableArray<CNContact *> *contacts = [NSMutableArray array];
            @try {
                for (NSString *identifier in safeIdentifiers) {
                    if (![identifier isKindOfClass:[NSString class]] || !identifier.length) continue;
                    NSError *error = nil;
                    CNContact *contact = [self.store unifiedContactWithIdentifier:identifier keysToFetch:PA46ContactKeys() error:&error];
                    if (contact && !error) [contacts addObject:contact];
                    if (contacts.count >= 4) break;
                }
            } @catch (__unused NSException *exception) {
                [contacts removeAllObjects];
            }
            [self finishArray:contacts completion:completion];
        }
    });
}

- (void)myCard:(void (^)(CNContact * _Nullable contact))completion {
    if (![self canRead]) { dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil); }); return; }
    dispatch_async(self.queue, ^{
        @autoreleasepool {
            CNContact *contact = nil;
            @try {
                NSError *error = nil;
                contact = [self.store unifiedMeContactWithKeysToFetch:PA46ContactKeys() error:&error];
                if (error) contact = nil;
            } @catch (__unused NSException *exception) {
                contact = nil;
            }
            CNContact *snapshot = contact;
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(snapshot); });
        }
    });
}

@end

#pragma mark - Shared contact cell

@interface PAContactRowV46 : UITableViewCell
@property(nonatomic,strong) UIView *card;
@property(nonatomic,strong) UIImageView *avatar;
@property(nonatomic,strong) UILabel *nameLabel;
@property(nonatomic,strong) UILabel *numberLabel;
@property(nonatomic,strong) UIImageView *accessoryIcon;
- (void)configureContact:(CNContact *)contact selected:(BOOL)selected picker:(BOOL)picker;
@end

@implementation PAContactRowV46

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _card = [[UIView alloc] init];
        _card.backgroundColor = PAColorHex(0x13273A, 0.98);
        _card.layer.cornerRadius = 15;
        _card.layer.cornerCurve = kCACornerCurveContinuous;
        _card.layer.borderWidth = 0.7;
        _card.layer.borderColor = PAColorHex(0x18C8B7, 0.22).CGColor;
        [self.contentView addSubview:_card];
        _avatar = [[UIImageView alloc] init];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES;
        _avatar.backgroundColor = PAColorHex(0x18C8B7, 0.16);
        [_card addSubview:_avatar];
        _nameLabel = [[UILabel alloc] init];
        _nameLabel.textColor = UIColor.whiteColor;
        _nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        [_card addSubview:_nameLabel];
        _numberLabel = [[UILabel alloc] init];
        _numberLabel.textColor = PAColorHex(0xA7B2CA, 1.0);
        _numberLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        [_card addSubview:_numberLabel];
        _accessoryIcon = [[UIImageView alloc] init];
        _accessoryIcon.contentMode = UIViewContentModeScaleAspectFit;
        _accessoryIcon.tintColor = PAColorHex(0x18C8B7, 1.0);
        [_card addSubview:_accessoryIcon];
    }
    return self;
}

- (void)configureContact:(CNContact *)contact selected:(BOOL)selected picker:(BOOL)picker {
    self.nameLabel.text = PA46ContactName(contact);
    NSString *number = PA46PrimaryNumber(contact);
    self.numberLabel.text = number.length ? number : @"No phone number";
    UIImage *image = PA46ContactImage(contact);
    self.avatar.image = image ?: [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.avatar.tintColor = PAColorHex(0x18C8B7, 1.0);
    self.avatar.contentMode = image ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
    NSString *symbol = picker ? (selected ? @"checkmark.circle.fill" : @"circle") : @"chevron.right";
    self.accessoryIcon.image = [UIImage systemImageNamed:symbol];
    self.accessoryIcon.tintColor = selected ? PAColorHex(0xFF5B61, 1.0) : PAColorHex(0x18C8B7, 1.0);
    self.card.layer.borderColor = (selected ? PAColorHex(0xFF5B61, 0.52) : PAColorHex(0x18C8B7, 0.22)).CGColor;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.card.frame = CGRectInset(self.contentView.bounds, 14, 4);
    self.avatar.frame = CGRectMake(13, 9, 42, 42);
    self.avatar.layer.cornerRadius = 21;
    CGFloat width = CGRectGetWidth(self.card.bounds);
    self.nameLabel.frame = CGRectMake(68, 8, width - 120, 23);
    self.numberLabel.frame = CGRectMake(68, 31, width - 120, 18);
    self.accessoryIcon.frame = CGRectMake(width - 40, 18, 24, 24);
}

@end

#pragma mark - Hero and favorite cards

@interface PAHeroContactCardV46 : UIControl
@property(nonatomic,strong) CAGradientLayer *gradient;
@property(nonatomic,strong) UIImageView *avatar;
@property(nonatomic,strong) UILabel *eyebrow;
@property(nonatomic,strong) UILabel *nameLabel;
@property(nonatomic,strong) UILabel *numberLabel;
@property(nonatomic,strong) UIImageView *actionIcon;
@property(nonatomic,strong) CNContact *contact;
@property(nonatomic,copy) void (^tapHandler)(CNContact *contact);
- (void)configureContact:(CNContact *)contact title:(NSString *)title colors:(NSArray<UIColor *> *)colors;
@end

@implementation PAHeroContactCardV46

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 20;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        _gradient = [CAGradientLayer layer];
        _gradient.startPoint = CGPointMake(0, 0);
        _gradient.endPoint = CGPointMake(1, 1);
        [self.layer insertSublayer:_gradient atIndex:0];
        _avatar = [[UIImageView alloc] init];
        _avatar.clipsToBounds = YES;
        _avatar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
        [self addSubview:_avatar];
        _eyebrow = [[UILabel alloc] init];
        _eyebrow.textColor = [UIColor colorWithWhite:1 alpha:0.72];
        _eyebrow.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
        _eyebrow.text = @"MY CARD";
        [self addSubview:_eyebrow];
        _nameLabel = [[UILabel alloc] init];
        _nameLabel.textColor = UIColor.whiteColor;
        _nameLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightBold];
        _nameLabel.adjustsFontSizeToFitWidth = YES;
        _nameLabel.minimumScaleFactor = 0.7;
        [self addSubview:_nameLabel];
        _numberLabel = [[UILabel alloc] init];
        _numberLabel.textColor = [UIColor colorWithWhite:1 alpha:0.82];
        _numberLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        [self addSubview:_numberLabel];
        _actionIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right.circle.fill"]];
        _actionIcon.tintColor = UIColor.whiteColor;
        [self addSubview:_actionIcon];
        [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)configureContact:(CNContact *)contact title:(NSString *)title colors:(NSArray<UIColor *> *)colors {
    self.contact = contact;
    self.eyebrow.text = title.uppercaseString;
    self.nameLabel.text = PA46ContactName(contact);
    NSString *number = PA46PrimaryNumber(contact);
    self.numberLabel.text = number.length ? number : @"No phone number";
    UIImage *image = PA46ContactImage(contact);
    self.avatar.image = image ?: [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.avatar.tintColor = UIColor.whiteColor;
    self.avatar.contentMode = image ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
    NSMutableArray *cg = [NSMutableArray array];
    for (UIColor *color in colors) [cg addObject:(id)color.CGColor];
    self.gradient.colors = cg;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.gradient.frame = self.bounds;
    self.avatar.frame = CGRectMake(18, 18, 76, 76);
    self.avatar.layer.cornerRadius = 38;
    CGFloat x = 110;
    CGFloat width = CGRectGetWidth(self.bounds) - x - 54;
    self.eyebrow.frame = CGRectMake(x, 20, width, 16);
    self.nameLabel.frame = CGRectMake(x, 38, width, 29);
    self.numberLabel.frame = CGRectMake(x, 70, width, 20);
    self.actionIcon.frame = CGRectMake(CGRectGetWidth(self.bounds) - 42, 45, 26, 26);
}

- (void)tapped { if (self.tapHandler && self.contact) self.tapHandler(self.contact); }

@end

@interface PAFavoriteCardV46 : UIControl
@property(nonatomic,strong) CAGradientLayer *gradient;
@property(nonatomic,strong) UIImageView *avatar;
@property(nonatomic,strong) UILabel *nameLabel;
@property(nonatomic,strong) UILabel *numberLabel;
@property(nonatomic,strong) CNContact *contact;
@property(nonatomic,copy) void (^tapHandler)(CNContact *contact);
- (void)configureContact:(CNContact *)contact colors:(NSArray<UIColor *> *)colors large:(BOOL)large;
@property(nonatomic) BOOL large;
@end

@implementation PAFavoriteCardV46

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 18;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        _gradient = [CAGradientLayer layer];
        _gradient.startPoint = CGPointMake(0, 0);
        _gradient.endPoint = CGPointMake(1, 1);
        [self.layer insertSublayer:_gradient atIndex:0];
        _avatar = [[UIImageView alloc] init];
        _avatar.clipsToBounds = YES;
        _avatar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
        [self addSubview:_avatar];
        _nameLabel = [[UILabel alloc] init];
        _nameLabel.textColor = UIColor.whiteColor;
        _nameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
        _nameLabel.adjustsFontSizeToFitWidth = YES;
        _nameLabel.minimumScaleFactor = 0.68;
        [self addSubview:_nameLabel];
        _numberLabel = [[UILabel alloc] init];
        _numberLabel.textColor = [UIColor colorWithWhite:1 alpha:0.80];
        _numberLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        [self addSubview:_numberLabel];
        [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)configureContact:(CNContact *)contact colors:(NSArray<UIColor *> *)colors large:(BOOL)large {
    self.contact = contact;
    self.large = large;
    self.nameLabel.text = PA46ContactName(contact);
    self.numberLabel.text = PA46PrimaryNumber(contact);
    UIImage *image = PA46ContactImage(contact);
    self.avatar.image = image ?: [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.avatar.tintColor = UIColor.whiteColor;
    self.avatar.contentMode = image ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
    NSMutableArray *cg = [NSMutableArray array];
    for (UIColor *color in colors) [cg addObject:(id)color.CGColor];
    self.gradient.colors = cg;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.gradient.frame = self.bounds;
    CGFloat avatarSize = self.large ? 72 : 46;
    self.avatar.frame = CGRectMake(14, (CGRectGetHeight(self.bounds)-avatarSize)/2.0, avatarSize, avatarSize);
    self.avatar.layer.cornerRadius = avatarSize/2.0;
    CGFloat x = CGRectGetMaxX(self.avatar.frame)+12;
    self.nameLabel.frame = CGRectMake(x, self.large ? 34 : 19, CGRectGetWidth(self.bounds)-x-12, 24);
    self.numberLabel.frame = CGRectMake(x, CGRectGetMaxY(self.nameLabel.frame)+1, CGRectGetWidth(self.bounds)-x-12, 18);
}

- (void)tapped { if (self.tapHandler && self.contact) self.tapHandler(self.contact); }

@end

#pragma mark - Favorites dashboard

@interface PAFavoritesDashboardV46 ()
@property(nonatomic,strong) UIScrollView *scrollView;
@property(nonatomic,strong) UILabel *emptyLabel;
@property(nonatomic,strong) UIButton *chooseButton;
@property(nonatomic,strong) UILabel *shortcutsTitle;
@property(nonatomic,strong) NSArray<UIButton *> *shortcutButtons;
@property(nonatomic,strong) NSArray<PAFavoriteCardV46 *> *favoriteCards;
@end

@implementation PAFavoritesDashboardV46

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = PAColorHex(0x040817, 1.0);
        _scrollView = [[UIScrollView alloc] init];
        _scrollView.alwaysBounceVertical = YES;
        _scrollView.showsVerticalScrollIndicator = NO;
        [self addSubview:_scrollView];
        _emptyLabel = [[UILabel alloc] init];
        _emptyLabel.text = @"Add up to four favorite contacts";
        _emptyLabel.textColor = PAColorHex(0xA7B2CA, 1.0);
        _emptyLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _emptyLabel.textAlignment = NSTextAlignmentCenter;
        [_scrollView addSubview:_emptyLabel];
        _chooseButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_chooseButton setTitle:@"Choose Favorite Contacts" forState:UIControlStateNormal];
        [_chooseButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        _chooseButton.backgroundColor = PAColorHex(0xFF5B61, 1.0);
        _chooseButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        _chooseButton.layer.cornerRadius = 16;
        [_chooseButton addTarget:self action:@selector(chooseTapped) forControlEvents:UIControlEventTouchUpInside];
        [_scrollView addSubview:_chooseButton];
        _shortcutsTitle = [[UILabel alloc] init];
        _shortcutsTitle.text = @"Smart Shortcuts";
        _shortcutsTitle.textColor = UIColor.whiteColor;
        _shortcutsTitle.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
        [_scrollView addSubview:_shortcutsTitle];
        NSArray *titles = @[@"Family Group", @"Work Line", @"Voicemail", @"Edit Favorites"];
        NSArray *subtitles = @[@"Quick access", @"Quick call", @"New messages", @"Choose contacts"];
        NSArray *icons = @[@"person.2.fill", @"briefcase.fill", @"recordingtape", @"person.crop.circle.badge.plus"];
        NSArray *colors = @[PAColorHex(0x7C4DFF,1), PAColorHex(0xFF7A1A,1), PAColorHex(0x18C8B7,1), PAColorHex(0x202B49,1)];
        NSMutableArray *buttons = [NSMutableArray array];
        for (NSUInteger index=0; index<titles.count; index++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.tag = index;
            button.backgroundColor = colors[index];
            button.tintColor = UIColor.whiteColor;
            button.layer.cornerRadius = 16;
            button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            button.contentEdgeInsets = UIEdgeInsetsMake(0, 13, 0, 8);
            [button setImage:[UIImage systemImageNamed:icons[index]] forState:UIControlStateNormal];
            NSString *combined = [NSString stringWithFormat:@"  %@\n  %@", titles[index], subtitles[index]];
            NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:combined attributes:@{NSForegroundColorAttributeName:UIColor.whiteColor, NSFontAttributeName:[UIFont systemFontOfSize:12 weight:UIFontWeightBold]}];
            NSRange subtitleRange = [combined rangeOfString:subtitles[index]];
            if (subtitleRange.location != NSNotFound) [text addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:10 weight:UIFontWeightMedium] range:subtitleRange];
            [button setAttributedTitle:text forState:UIControlStateNormal];
            button.titleLabel.numberOfLines = 2;
            [button addTarget:self action:@selector(shortcutTapped:) forControlEvents:UIControlEventTouchUpInside];
            [_scrollView addSubview:button];
            [buttons addObject:button];
        }
        _shortcutButtons = buttons;
    }
    return self;
}

- (void)reloadFavoriteIdentifiers:(NSArray<NSString *> *)identifiers {
    [[PAContactDirectoryV46 sharedDirectory] contactsForIdentifiers:identifiers completion:^(NSArray<CNContact *> *contacts) {
        for (PAFavoriteCardV46 *card in self.favoriteCards) [card removeFromSuperview];
        NSArray *palettes = @[
            @[PAColorHex(0xFF5B61,1), PAColorHex(0xFF7A1A,1)],
            @[PAColorHex(0x6F63FF,1), PAColorHex(0x3B82F6,1)],
            @[PAColorHex(0x18C8B7,1), PAColorHex(0x0F8B8D,1)],
            @[PAColorHex(0xFF7A1A,1), PAColorHex(0xFF3E88,1)]
        ];
        NSMutableArray *cards = [NSMutableArray array];
        NSUInteger count = MIN(contacts.count, (NSUInteger)4);
        for (NSUInteger index=0; index<count; index++) {
            PAFavoriteCardV46 *card = [[PAFavoriteCardV46 alloc] init];
            [card configureContact:contacts[index] colors:palettes[index] large:(index==0)];
            __weak typeof(self) weakSelf = self;
            card.tapHandler = ^(CNContact *contact) {
                PA46Impact(weakSelf.hapticsEnabled);
                NSString *number = PA46PrimaryNumber(contact);
                if (number.length && weakSelf.callHandler) weakSelf.callHandler(number);
            };
            [self.scrollView addSubview:card];
            [cards addObject:card];
        }
        self.favoriteCards = cards;
        self.emptyLabel.hidden = count > 0;
        [self.chooseButton setTitle:(count > 0 ? @"Edit Favorite Contacts" : @"Choose Favorite Contacts") forState:UIControlStateNormal];
        [self setNeedsLayout];
    }];
}

- (void)chooseTapped {
    PA46Impact(self.hapticsEnabled);
    if (self.chooseHandler) self.chooseHandler();
}

- (void)shortcutTapped:(UIButton *)sender {
    PA46Impact(self.hapticsEnabled);
    if (sender.tag == 2) {
        NSURL *url = [NSURL URLWithString:@"mobilephone-voicemail://"];
        if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    } else if (sender.tag == 3 && self.chooseHandler) {
        self.chooseHandler();
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.scrollView.frame = self.bounds;
    CGFloat width = CGRectGetWidth(self.bounds), inset = 16, y = 10;
    if (self.favoriteCards.count == 0) {
        self.emptyLabel.frame = CGRectMake(24, y+20, width-48, 40);
        self.chooseButton.frame = CGRectMake((width-230)/2.0, CGRectGetMaxY(self.emptyLabel.frame)+10, 230, 50);
        y = CGRectGetMaxY(self.chooseButton.frame)+28;
    } else {
        PAFavoriteCardV46 *hero = self.favoriteCards.firstObject;
        hero.frame = CGRectMake(inset, y, width-inset*2, 126);
        y = CGRectGetMaxY(hero.frame)+10;
        CGFloat gap=10, half=(width-inset*2-gap)/2.0;
        for (NSUInteger index=1; index<self.favoriteCards.count; index++) {
            NSUInteger item=index-1, row=item/2, column=item%2;
            self.favoriteCards[index].frame = CGRectMake(inset+column*(half+gap), y+row*100, half, 90);
        }
        NSUInteger compact = self.favoriteCards.count>1 ? self.favoriteCards.count-1 : 0;
        y += ceil(compact/2.0)*100 + 4;
        self.chooseButton.frame = CGRectMake(inset, y, width-inset*2, 46);
        y = CGRectGetMaxY(self.chooseButton.frame)+22;
    }
    self.shortcutsTitle.frame = CGRectMake(inset, y, width-inset*2, 24);
    y += 32;
    CGFloat gap=10, buttonWidth=(width-inset*2-gap)/2.0;
    for (NSUInteger index=0; index<self.shortcutButtons.count; index++) {
        NSUInteger row=index/2, column=index%2;
        self.shortcutButtons[index].frame = CGRectMake(inset+column*(buttonWidth+gap), y+row*66, buttonWidth, 56);
    }
    y += 140;
    self.scrollView.contentSize = CGSizeMake(width, MAX(y, CGRectGetHeight(self.bounds)+1));
}

@end

#pragma mark - Contacts dashboard

@interface PAContactsDashboardV46 () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property(nonatomic,strong) UISearchBar *searchBar;
@property(nonatomic,strong) PAHeroContactCardV46 *heroCard;
@property(nonatomic,strong) UILabel *myCardMissingLabel;
@property(nonatomic,strong) UITableView *tableView;
@property(nonatomic,strong) NSArray<CNContact *> *allContacts;
@property(nonatomic,strong) NSArray<CNContact *> *filteredContacts;
@property(nonatomic,strong) CNContact *myContact;
@end

@implementation PAContactsDashboardV46

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
        _heroCard = [[PAHeroContactCardV46 alloc] init];
        __weak typeof(self) weakSelf = self;
        _heroCard.tapHandler = ^(CNContact *contact) {
            PA46Impact(weakSelf.hapticsEnabled);
            if (weakSelf.contactHandler) weakSelf.contactHandler(contact);
        };
        [self addSubview:_heroCard];
        _myCardMissingLabel = [[UILabel alloc] init];
        _myCardMissingLabel.text = @"My Card is not set in Contacts / Siri";
        _myCardMissingLabel.textColor = PAColorHex(0xA7B2CA,1);
        _myCardMissingLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _myCardMissingLabel.textAlignment = NSTextAlignmentCenter;
        _myCardMissingLabel.backgroundColor = PAColorHex(0x13273A,0.96);
        _myCardMissingLabel.layer.cornerRadius = 15;
        _myCardMissingLabel.layer.masksToBounds = YES;
        [self addSubview:_myCardMissingLabel];
        _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _tableView.backgroundColor = UIColor.clearColor;
        _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        _tableView.rowHeight = 64;
        _tableView.dataSource = self;
        _tableView.delegate = self;
        [_tableView registerClass:[PAContactRowV46 class] forCellReuseIdentifier:@"contact46"];
        [self addSubview:_tableView];
        [self refresh];
    }
    return self;
}

- (void)refresh {
    [[PAContactDirectoryV46 sharedDirectory] allContacts:^(NSArray<CNContact *> *contacts) {
        self.allContacts = contacts;
        self.filteredContacts = contacts;
        [self.tableView reloadData];
    }];
    [[PAContactDirectoryV46 sharedDirectory] myCard:^(CNContact *contact) {
        self.myContact = contact;
        self.heroCard.hidden = contact == nil;
        self.myCardMissingLabel.hidden = contact != nil;
        if (contact) [self.heroCard configureContact:contact title:@"My Card · Siri" colors:@[PAColorHex(0x18C8B7,1), PAColorHex(0x087B87,1)]];
        [self setNeedsLayout];
    }];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (!searchText.length) self.filteredContacts = self.allContacts;
    else {
        NSString *needle = searchText.lowercaseString;
        self.filteredContacts = [self.allContacts filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CNContact *contact, NSDictionary *bindings) {
            return [PA46ContactName(contact).lowercaseString containsString:needle] || [PA46PrimaryNumber(contact) containsString:needle];
        }]];
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filteredContacts.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PAContactRowV46 *cell = [tableView dequeueReusableCellWithIdentifier:@"contact46" forIndexPath:indexPath];
    if (indexPath.row < self.filteredContacts.count) [cell configureContact:self.filteredContacts[indexPath.row] selected:NO picker:NO];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.filteredContacts.count) return;
    PA46Impact(self.hapticsEnabled);
    if (self.contactHandler) self.contactHandler(self.filteredContacts[indexPath.row]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    self.searchBar.frame = CGRectMake(12, 4, width-24, 46);
    CGFloat y = CGRectGetMaxY(self.searchBar.frame)+7;
    if (!self.heroCard.hidden) {
        self.heroCard.frame = CGRectMake(16, y, width-32, 112);
        y = CGRectGetMaxY(self.heroCard.frame)+9;
    } else {
        self.myCardMissingLabel.frame = CGRectMake(16, y, width-32, 54);
        y = CGRectGetMaxY(self.myCardMissingLabel.frame)+9;
    }
    self.tableView.frame = CGRectMake(0, y, width, MAX(0, CGRectGetHeight(self.bounds)-y));
}

@end

#pragma mark - Favorite picker

@interface PAFavoritePickerViewV46 () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property(nonatomic,strong) UISearchBar *searchBar;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UITableView *tableView;
@property(nonatomic,strong) UIButton *saveButton;
@property(nonatomic,strong) NSArray<CNContact *> *allContacts;
@property(nonatomic,strong) NSArray<CNContact *> *filteredContacts;
@property(nonatomic,strong) NSMutableArray<NSString *> *selectedIdentifiers;
@end

@implementation PAFavoritePickerViewV46

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = PAColorHex(0x040817,1);
        _selectedIdentifiers = [NSMutableArray array];
        _searchBar = [[UISearchBar alloc] init];
        _searchBar.searchBarStyle = UISearchBarStyleMinimal;
        _searchBar.placeholder = @"Search contacts to add";
        _searchBar.delegate = self;
        _searchBar.searchTextField.backgroundColor = PAColorHex(0x17213D,0.98);
        _searchBar.searchTextField.textColor = UIColor.whiteColor;
        _searchBar.searchTextField.tintColor = PAColorHex(0xFF5B61,1);
        [self addSubview:_searchBar];
        _statusLabel = [[UILabel alloc] init];
        _statusLabel.textColor = PAColorHex(0xA7B2CA,1);
        _statusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        [self addSubview:_statusLabel];
        _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _tableView.backgroundColor = UIColor.clearColor;
        _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        _tableView.rowHeight = 64;
        _tableView.dataSource = self;
        _tableView.delegate = self;
        [_tableView registerClass:[PAContactRowV46 class] forCellReuseIdentifier:@"picker46"];
        [self addSubview:_tableView];
        _saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_saveButton setTitle:@"Save Favorites" forState:UIControlStateNormal];
        [_saveButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        _saveButton.backgroundColor = PAColorHex(0xFF5B61,1);
        _saveButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        _saveButton.layer.cornerRadius = 16;
        [_saveButton addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_saveButton];
        [[PAContactDirectoryV46 sharedDirectory] allContacts:^(NSArray<CNContact *> *contacts) {
            self.allContacts = contacts;
            self.filteredContacts = contacts;
            [self.tableView reloadData];
        }];
        [self updateStatus];
    }
    return self;
}

- (void)reloadSelectedIdentifiers:(NSArray<NSString *> *)identifiers {
    self.selectedIdentifiers = [NSMutableArray array];
    for (NSString *identifier in identifiers) {
        if ([identifier isKindOfClass:[NSString class]] && identifier.length && ![self.selectedIdentifiers containsObject:identifier]) {
            [self.selectedIdentifiers addObject:identifier];
            if (self.selectedIdentifiers.count >= 4) break;
        }
    }
    [self updateStatus];
    [self.tableView reloadData];
}

- (void)updateStatus {
    self.statusLabel.text = [NSString stringWithFormat:@"%lu of 4 selected", (unsigned long)self.selectedIdentifiers.count];
    self.saveButton.alpha = 1.0;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (!searchText.length) self.filteredContacts = self.allContacts;
    else {
        NSString *needle = searchText.lowercaseString;
        self.filteredContacts = [self.allContacts filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CNContact *contact, NSDictionary *bindings) {
            return [PA46ContactName(contact).lowercaseString containsString:needle] || [PA46PrimaryNumber(contact) containsString:needle];
        }]];
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filteredContacts.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PAContactRowV46 *cell = [tableView dequeueReusableCellWithIdentifier:@"picker46" forIndexPath:indexPath];
    if (indexPath.row < self.filteredContacts.count) {
        CNContact *contact = self.filteredContacts[indexPath.row];
        [cell configureContact:contact selected:[self.selectedIdentifiers containsObject:contact.identifier] picker:YES];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.filteredContacts.count) return;
    CNContact *contact = self.filteredContacts[indexPath.row];
    NSString *identifier = contact.identifier;
    if (!identifier.length) return;
    if ([self.selectedIdentifiers containsObject:identifier]) {
        [self.selectedIdentifiers removeObject:identifier];
        PA46Impact(self.hapticsEnabled);
    } else if (self.selectedIdentifiers.count < 4) {
        [self.selectedIdentifiers addObject:identifier];
        PA46Impact(self.hapticsEnabled);
    } else {
        UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
        [generator notificationOccurred:UINotificationFeedbackTypeWarning];
        self.statusLabel.text = @"Maximum four favorites";
        return;
    }
    [self updateStatus];
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)saveTapped {
    PA46Impact(self.hapticsEnabled);
    if (self.saveHandler) self.saveHandler([self.selectedIdentifiers copy]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width=CGRectGetWidth(self.bounds), height=CGRectGetHeight(self.bounds);
    self.searchBar.frame = CGRectMake(12, 4, width-24, 46);
    self.statusLabel.frame = CGRectMake(20, 50, width-40, 22);
    self.saveButton.frame = CGRectMake(16, height-58, width-32, 48);
    CGFloat tableTop=76;
    self.tableView.frame = CGRectMake(0, tableTop, width, MAX(0, CGRectGetMinY(self.saveButton.frame)-tableTop-8));
}

@end

#pragma mark - Inline contact detail

@interface PAContactDetailViewV46 ()
@property(nonatomic,strong) UIScrollView *scrollView;
@property(nonatomic,strong) UIImageView *avatar;
@property(nonatomic,strong) UILabel *nameLabel;
@property(nonatomic,strong) UILabel *subtitleLabel;
@property(nonatomic,strong) UIStackView *actions;
@property(nonatomic,strong) UIButton *callButton;
@property(nonatomic,strong) UIButton *messageButton;
@property(nonatomic,strong) UIButton *facetimeButton;
@property(nonatomic,strong) UIView *numbersCard;
@property(nonatomic,strong) UILabel *numbersLabel;
@property(nonatomic,strong) CNContact *contact;
@end

@implementation PAContactDetailViewV46

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = PAColorHex(0x040817,1);
        _scrollView = [[UIScrollView alloc] init];
        _scrollView.alwaysBounceVertical = YES;
        [self addSubview:_scrollView];
        _avatar = [[UIImageView alloc] init];
        _avatar.clipsToBounds = YES;
        _avatar.backgroundColor = PAColorHex(0x18C8B7,0.18);
        [_scrollView addSubview:_avatar];
        _nameLabel = [[UILabel alloc] init];
        _nameLabel.textColor = UIColor.whiteColor;
        _nameLabel.font = [UIFont systemFontOfSize:27 weight:UIFontWeightBold];
        _nameLabel.textAlignment = NSTextAlignmentCenter;
        _nameLabel.adjustsFontSizeToFitWidth = YES;
        _nameLabel.minimumScaleFactor = 0.65;
        [_scrollView addSubview:_nameLabel];
        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.text = @"PhoneAura Contact";
        _subtitleLabel.textColor = PAColorHex(0xA7B2CA,1);
        _subtitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _subtitleLabel.textAlignment = NSTextAlignmentCenter;
        [_scrollView addSubview:_subtitleLabel];
        _actions = [[UIStackView alloc] init];
        _actions.axis = UILayoutConstraintAxisHorizontal;
        _actions.distribution = UIStackViewDistributionFillEqually;
        _actions.spacing = 10;
        [_scrollView addSubview:_actions];
        _callButton = [self actionButton:@"Call" icon:@"phone.fill" color:PAColorHex(0x22C55E,1) selector:@selector(callTapped)];
        _messageButton = [self actionButton:@"Message" icon:@"message.fill" color:PAColorHex(0x3B82F6,1) selector:@selector(messageTapped)];
        _facetimeButton = [self actionButton:@"FaceTime" icon:@"video.fill" color:PAColorHex(0x18C8B7,1) selector:@selector(facetimeTapped)];
        [_actions addArrangedSubview:_callButton];
        [_actions addArrangedSubview:_messageButton];
        [_actions addArrangedSubview:_facetimeButton];
        _numbersCard = [[UIView alloc] init];
        _numbersCard.backgroundColor = PAColorHex(0x152A38,0.96);
        _numbersCard.layer.cornerRadius = 18;
        _numbersCard.layer.cornerCurve = kCACornerCurveContinuous;
        [_scrollView addSubview:_numbersCard];
        _numbersLabel = [[UILabel alloc] init];
        _numbersLabel.textColor = UIColor.whiteColor;
        _numbersLabel.numberOfLines = 0;
        _numbersLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        [_numbersCard addSubview:_numbersLabel];
    }
    return self;
}

- (UIButton *)actionButton:(NSString *)title icon:(NSString *)icon color:(UIColor *)color selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = color;
    button.tintColor = UIColor.whiteColor;
    button.layer.cornerRadius = 17;
    button.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    button.titleLabel.numberOfLines = 2;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    [button setImage:[UIImage systemImageNamed:icon] forState:UIControlStateNormal];
    [button setTitle:[NSString stringWithFormat:@"\n%@", title] forState:UIControlStateNormal];
    button.imageEdgeInsets = UIEdgeInsetsMake(-14, 20, 12, -20);
    button.titleEdgeInsets = UIEdgeInsetsMake(24, -18, -4, 0);
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)configureContact:(CNContact *)contact {
    self.contact = contact;
    self.nameLabel.text = PA46ContactName(contact);
    UIImage *image = PA46ContactImage(contact);
    self.avatar.image = image ?: [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.avatar.tintColor = PAColorHex(0x18C8B7,1);
    self.avatar.contentMode = image ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
    NSArray<NSString *> *numbers = PA46ContactNumbers(contact);
    self.numbersLabel.text = numbers.count ? [numbers componentsJoinedByString:@"\n\n"] : @"No phone numbers saved";
    BOOL hasNumber = numbers.count > 0;
    self.callButton.enabled = hasNumber;
    self.messageButton.enabled = hasNumber;
    self.facetimeButton.enabled = hasNumber;
    self.actions.alpha = hasNumber ? 1.0 : 0.45;
    [self setNeedsLayout];
}

- (NSString *)primaryNumber { return PA46PrimaryNumber(self.contact); }

- (void)callTapped {
    PA46Impact(self.hapticsEnabled);
    NSString *number = [self primaryNumber];
    if (number.length && self.callHandler) self.callHandler(number);
}

- (void)openScheme:(NSString *)scheme {
    NSString *number = [self primaryNumber];
    if (!number.length) return;
    NSString *escaped = [number stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@:%@", scheme, escaped ?: number]];
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (void)messageTapped { PA46Impact(self.hapticsEnabled); [self openScheme:@"sms"]; }
- (void)facetimeTapped { PA46Impact(self.hapticsEnabled); [self openScheme:@"facetime"]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    self.scrollView.frame = self.bounds;
    CGFloat width=CGRectGetWidth(self.bounds), y=18;
    self.avatar.frame = CGRectMake((width-116)/2.0, y, 116, 116);
    self.avatar.layer.cornerRadius = 58;
    y = CGRectGetMaxY(self.avatar.frame)+14;
    self.nameLabel.frame = CGRectMake(20, y, width-40, 38);
    y += 40;
    self.subtitleLabel.frame = CGRectMake(20, y, width-40, 22);
    y += 38;
    self.actions.frame = CGRectMake(16, y, width-32, 76);
    y += 92;
    CGFloat numbersHeight = MAX(80, [self.numbersLabel sizeThatFits:CGSizeMake(width-64, CGFLOAT_MAX)].height+34);
    self.numbersCard.frame = CGRectMake(16, y, width-32, numbersHeight);
    self.numbersLabel.frame = CGRectInset(self.numbersCard.bounds, 16, 16);
    y = CGRectGetMaxY(self.numbersCard.frame)+20;
    self.scrollView.contentSize = CGSizeMake(width, MAX(y, CGRectGetHeight(self.bounds)+1));
}

@end
