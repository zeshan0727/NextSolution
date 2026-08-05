#!/usr/bin/env python3
from enum import IntEnum

class State(IntEnum):
    UNKNOWN = 0
    UNPLUGGED = 1
    CHARGING = 2
    FULL = 3

def is_charging(state: State) -> bool:
    return state in (State.CHARGING, State.FULL)

def is_full(level: float, state: State) -> bool:
    return level >= 0.995 and is_charging(state)

def should_notify(enabled: bool, initialized: bool, was_full: bool, now_full: bool) -> bool:
    return enabled and initialized and not was_full and now_full

assert not is_full(1.0, State.UNPLUGGED)
assert not is_full(0.994, State.CHARGING)
assert is_full(0.995, State.CHARGING)
assert is_full(1.0, State.FULL)
assert should_notify(True, True, False, True)
assert not should_notify(False, True, False, True)
assert not should_notify(True, False, False, True)
assert not should_notify(True, True, True, True)
assert not should_notify(True, True, False, False)
print('Full Charge Haptic runtime logic: PASS')
