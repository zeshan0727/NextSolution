#!/usr/bin/env python3
import unittest

UNKNOWN, UNPLUGGED, CHARGING, FULL = range(4)


def is_powered(state: int) -> bool:
    return state in (CHARGING, FULL)


def should_notify(enabled: bool, initialized: bool, previous: int, current: int) -> bool:
    return enabled and initialized and is_powered(previous) and current == UNPLUGGED


class ChargingInterruptedLogicTests(unittest.TestCase):
    def test_charging_to_unplugged_activates(self):
        self.assertTrue(should_notify(True, True, CHARGING, UNPLUGGED))

    def test_full_to_unplugged_activates(self):
        self.assertTrue(should_notify(True, True, FULL, UNPLUGGED))

    def test_initial_state_is_suppressed(self):
        self.assertFalse(should_notify(True, False, CHARGING, UNPLUGGED))

    def test_disabled_is_rejected(self):
        self.assertFalse(should_notify(False, True, CHARGING, UNPLUGGED))

    def test_duplicate_unplugged_is_rejected(self):
        self.assertFalse(should_notify(True, True, UNPLUGGED, UNPLUGGED))

    def test_unplugged_to_charging_is_rejected(self):
        self.assertFalse(should_notify(True, True, UNPLUGGED, CHARGING))

    def test_charging_to_full_is_rejected(self):
        self.assertFalse(should_notify(True, True, CHARGING, FULL))

    def test_unknown_previous_is_rejected(self):
        self.assertFalse(should_notify(True, True, UNKNOWN, UNPLUGGED))


if __name__ == "__main__":
    unittest.main()
