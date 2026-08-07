#!/usr/bin/env python3
"""Deterministic checks for Headphone Disconnect Haptic runtime decisions."""

OLD_DEVICE_UNAVAILABLE = 2
NEW_DEVICE_AVAILABLE = 1
CATEGORY_CHANGE = 3


def should_notify(enabled: bool, reason: int, previous_personal: bool, current_personal: bool) -> bool:
    return enabled and reason == OLD_DEVICE_UNAVAILABLE and previous_personal and not current_personal


def run():
    cases = [
        ("wired unplug", True, OLD_DEVICE_UNAVAILABLE, True, False, True),
        ("bluetooth disconnect", True, OLD_DEVICE_UNAVAILABLE, True, False, True),
        ("disabled", False, OLD_DEVICE_UNAVAILABLE, True, False, False),
        ("new device", True, NEW_DEVICE_AVAILABLE, False, True, False),
        ("category change", True, CATEGORY_CHANGE, True, False, False),
        ("speaker route removed", True, OLD_DEVICE_UNAVAILABLE, False, False, False),
        ("switch personal route", True, OLD_DEVICE_UNAVAILABLE, True, True, False),
        ("no personal audio", True, OLD_DEVICE_UNAVAILABLE, False, True, False),
    ]
    for name, enabled, reason, previous_personal, current_personal, expected in cases:
        actual = should_notify(enabled, reason, previous_personal, current_personal)
        assert actual == expected, f"{name}: expected {expected}, got {actual}"
    print(f"Headphone Disconnect Haptic deterministic runtime checks passed: {len(cases)} cases")


if __name__ == "__main__":
    run()
