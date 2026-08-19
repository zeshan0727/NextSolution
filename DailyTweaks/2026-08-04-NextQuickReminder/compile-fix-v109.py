#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).with_name('SystemApertureReminderV109.xm')
text = path.read_text()
old = 'result = [(NSDictionary *)value copy];'
new = 'result = [(__bridge NSDictionary *)value copy];'
if old not in text:
    if new in text:
        print('Next Quick Reminder 1.0.9 bridge cast already fixed.')
        raise SystemExit(0)
    raise SystemExit('Expected v1.0.9 CF bridge anchor not found')
path.write_text(text.replace(old, new, 1))
print('Applied Next Quick Reminder 1.0.9 ARC bridge compiler fix.')
