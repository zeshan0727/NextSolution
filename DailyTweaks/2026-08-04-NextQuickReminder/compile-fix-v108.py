#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).with_name("SystemApertureReminder.xm")
text = path.read_text()
old = "dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS, ^{"
new = "dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, ^{"
if old not in text:
    if new in text:
        print("Next Quick Reminder 1.0.8 dispatch flag already fixed.")
        raise SystemExit(0)
    raise SystemExit("Expected System Aperture dispatch flag anchor not found")
path.write_text(text.replace(old, new, 1))
print("Applied Next Quick Reminder 1.0.8 System Aperture compiler fix.")
