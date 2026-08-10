#!/usr/bin/env python3
from pathlib import Path


def should_notify(enabled, has_previous, previous_wifi, current_wifi):
    return enabled and has_previous and previous_wifi and not current_wifi

cases = [
    (True, True, True, False, True, "wifi-to-cellular-or-off alerts"),
    (True, True, True, True, False, "wifi remains wifi"),
    (True, True, False, False, False, "repeated non-wifi is rejected"),
    (True, True, False, True, False, "joining wifi is rejected"),
    (False, True, True, False, False, "disabled is rejected"),
    (True, False, True, False, False, "startup is suppressed"),
    (False, False, False, False, False, "disabled startup is suppressed"),
    (True, False, False, True, False, "initial wifi sample is suppressed"),
]

for enabled, has_previous, previous_wifi, current_wifi, expected, label in cases:
    actual = should_notify(enabled, has_previous, previous_wifi, current_wifi)
    assert actual == expected, f"{label}: expected {expected}, got {actual}"

source = (Path(__file__).resolve().parents[1] / "Tweak.xm").read_text()
required = [
    'enabled && hasPreviousState && previousWiFi && !currentWiFi',
    'nw_path_get_status(path) == nw_path_status_satisfied',
    'nw_path_uses_interface_type(path, nw_interface_type_wifi)',
    'WDHPreviousWiFi = currentWiFi;',
    'WDHHasPreviousState = YES;',
    'UINotificationFeedbackTypeWarning',
    'nw_path_monitor_set_update_handler',
    'nw_path_monitor_set_queue',
    'nw_path_monitor_start',
]
for marker in required:
    assert marker in source, f"missing runtime marker: {marker}"

handler = source[source.index('static void WDHHandlePath'):source.index('static void WDHPreferencesChangedCallback')]
assert handler.index('BOOL shouldNotify') < handler.index('WDHPreviousWiFi = currentWiFi;')
assert handler.index('WDHPreviousWiFi = currentWiFi;') < handler.index('if (!shouldNotify) return;')

ctor = source[source.index('%ctor'):]
assert ctor.index('WDHReloadPreferences();') < ctor.index('WDHMonitor = nw_path_monitor_create();')
assert ctor.index('nw_path_monitor_set_update_handler') < ctor.index('nw_path_monitor_start(WDHMonitor);')

print(f"Wi-Fi Drop Haptic deterministic runtime checks: PASS ({len(cases)} cases)")
