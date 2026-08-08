#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).with_name("Tweak.xm")
text = path.read_text()

old_target = '[dismissArea addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];'
new_target = '[dismissArea addTarget:self action:@selector(backgroundTapped) forControlEvents:UIControlEventTouchUpInside];'
if old_target not in text:
    raise SystemExit('Panel background target was not found')
text = text.replace(old_target, new_target, 1)

old_height_anchor = '''        [card.widthAnchor constraintLessThanOrEqualToConstant:420],
        [card.widthAnchor constraintEqualToAnchor:self.view.widthAnchor constant:-28],
        [card.topAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],'''
new_height_anchor = '''        [card.widthAnchor constraintLessThanOrEqualToConstant:420],
        [card.widthAnchor constraintEqualToAnchor:self.view.widthAnchor constant:-28],
        [card.heightAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.heightAnchor multiplier:0.78],
        [card.topAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],'''
if old_height_anchor not in text:
    raise SystemExit('Panel card constraint anchor was not found')
text = text.replace(old_height_anchor, new_height_anchor, 1)

text = text.replace(
    '    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;\n',
    '    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;\n    scrollView.alwaysBounceVertical = YES;\n',
    1,
)

method_anchor = '''- (void)cancelTapped {
    NQRLog(@"Quick panel cancelled");
    NQRDismissPanel();
}
'''
method_replacement = '''- (void)backgroundTapped {
    [self.view endEditing:YES];
    NQRLog(@"Panel background tapped; form remains open");
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.view layoutIfNeeded];
    UIView *card = self.view.subviews.lastObject;
    NQRLog(@"Quick panel form visible root=%@ card=%@ subviews=%lu", NSStringFromCGRect(self.view.frame), NSStringFromCGRect(card.frame), (unsigned long)card.subviews.count);
}

- (void)cancelTapped {
    NQRLog(@"Quick panel cancelled by Cancel button");
    NQRDismissPanel();
}
'''
if method_anchor not in text:
    raise SystemExit('Panel cancel method anchor was not found')
text = text.replace(method_anchor, method_replacement, 1)

text = text.replace('card.backgroundColor = UIColor.secondarySystemBackgroundColor;', 'card.backgroundColor = UIColor.systemBackgroundColor;', 1)
text = text.replace('Next Quick Reminder 1.0.2 loaded in safe startup mode', 'Next Quick Reminder 1.0.3 loaded with visible panel layout', 1)

path.write_text(text)
print('Applied Next Quick Reminder 1.0.3 visible panel layout fix.')
