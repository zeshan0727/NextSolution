#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).with_name('SystemApertureReminderV109.xm')
text = path.read_text()
old = '''        NQR109PresentReminder(sample);\n        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{\n            if ([NQR109IslandView isKindOfClass:NQR109ApertureCard.class]) {\n                [(NQR109ApertureCard *)NQR109IslandView setExpanded:YES animated:YES];\n            }\n        });'''
new = '''        // Start the Settings preview in compact state so Compact Width/Height/Position\n        // can be tuned immediately. Tap the preview to expand it and then tune the\n        // Expanded controls; long-press toggles between compact and expanded.\n        NQR109PresentReminder(sample);'''
if old not in text:
    if new in text:
        print('Next Quick Reminder 1.0.10 compact-first test preview already applied.')
        raise SystemExit(0)
    raise SystemExit('Expected v1.0.10 test auto-expand block not found')
path.write_text(text.replace(old, new, 1))
print('Applied Next Quick Reminder 1.0.10 compact-first live test preview.')
