#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static NSString * const NPDomain = @"com.nextpassword.keyboard";
static UIWindow *NPOverlayWindow;
static UIButton *NPShieldButton;
static UIViewController *NPPresentedController;

static NSInteger NPPosition(unichar c) {
    unichar u = [[NSString stringWithCharacters:&c length:1].uppercaseString characterAtIndex:0];
    return (u >= 'A' && u <= 'Z') ? (u - 'A' + 1) : 0;
}

static NSString *NPPasswordForSite(NSString *site) {
    NSMutableString *letters = [NSMutableString string];
    for (NSUInteger i = 0; i < site.length; i++) {
        unichar c = [site characterAtIndex:i];
        if ([[NSCharacterSet letterCharacterSet] characterIsMember:c]) [letters appendFormat:@"%C", c];
    }
    if (letters.length == 0) return @"MpMr@";
    NSInteger count = letters.length;
    NSInteger first = NPPosition([letters characterAtIndex:0]);
    NSInteger last = NPPosition([letters characterAtIndex:letters.length - 1]);
    return [NSString stringWithFormat:@"MpMr@%ld%02ld%02ld", (long)count, (long)first, (long)last];
}

static id NPFirstResponder(UIView *view) {
    if (view.isFirstResponder) return view;
    for (UIView *subview in view.subviews) {
        id responder = NPFirstResponder(subview);
        if (responder) return responder;
    }
    return nil;
}

static UIWindow *NPAppWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
        }
    }
    return UIApplication.sharedApplication.keyWindow;
}

static void NPInsertText(NSString *text) {
    UIWindow *window = NPAppWindow();
    id responder = window ? NPFirstResponder(window) : nil;
    if ([responder conformsToProtocol:@protocol(UITextInput)] && [responder respondsToSelector:@selector(insertText:)]) {
        [responder insertText:text];
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
    } else {
        UIPasteboard.generalPasteboard.string = text;
    }
}

static NSArray *NPLoadEntries(void) {
    CFPropertyListRef value = CFPreferencesCopyValue(CFSTR("entries"), (__bridge CFStringRef)NPDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    return CFBridgingRelease(value) ?: @[];
}

static void NPSaveEntry(NSString *site, NSString *password) {
    NSMutableArray *entries = [NPLoadEntries() mutableCopy];
    NSIndexSet *duplicates = [entries indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
        return [item[@"site"] caseInsensitiveCompare:site] == NSOrderedSame;
    }];
    if (duplicates.count) [entries removeObjectsAtIndexes:duplicates];
    [entries insertObject:@{ @"site": site, @"password": password } atIndex:0];
    if (entries.count > 30) [entries removeObjectsInRange:NSMakeRange(30, entries.count - 30)];
    CFPreferencesSetValue(CFSTR("entries"), (__bridge CFArrayRef)entries, (__bridge CFStringRef)NPDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)NPDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

@interface NPPanelController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property(nonatomic,strong) UITextField *siteField;
@property(nonatomic,strong) UILabel *passwordLabel;
@property(nonatomic,strong) UILabel *helperLabel;
@property(nonatomic,strong) UITableView *tableView;
@property(nonatomic,strong) NSArray *entries;
@end

@implementation NPPanelController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.98];
    self.preferredContentSize = CGSizeMake(390, 520);
    self.entries = NPLoadEntries();

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Next Password";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:22];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setTitle:@"Done" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];

    self.siteField = [[UITextField alloc] init];
    self.siteField.translatesAutoresizingMaskIntoConstraints = NO;
    self.siteField.placeholder = @"Website or app name";
    self.siteField.textColor = UIColor.whiteColor;
    self.siteField.backgroundColor = [UIColor colorWithWhite:0.13 alpha:1];
    self.siteField.layer.cornerRadius = 12;
    self.siteField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,12,1)];
    self.siteField.leftViewMode = UITextFieldViewModeAlways;
    [self.siteField addTarget:self action:@selector(siteChanged) forControlEvents:UIControlEventEditingChanged];

    self.helperLabel = [[UILabel alloc] init];
    self.helperLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.helperLabel.textColor = UIColor.secondaryLabelColor;
    self.helperLabel.font = [UIFont systemFontOfSize:12];
    self.helperLabel.numberOfLines = 2;
    self.helperLabel.text = @"Type a website to calculate length, first letter and last letter positions.";

    self.passwordLabel = [[UILabel alloc] init];
    self.passwordLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.passwordLabel.text = @"MpMr@";
    self.passwordLabel.textColor = [UIColor colorWithRed:0.25 green:0.82 blue:0.45 alpha:1];
    self.passwordLabel.font = [UIFont monospacedSystemFontOfSize:22 weight:UIFontWeightBold];

    UIButton *insert = [UIButton buttonWithType:UIButtonTypeSystem];
    insert.translatesAutoresizingMaskIntoConstraints = NO;
    insert.backgroundColor = UIColor.systemBlueColor;
    insert.layer.cornerRadius = 12;
    [insert setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [insert setTitle:@"Insert & Save" forState:UIControlStateNormal];
    [insert addTarget:self action:@selector(insertGenerated) forControlEvents:UIControlEventTouchUpInside];

    UILabel *saved = [[UILabel alloc] init];
    saved.translatesAutoresizingMaskIntoConstraints = NO;
    saved.text = @"Saved Passwords";
    saved.textColor = UIColor.whiteColor;
    saved.font = [UIFont boldSystemFontOfSize:16];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;

    [self.view addSubview:title]; [self.view addSubview:close]; [self.view addSubview:self.siteField];
    [self.view addSubview:self.helperLabel]; [self.view addSubview:self.passwordLabel]; [self.view addSubview:insert];
    [self.view addSubview:saved]; [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:18],
        [title.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18],
        [close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor], [close.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18],
        [self.siteField.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:18],
        [self.siteField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16], [self.siteField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16], [self.siteField.heightAnchor constraintEqualToConstant:48],
        [self.helperLabel.topAnchor constraintEqualToAnchor:self.siteField.bottomAnchor constant:8], [self.helperLabel.leadingAnchor constraintEqualToAnchor:self.siteField.leadingAnchor], [self.helperLabel.trailingAnchor constraintEqualToAnchor:self.siteField.trailingAnchor],
        [self.passwordLabel.topAnchor constraintEqualToAnchor:self.helperLabel.bottomAnchor constant:14], [self.passwordLabel.leadingAnchor constraintEqualToAnchor:self.siteField.leadingAnchor],
        [insert.centerYAnchor constraintEqualToAnchor:self.passwordLabel.centerYAnchor], [insert.trailingAnchor constraintEqualToAnchor:self.siteField.trailingAnchor], [insert.widthAnchor constraintEqualToConstant:120], [insert.heightAnchor constraintEqualToConstant:42],
        [saved.topAnchor constraintEqualToAnchor:self.passwordLabel.bottomAnchor constant:22], [saved.leadingAnchor constraintEqualToAnchor:self.siteField.leadingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:saved.bottomAnchor constant:4], [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}
- (void)siteChanged {
    NSString *site = self.siteField.text ?: @"";
    NSString *password = NPPasswordForSite(site);
    self.passwordLabel.text = password;
    NSMutableString *letters = [NSMutableString string];
    for (NSUInteger i=0;i<site.length;i++){ unichar c=[site characterAtIndex:i]; if([[NSCharacterSet letterCharacterSet] characterIsMember:c]) [letters appendFormat:@"%C",c]; }
    if (letters.length) self.helperLabel.text = [NSString stringWithFormat:@"Length %lu • %@=%02ld • %@=%02ld", (unsigned long)letters.length, [[letters substringToIndex:1] uppercaseString], (long)NPPosition([letters characterAtIndex:0]), [[letters substringFromIndex:letters.length-1] uppercaseString], (long)NPPosition([letters characterAtIndex:letters.length-1])];
}
- (void)insertGenerated {
    NSString *site = [self.siteField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!site.length) return;
    NSString *password = NPPasswordForSite(site);
    NPSaveEntry(site, password);
    NPInsertText(password);
    [self closePanel];
}
- (void)closePanel { [self dismissViewControllerAnimated:YES completion:nil]; NPPresentedController = nil; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.entries.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"entry"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"entry"];
    NSDictionary *entry = self.entries[indexPath.row]; cell.textLabel.text = entry[@"site"]; cell.detailTextLabel.text = entry[@"password"]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { NPInsertText(self.entries[indexPath.row][@"password"]); [self closePanel]; }
@end

static void NPShowPanel(void) {
    UIWindow *window = NPAppWindow(); if (!window || NPPresentedController) return;
    UIViewController *root = window.rootViewController; while (root.presentedViewController) root = root.presentedViewController;
    NPPanelController *panel = [NPPanelController new]; panel.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) { panel.sheetPresentationController.detents = @[[UISheetPresentationControllerDetent mediumDetent], [UISheetPresentationControllerDetent largeDetent]]; panel.sheetPresentationController.prefersGrabberVisible = YES; }
    NPPresentedController = panel; [root presentViewController:panel animated:YES completion:^{ [panel.siteField becomeFirstResponder]; }];
}

static void NPKeyboardWillShow(NSNotification *note) {
    CGRect frame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue]; UIWindow *window = NPAppWindow(); if (!window) return;
    if (!NPShieldButton) {
        NPShieldButton = [UIButton buttonWithType:UIButtonTypeSystem]; NPShieldButton.frame = CGRectMake(0,0,44,44); NPShieldButton.layer.cornerRadius = 22; NPShieldButton.backgroundColor = UIColor.systemBlueColor; NPShieldButton.tintColor = UIColor.whiteColor;
        [NPShieldButton setImage:[UIImage systemImageNamed:@"lock.shield.fill"] forState:UIControlStateNormal]; [NPShieldButton addTarget:[NSBlockOperation blockOperationWithBlock:^{ NPShowPanel(); }] action:@selector(main) forControlEvents:UIControlEventTouchUpInside];
    }
    if (NPShieldButton.superview != window) [window addSubview:NPShieldButton];
    CGFloat y = frame.origin.y - 52; NPShieldButton.frame = CGRectMake(window.bounds.size.width - 58, y, 44, 44); NPShieldButton.hidden = NO;
}
static void NPKeyboardWillHide(NSNotification *note) { NPShieldButton.hidden = YES; }

%ctor {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardWillShowNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){ NPKeyboardWillShow(note); }];
            [NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardWillHideNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){ NPKeyboardWillHide(note); }];
        });
    }
}
