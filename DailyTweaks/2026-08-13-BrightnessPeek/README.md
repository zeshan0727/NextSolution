# Brightness Peek 1.0.0

Brightness Peek adds one focused convenience feature: whenever display brightness changes, SpringBoard briefly shows the exact brightness percentage in a small, non-interactive top overlay. It adds no haptics and does not modify automatic brightness, Reduce White Point, display calibration, or charging behavior.

## Native-feature verification
Apple documents `UIScreenBrightnessDidChangeNotification` for brightness changes and documents brightness adjustment through Control Center and Settings. The stock iOS 15/16 brightness UI uses a slider and does not provide a documented always-visible exact percentage toast during normal brightness changes. Repository history was also checked before implementation. `BrightnessEdgeHaptic` already exists, but it only generates edge feedback at minimum/maximum brightness; Brightness Peek instead gives exact numeric visual feedback across the full range and has no haptic behavior.

## Compatibility
- iOS 15 and later; primary target iOS 16.0.
- RootHide build: `iphoneos-arm64e`.
- Standard rootless build: `iphoneos-arm64`.
- SpringBoard only.

## Settings
The release pane contains one real control: **Enable Brightness Peek**. It uses CFPreferences and a Darwin notification for live reload, following the proven Next Jailbreak preference pattern. No diagnostic rows, process IDs, hook status, or test buttons are exposed.

## Runtime design
The critical path uses UIKit's brightness-change notification rather than attaching a gesture recognizer to a private view. On a notification, the tweak reads `UIScreen.mainScreen.brightness`, clamps it to 0...1, converts it to a rounded percentage, and displays a retained pass-through overlay. A generation counter prevents an older delayed fade from hiding a newer update during rapid slider movement. The overlay disables interaction so it cannot block SpringBoard touches.

## Working references inspected
- Next Aura (`com.nextsolution.unlockvibrate`) repository history and release structure.
- PhoneAura branches and publication history.
- Physically verified Next Home Lock 1.0.4/1.0.5: dual architectures, `0x4000` segment alignment, SpringBoard process filtering, CFPreferences/Darwin reload, conservative selector/lifecycle handling, and RootHide packaging discipline.
- Clean Home Labels 1.0.0: current successful dual-build and package-index publication gates.

No code from those projects is copied as a feature implementation; only proven repository/package structure is reused.

## Market comparison and upstream attribution
Havoc products including AdvancedBrightnessSlider and VolumePercent were reviewed only for feature-market comparison. AdvancedBrightnessSlider changes brightness-control behavior and Reduce White Point; VolumePercent displays volume percentage. Brightness Peek does neither. No Havoc code, paid assets, descriptions, branding, or proprietary implementation were copied.

The feature implementation is original glue around Apple UIKit APIs. No third-party source code is embedded, so there are no additional third-party licence obligations for the tweak source.

## Installation
Refresh `https://nextjailbreak.com/` in Sileo, install the package matching the jailbreak environment, and respring if requested by the package manager. Uninstalling removes the injected tweak and preference bundle; it does not modify stock brightness settings.

## Deterministic checks
`tests/test_decision.c` checks clamping/rounding at below-zero, zero, rounding boundaries, a normal midrange value, near-maximum, maximum and above-maximum values, plus enabled/disabled event acceptance. CI separately checks source ordering, SpringBoard targeting, preference loading, required symbols, architectures, package metadata and installed paths.

## Device test checklist
1. Install the RootHide build on iOS 16.0 and verify Settings shows only Enable Brightness Peek.
2. Change brightness in Control Center and confirm an exact percentage overlay appears without blocking touches.
3. Change brightness in Settings > Display & Brightness and confirm the same behavior.
4. Move the slider rapidly and confirm the latest value remains visible briefly without a stuck overlay.
5. Disable the tweak in Settings and confirm subsequent changes show no Brightness Peek overlay; re-enable and confirm it returns.
6. Lock/unlock and repeat; confirm SpringBoard remains stable and does not enter safe mode.

## Known limitations / unverified runtime assumptions
Compilation and deterministic tests cannot prove SpringBoard's real-device UIKit window/scene presentation. The build is therefore described as build-validated and awaiting physical-device testing until confirmed on a matching device. Brightness changes driven by automatic brightness may also generate the documented notification, so a toast may appear when iOS changes brightness automatically.
