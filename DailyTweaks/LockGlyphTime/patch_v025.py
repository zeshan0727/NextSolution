#!/usr/bin/env python3
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parent
runtime_path = ROOT / "RuntimeV023.xm"
src = runtime_path.read_text()

anchor = '''typedef void(*LGTLayoutIMP)(id,SEL);static LGTLayoutIMP gOriginalLayout=NULL;'''
if anchor not in src:
    raise SystemExit("Direct clock hook anchor not found")

hook_code = r'''
static BOOL gLGTInternalLabelMutation = NO;
typedef void(*LGTSetTextIMP)(id,SEL,NSString *);
typedef void(*LGTSetAttributedTextIMP)(id,SEL,NSAttributedString *);
static LGTSetTextIMP gOriginalUILabelSetText = NULL;
static LGTSetAttributedTextIMP gOriginalUILabelSetAttributedText = NULL;

static UIView *LGTLockScreenContainerForLabel(UILabel *label) {
    UIView *view = label;
    while (view) {
        NSString *name = NSStringFromClass(view.class);
        if ([name isEqualToString:@"SBFLockScreenDateView"] ||
            [name isEqualToString:@"CSDateView"] ||
            [name isEqualToString:@"SBFLockScreenDateSubtitleView"] ||
            [name containsString:@"LockScreenDateView"] ||
            [name containsString:@"CSDateView"]) {
            return view;
        }
        view = view.superview;
    }
    return nil;
}

static BOOL LGTLabelIsResolvedTime(UILabel *label, UIView *container) {
    if (!label || !container) return NO;
    UILabel *time = nil, *date = nil;
    LGTResolveLabels(container, &time, &date);
    if (label == time) return YES;
    NSString *text = label.text ?: label.attributedText.string ?: @"";
    NSUInteger digits = 0;
    for (NSUInteger i = 0; i < text.length; i++) {
        if ([NSCharacterSet.decimalDigitCharacterSet characterIsMember:[text characterAtIndex:i]]) digits++;
    }
    return digits >= 3 && ([text containsString:@":"] || [text containsString:@"."]);
}

static void LGTReapplyAfterAppleClockMutation(UILabel *label, BOOL attributedMutation) {
    if (!label || gLGTInternalLabelMutation || !gEnabled) return;
    UIView *container = LGTLockScreenContainerForLabel(label);
    if (!container) return;
    if (!LGTLabelIsResolvedTime(label, container)) return;

    LGTLabelState *state = LGTStateForLabel(label);
    if (attributedMutation) {
        state.nativeAttributedText = [label.attributedText copy];
        state.nativeText = label.attributedText.string ?: label.text;
    } else {
        state.nativeText = [label.text copy];
        state.nativeAttributedText = nil;
    }

    __weak UILabel *weakLabel = label;
    __weak UIView *weakContainer = container;
    dispatch_async(dispatch_get_main_queue(), ^{
        UILabel *strongLabel = weakLabel;
        UIView *strongContainer = weakContainer;
        if (!strongLabel || !strongContainer || !strongLabel.window || !gEnabled || !gCustomTimeEnabled) return;
        gLGTInternalLabelMutation = YES;
        LGTApplyTimeAppearance(strongLabel);
        LGTApplyFinalGeometry(strongContainer);
        gLGTInternalLabelMutation = NO;
    });
}

static void LGTHookedUILabelSetText(id self, SEL _cmd, NSString *text) {
    if (gOriginalUILabelSetText) gOriginalUILabelSetText(self, _cmd, text);
    if ([self isKindOfClass:UILabel.class]) LGTReapplyAfterAppleClockMutation((UILabel *)self, NO);
}

static void LGTHookedUILabelSetAttributedText(id self, SEL _cmd, NSAttributedString *text) {
    if (gOriginalUILabelSetAttributedText) gOriginalUILabelSetAttributedText(self, _cmd, text);
    if ([self isKindOfClass:UILabel.class]) LGTReapplyAfterAppleClockMutation((UILabel *)self, YES);
}

'''
src = src.replace(anchor, hook_code + anchor, 1)

old_ctor = '''        LGTStartLiveClockTimer();'''
new_ctor = '''        LGTStartLiveClockTimer();\n        MSHookMessageEx(UILabel.class,@selector(setText:),(IMP)LGTHookedUILabelSetText,(IMP *)&gOriginalUILabelSetText);\n        MSHookMessageEx(UILabel.class,@selector(setAttributedText:),(IMP)LGTHookedUILabelSetAttributedText,(IMP *)&gOriginalUILabelSetAttributedText);'''
if old_ctor not in src:
    raise SystemExit("Live-clock ctor line not found")
src = src.replace(old_ctor, new_ctor, 1)
runtime_path.write_text(src)

control_path = ROOT / "control"
control = control_path.read_text()
control = control.replace("Version: 1.0.2", "Version: 1.0.3")
if "live clock refresh" in control:
    control = control.replace("Version 1.0.2 fixes live clock refresh so customized time updates automatically without respring.",
                              "Version 1.0.3 follows Apple's native Lock Screen clock text updates directly, with the timer retained as a fallback.")
control_path.write_text(control)

resources = ROOT / "prefs" / "Resources"
info_path = resources / "Info.plist"
info = plistlib.loads(info_path.read_bytes())
info["CFBundleShortVersionString"] = "1.0.3"
info["CFBundleVersion"] = "103"
info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=False))

about_path = resources / "About.plist"
about = plistlib.loads(about_path.read_bytes())
for item in about.get("items", []):
    footer = item.get("footerText")
    if isinstance(footer, str):
        footer = footer.replace("Version 1.0.1", "Version 1.0.3")
        footer = footer.replace("Version 1.0.2", "Version 1.0.3")
        item["footerText"] = footer
about_path.write_bytes(plistlib.dumps(about, fmt=plistlib.FMT_XML, sort_keys=False))

print("Patched RuntimeV023.xm with direct Apple clock UILabel updates and NextLock 1.0.3 metadata")
