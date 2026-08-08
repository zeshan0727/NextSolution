#!/usr/bin/env python3

NOMINAL = 0
FAIR = 1
SERIOUS = 2
CRITICAL = 3


def is_hot(state):
    return state in (SERIOUS, CRITICAL)


def should_notify(enabled, has_previous, previous, current):
    return enabled and has_previous and (not is_hot(previous)) and is_hot(current)


def run():
    cases = [
        ("startup serious suppressed", True, False, NOMINAL, SERIOUS, False),
        ("fair to serious alerts", True, True, FAIR, SERIOUS, True),
        ("nominal to critical alerts", True, True, NOMINAL, CRITICAL, True),
        ("serious to critical no duplicate", True, True, SERIOUS, CRITICAL, False),
        ("critical to fair no alert", True, True, CRITICAL, FAIR, False),
        ("disabled rejects", False, True, FAIR, SERIOUS, False),
        ("unchanged fair rejects", True, True, FAIR, FAIR, False),
        ("recovered then hot alerts again", True, True, FAIR, SERIOUS, True),
    ]
    for name, enabled, has_previous, previous, current, expected in cases:
        actual = should_notify(enabled, has_previous, previous, current)
        assert actual == expected, f"{name}: expected {expected}, got {actual}"
    print(f"PASS: {len(cases)} deterministic Thermal Warning Haptic cases")


if __name__ == "__main__":
    run()
