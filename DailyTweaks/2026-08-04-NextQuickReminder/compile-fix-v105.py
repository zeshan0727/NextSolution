#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).with_name('MultiTriggersSettings.xm')
text = path.read_text()
old = '''        UIWindowScene *scene = NQR105ActiveScene();
        if (!NQR105StatusWindow || (@available(iOS 13.0, *) && scene && NQR105StatusWindow.windowScene != scene)) {
            NQR105DestroyStatusWindow();
            if (@available(iOS 13.0, *)) {'''
new = '''        UIWindowScene *scene = NQR105ActiveScene();
        BOOL needsNewWindow = (NQR105StatusWindow == nil);
        if (@available(iOS 13.0, *)) {
            if (scene && NQR105StatusWindow && NQR105StatusWindow.windowScene != scene) {
                needsNewWindow = YES;
            }
        }
        if (needsNewWindow) {
            NQR105DestroyStatusWindow();
            if (@available(iOS 13.0, *)) {'''
if old not in text:
    raise SystemExit('v1.0.5 availability guard anchor not found')
path.write_text(text.replace(old, new, 1))
print('Applied v1.0.5 compiler compatibility fix.')
