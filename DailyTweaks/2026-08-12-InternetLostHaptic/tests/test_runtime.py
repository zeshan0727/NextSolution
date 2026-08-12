#!/usr/bin/env python3
SATISFIED='satisfied'
UNSATISFIED='unsatisfied'
REQUIRES='requiresConnection'
INVALID='invalid'

def should_alert(enabled, initialized, previous, current):
    return enabled and initialized and previous == SATISFIED and current == UNSATISFIED

cases = [
    ('startup satisfied', True, False, INVALID, SATISFIED, False),
    ('startup unsatisfied', True, False, INVALID, UNSATISFIED, False),
    ('internet lost', True, True, SATISFIED, UNSATISFIED, True),
    ('path remains usable', True, True, SATISFIED, SATISFIED, False),
    ('wifi to cellular remains usable', True, True, SATISFIED, SATISFIED, False),
    ('requires connection is not hard loss', True, True, SATISFIED, REQUIRES, False),
    ('requires to unsatisfied', True, True, REQUIRES, UNSATISFIED, False),
    ('recovery', True, True, UNSATISFIED, SATISFIED, False),
    ('duplicate loss', True, True, UNSATISFIED, UNSATISFIED, False),
    ('disabled loss', False, True, SATISFIED, UNSATISFIED, False),
]
for name, enabled, initialized, previous, current, expected in cases:
    actual = should_alert(enabled, initialized, previous, current)
    assert actual == expected, f'{name}: expected {expected}, got {actual}'
print(f'PASS {len(cases)}/{len(cases)} deterministic runtime cases')
