#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parent

# Bump all package/version surfaces from 1.0.5 to 1.0.6.
for rel in ['control', 'ConsoleBridge.m', 'Preferences/Resources/Info.plist', 'Preferences/NQRDiagnosticsController.m', 'layout/DEBIAN/postinst']:
    path = root / rel
    text = path.read_text().replace('1.0.5', '1.0.6')
    if rel == 'control':
        lines = []
        for line in text.splitlines():
            if line.startswith('Description:'):
                line = 'Description: RootHide quick reminder card with reliable multi-trigger access, Lock Screen support, background saving, in-panel Quick Access settings, and restored keyboard input.'
            lines.append(line)
        text = '\n'.join(lines) + '\n'
    path.write_text(text)

# Fix keyboard visibility/focus in the SpringBoard overlay window.
tweak = root / 'Tweak.xm'
text = tweak.read_text()
text = text.replace(
    '@interface NQRQuickPanelController : UIViewController <UITextViewDelegate>',
    '@interface NQRQuickPanelController : UIViewController <UITextViewDelegate, UITextFieldDelegate>',
    1,
)

old_title = '''    self.titleField.returnKeyType = UIReturnKeyNext;
    [self.titleField addTarget:self action:@selector(titleSubmitted) forControlEvents:UIControlEventEditingDidEndOnExit];
'''
new_title = '''    self.titleField.returnKeyType = UIReturnKeyNext;
    self.titleField.delegate = self;
    self.titleField.userInteractionEnabled = YES;
    [self.titleField addTarget:self action:@selector(nqr106_titleTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.titleField addTarget:self action:@selector(titleSubmitted) forControlEvents:UIControlEventEditingDidEndOnExit];
'''
if old_title not in text:
    raise SystemExit('Title-field keyboard anchor not found')
text = text.replace(old_title, new_title, 1)

old_notes = '''    self.notesView.backgroundColor = UIColor.clearColor;
    self.notesView.font = [UIFont systemFontOfSize:15];
    self.notesView.delegate = self;
    [notesContainer addSubview:self.notesView];
'''
new_notes = '''    self.notesView.backgroundColor = UIColor.clearColor;
    self.notesView.font = [UIFont systemFontOfSize:15];
    self.notesView.delegate = self;
    self.notesView.editable = YES;
    self.notesView.selectable = YES;
    self.notesView.userInteractionEnabled = YES;
    UITapGestureRecognizer *notesTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(nqr106_notesTapped:)];
    notesTap.cancelsTouchesInView = NO;
    [self.notesView addGestureRecognizer:notesTap];
    [notesContainer addSubview:self.notesView];
'''
if old_notes not in text:
    raise SystemExit('Notes-view keyboard anchor not found')
text = text.replace(old_notes, new_notes, 1)

old_methods = '''- (void)titleSubmitted {
    [self.notesView becomeFirstResponder];
}

- (void)textViewDidChange:(UITextView *)textView {
'''
new_methods = '''- (void)nqr106_prepareKeyboardForResponder:(UIResponder *)responder source:(NSString *)source {
    if (!responder) return;
    if (NQRPanelWindow) {
        NQRPanelWindow.hidden = NO;
        [NQRPanelWindow makeKeyAndVisible];
        [NQRPanelWindow makeKeyWindow];
    }
    BOOL accepted = [responder becomeFirstResponder];
    NQRLog(@"Keyboard focus request source=%@ keyWindow=%@ accepted=%@ firstResponder=%@", source ?: @"unknown", NQRPanelWindow.isKeyWindow ? @"YES" : @"NO", accepted ? @"YES" : @"NO", responder.isFirstResponder ? @"YES" : @"NO");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (NQRPanelWindow && !NQRPanelWindow.isKeyWindow) [NQRPanelWindow makeKeyWindow];
        if (!responder.isFirstResponder) [responder becomeFirstResponder];
        [responder reloadInputViews];
    });
}

- (void)nqr106_titleTouchDown:(UITextField *)field {
    [self nqr106_prepareKeyboardForResponder:field source:@"title touch"];
}

- (void)nqr106_notesTapped:(UITapGestureRecognizer *)tap {
    if (tap.state == UIGestureRecognizerStateRecognized) {
        [self nqr106_prepareKeyboardForResponder:self.notesView source:@"notes touch"];
    }
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    if (NQRPanelWindow && !NQRPanelWindow.isKeyWindow) [NQRPanelWindow makeKeyWindow];
    return YES;
}

- (BOOL)textViewShouldBeginEditing:(UITextView *)textView {
    if (NQRPanelWindow && !NQRPanelWindow.isKeyWindow) [NQRPanelWindow makeKeyWindow];
    return YES;
}

- (void)titleSubmitted {
    [self nqr106_prepareKeyboardForResponder:self.notesView source:@"title return"];
}

- (void)textViewDidChange:(UITextView *)textView {
'''
if old_methods not in text:
    raise SystemExit('Keyboard method insertion anchor not found')
text = text.replace(old_methods, new_methods, 1)

# Keep the overlay above normal SpringBoard content but below system keyboard windows.
text = text.replace('NQRPanelWindow.windowLevel = UIWindowLevelAlert + 3000;', 'NQRPanelWindow.windowLevel = UIWindowLevelAlert + 40.0;', 1)

# Reassert key-window ownership after the card becomes visible.
old_appear = '''- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.cardView) return;
'''
new_appear = '''- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (NQRPanelWindow) {
        [NQRPanelWindow makeKeyAndVisible];
        [NQRPanelWindow makeKeyWindow];
    }
    if (!self.cardView) return;
'''
if old_appear not in text:
    raise SystemExit('viewDidAppear keyboard anchor not found')
text = text.replace(old_appear, new_appear, 1)

text = text.replace('Next Quick Reminder 1.0.3 loaded with visible-panel layout fix in safe startup mode', 'Next Quick Reminder 1.0.6 loaded with multi-trigger keyboard fix', 1)
tweak.write_text(text)

# The lock-screen helper previously raised the panel far above normal alert windows,
# which could also place it above the system keyboard. Keep it at the same keyboard-safe level.
background = root / 'BackgroundLockscreen.xm'
bg = background.read_text()
bg = bg.replace('window.windowLevel = UIWindowLevelAlert + 5000;', 'window.windowLevel = UIWindowLevelAlert + 40.0;', 1)
background.write_text(bg)

print('Prepared Next Quick Reminder 1.0.6 keyboard and focus fix.')
