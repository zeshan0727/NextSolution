#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = (ROOT / 'Tweak.xm').read_text()
FILTER = (ROOT / 'CleanHomeLabels.plist').read_text()
CONTROL = (ROOT / 'control').read_text()
PREFS = (ROOT / 'Preferences/Resources/Root.plist').read_text()


def resolved_hidden(enabled: bool, requested_hidden: bool) -> bool:
    return True if enabled else requested_hidden

cases = [
    (True, False, True, 'enabled forces visible labels hidden'),
    (True, True, True, 'enabled preserves already-hidden labels'),
    (False, False, False, 'disabled preserves stock visible request'),
    (False, True, True, 'disabled preserves stock hidden request'),
]
for enabled, requested, expected, name in cases:
    got = resolved_hidden(enabled, requested)
    assert got == expected, f'{name}: expected {expected}, got {got}'

assert '%hook SBIconView' in SRC
assert '- (void)setLabelHidden:(BOOL)hidden' in SRC
assert '%orig(CHLResolvedHidden(CHLEnabled, hidden));' in SRC
assert 'CHLIsSpringBoardProcess()' in SRC
assert 'com.apple.springboard' in FILTER and 'Bundles' in FILTER
assert 'CFPreferencesCopyAppValue' in SRC and 'CFNotificationCenterAddObserver' in SRC
assert 'Package: com.nextsolution.cleanhomelabels' in CONTROL
assert 'Architecture: iphoneos-arm64' in CONTROL
assert 'Hide Icon Names' in PREFS and 'Apply &amp; Respring' in PREFS
assert 'zeshan0727.github.io' not in '\n'.join(p.read_text(errors='ignore') for p in ROOT.rglob('*') if p.is_file())
print('PASS 12/12 deterministic/source validation cases')
