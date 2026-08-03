def should_play(enabled, initialized, previous, current):
    return enabled and initialized and previous != current

assert should_play(True, True, False, True)
assert should_play(True, True, True, False)
assert not should_play(False, True, False, True)
assert not should_play(True, False, False, True)
assert not should_play(True, True, True, True)
assert not should_play(True, True, False, False)
print('capture decision tests passed')
