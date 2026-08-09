#!/usr/bin/env python3
THRESHOLD = 80
UNKNOWN, UNPLUGGED, CHARGING, FULL = 0, 1, 2, 3

def powered(state):
    return state in (CHARGING, FULL)

def should_notify(enabled, has_previous, previous, current, state):
    return (enabled and has_previous and powered(state) and previous >= 0
            and previous < THRESHOLD and current >= THRESHOLD)

def check(name, expected, *args):
    actual = should_notify(*args)
    assert actual is expected, f"{name}: expected {expected}, got {actual}"

cases = [
    ("79 to 80 charging", True, True, True, 79, 80, CHARGING),
    ("79 to 81 charging", True, True, True, 79, 81, CHARGING),
    ("79 to 80 full", True, True, True, 79, 80, FULL),
    ("startup suppressed", False, True, False, 79, 80, CHARGING),
    ("disabled", False, False, True, 79, 80, CHARGING),
    ("unplugged rejected", False, True, True, 79, 80, UNPLUGGED),
    ("duplicate edge rejected", False, True, True, 80, 80, CHARGING),
    ("already above rejected", False, True, True, 82, 83, CHARGING),
    ("below threshold rejected", False, True, True, 78, 79, CHARGING),
    ("unknown previous rejected", False, True, True, -1, 80, CHARGING),
]
for name, expected, *args in cases:
    check(name, expected, *args)
print(f"Charge 80 Haptic deterministic runtime logic: PASS ({len(cases)} cases)")
