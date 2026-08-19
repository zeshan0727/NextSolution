#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parent
path = root / "Tweak.xm"
text = path.read_text()
text = text.replace('#import <CoreMotion/CoreMotion.h>\n', '#import <CoreMotion/CoreMotion.h>\n#import <math.h>\n', 1)
text = text.replace('[NSDate date].descriptionWithLocale', '[NSDate date].description')
text = text.replace('[attributes fileSize] > 512 * 1024', '[attributes[NSFileSize] unsignedLongLongValue] > 512 * 1024')
text = text.replace(
    '@interface NQRQuickPanelController : UIViewController <UITextViewDelegate>\n',
    '@interface NQRQuickPanelController : UIViewController <UITextViewDelegate>\n- (instancetype)initWithTrigger:(NSString *)trigger;\n',
    1,
)
path.write_text(text)

# 1.0.10 Settings test preview: start compact so compact geometry can be tuned
# live, then let a normal tap expand it for expanded-geometry tuning. Older
# versions do not contain this block, so this is a safe no-op for their builds.
aperture = root / 'SystemApertureReminderV109.xm'
if aperture.exists():
    source = aperture.read_text()
    old = '''        NQR109PresentReminder(sample);\n        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{\n            if ([NQR109IslandView isKindOfClass:NQR109ApertureCard.class]) {\n                [(NQR109ApertureCard *)NQR109IslandView setExpanded:YES animated:YES];\n            }\n        });'''
    new = '''        // Compact-first Settings preview. Tap to expand; long-press toggles states.\n        NQR109PresentReminder(sample);'''
    if old in source:
        aperture.write_text(source.replace(old, new, 1))
        print('Applied compact-first 1.0.10 Dynamic Island test preview.')

print('Prepared Next Quick Reminder tweak source for compilation.')
