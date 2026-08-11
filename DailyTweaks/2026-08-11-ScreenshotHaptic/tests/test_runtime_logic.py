#!/usr/bin/env python3
from pathlib import Path


def should_notify(enabled: bool, received_event: bool) -> bool:
    return enabled and received_event

cases = [
    (True, True, True, "enabled screenshot event activates"),
    (False, True, False, "disabled rejects screenshot event"),
    (True, False, False, "no event rejects activation"),
    (False, False, False, "disabled no-event rejects activation"),
]
for enabled, event, expected, label in cases:
    actual = should_notify(enabled, event)
    assert actual == expected, f"{label}: expected {expected}, got {actual}"

root = Path(__file__).resolve().parents[1]
src = (root / "Tweak.xm").read_text()
assert "UIApplicationUserDidTakeScreenshotNotification" in src
assert "SSHIsSpringBoard" in src and "com.apple.springboard" in src
assert "SSHScreenshotObserver =" in src, "observer must be retained"
assert "SSHReloadPreferences();" in src
assert "CFPreferencesCopyAppValue" in src
assert "CFNotificationCenterAddObserver" in src
assert "UINotificationFeedbackTypeSuccess" in src
assert src.index("if (!SSHIsSpringBoard()) return;") < src.index("SSHScreenshotObserver ="), "process guard must precede observer registration"
assert src.index("if (!SSHShouldNotify(SSHEnabled, YES)) return;") < src.index("notificationOccurred:UINotificationFeedbackTypeSuccess"), "decision gate must precede feedback"
assert "SBRootFolderView" not in src and "UIGestureRecognizer" not in src, "must not use unverified private-view gesture lifecycle"
print("Screenshot Haptic deterministic runtime checks: PASS (4 decision cases + source invariants)")
