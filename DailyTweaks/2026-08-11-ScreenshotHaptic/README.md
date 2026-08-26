# Screenshot Haptic 1.0.0

## Feature
Screenshot Haptic plays one success haptic after iOS confirms that a screenshot was taken. It does not capture, inspect, copy, upload, modify, block, hide, or delete screenshot content.

## Native-feature verification
Target iOS is 15 and later, primarily iOS 16.0. Apple documents `UIApplicationUserDidTakeScreenshotNotification` as a notification posted after a screenshot is taken. Apple Support documents that on iOS 18 and earlier a screenshot produces the normal screenshot flow with a temporary thumbnail; the documented iOS screenshot settings do not provide a dedicated screenshot-haptic option. Repository history and the current `Packages` catalogue were reviewed before implementation and no Next Jailbreak package provides this feature.

Apple references reviewed:
- https://developer.apple.com/documentation/uikit/uiapplication/userdidtakescreenshotnotification
- https://support.apple.com/en-ie/102616

## Working internal references inspected
- Next Aura / `com.nextsolution.unlockvibrate`: package identity and proven CFPreferences/Darwin notification conventions were checked against the current repository catalogue/history.
- PhoneAura: repository references were reviewed for publication and preference conventions.
- Next Home Lock 1.0.4/1.0.5: `DailyTweaks/2026-07-30-NextHomeLock` was the primary physically verified RootHide reference for SpringBoard targeting, `arm64 arm64e`, `0x4000` segment alignment, PreferenceLoader, CFPreferences, Darwin notifications and post-install restarts.
- Wi-Fi Drop Haptic 1.0.0: `DailyTweaks/2026-08-10-WiFiDropHaptic` was used as the most recent successful dual-package structure and publisher reference.

The tweak does not add a gesture recognizer to an assumed private view and does not depend on a private lifecycle class. It listens to Apple's documented UIKit screenshot notification.

## Market comparison
Havoc was reviewed for current iOS 15/16 rootless screenshot-related products. `ScreenshotActions` adds quick actions to screenshot previews and `Unseen` controls screenshots/recordings; they are materially different from this single-purpose post-capture haptic. Havoc's broader haptic/system products were also reviewed for market context. No proprietary code, assets, descriptions, branding or paid behavior were copied.

## Upstream/open-source review and licence obligations
Searches for reputable open-source screenshot tweaks were performed. No third-party code is incorporated. The implementation is original and uses Apple UIKit/Foundation APIs, so this release has no new third-party source-code attribution or licence obligation.

## Compatibility
- iOS 15.0+
- Primary physical target: iPhone 14 Pro Max on iOS 16.0
- Rootless package: `iphoneos-arm64`
- RootHide package: `iphoneos-arm64e`
- Injection target: SpringBoard only

## Runtime design
At SpringBoard startup the tweak loads the `enabled` preference through CFPreferences, registers a retained observer for `UIApplicationUserDidTakeScreenshotNotification`, and registers a Darwin preferences-change callback. The screenshot observer calls the decision gate only after UIKit posts the documented post-capture notification. If enabled, feedback is dispatched on the main queue using `UINotificationFeedbackGenerator` success feedback.

Critical runtime assumptions:
- SpringBoard receives `UIApplicationUserDidTakeScreenshotNotification` on iOS 15/16 when a screenshot is taken system-wide.
- UIKit haptic feedback generation remains available in SpringBoard on the target device.
These assumptions are build-validated but must not be called physically verified until tested on the matching device.

## Settings
Settings > Screenshot Haptic contains one user-facing control:
- Enable Screenshot Haptic

Preferences use CFPreferences and a Darwin notification. No physical plist path, diagnostics, runtime class names, process IDs, hook status or test buttons are exposed.

## Deterministic checks
`tests/test_runtime_logic.py` exercises successful activation plus disabled/no-event rejection cases and validates source invariants for process targeting, observer retention, callback selection, decision ordering, CFPreferences/Darwin usage and absence of an unverified private-view gesture lifecycle.

## Installation
Add `https://nextjailbreak.com/` to Sileo, refresh sources, install the package matching the jailbreak environment, and allow the package post-install action to restart Preferences and SpringBoard.

## Physical-device test checklist
This release remains labelled build-validated and awaiting device test until completed on the matching device.
1. Install the RootHide build on iOS 16.0 and confirm SpringBoard returns normally.
2. Open Settings > Screenshot Haptic and confirm only the enable switch is shown.
3. With the tweak enabled, take one screenshot with Side + Volume Up and confirm exactly one success haptic after capture.
4. Take several separate screenshots and confirm one haptic per screenshot, with no spontaneous feedback between captures.
5. Disable the tweak in Settings and take another screenshot; confirm no added haptic occurs.
6. Re-enable it and confirm a later screenshot again produces one haptic.

## Uninstall behavior
Removing the package removes the tweak dylib, filter, preference bundle and PreferenceLoader entry. It does not remove screenshots or modify Photos, screenshot settings, button behavior or user data.

## Known limitations
- The tweak responds after UIKit reports a completed screenshot event; it does not signal the exact hardware-button press instant.
- Physical runtime behavior is not claimed verified until tested on the target device.
