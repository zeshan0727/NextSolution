# Low Battery Haptic Alert 1.0.0

## Feature
Plays one warning haptic when the unplugged battery percentage crosses a user-selected threshold. It does not display notifications, read private data, change charging behavior, or alter battery management.

## Native-feature verification
Apple documents battery percentage display, Low Power Mode, and system low-battery behavior, but iOS 15 and iOS 16 do not provide a user setting for a custom tactile alert at a selected battery percentage. This tweak adds only that missing accessibility/convenience behavior. Repository history and the live `Packages` catalogue were checked; no published Next Jailbreak package implements a custom battery-threshold haptic.

## Compatibility
- iOS 15 and later
- Primary target: iPhone 14 Pro Max on iOS 16.0 with RootHide
- RootHide: `iphoneos-arm64e`
- Standard rootless: `iphoneos-arm64`
- Injects only into SpringBoard

## Working references inspected
- Next Home Lock 1.0.4/1.0.5: architecture declarations, RootHide/rootless build split, `-segalign,4000`, SpringBoard-only filter, PreferenceLoader bundle layout, CFPreferences, Darwin preference reload, and post-install process restart.
- Low Power Mode Haptic 1.0.0: documented `NSProcessInfo` notification lifecycle, initialization-before-observation ordering, deterministic decision separation, minimal settings pane, and successful dual-package publishing workflow.
- NextAura and PhoneAura release entries and compiled package metadata: architecture naming, dependency metadata, `nextjailbreak.com` homepage/depiction paths, and separate RootHide/rootless publication conventions. Their proprietary implementation was not copied.

## Apple runtime reference
The implementation uses public UIKit battery monitoring. `UIDevice.batteryMonitoringEnabled` is enabled before reading the level or registering observers. `UIDeviceBatteryLevelDidChangeNotification` is the activation callback; `UIDeviceBatteryStateDidChangeNotification` updates baseline state without generating an alert.

## Runtime decision path
1. SpringBoard starts and reads CFPreferences.
2. Battery monitoring is enabled.
3. The current battery percentage is stored as the baseline, preventing an install/respring haptic.
4. On a battery-level notification, the pure decision function receives enabled state, previous percentage, current percentage, battery state, and threshold.
5. It accepts only a downward crossing from above the threshold to at-or-below it while unplugged.
6. Disabled, initial, charging, full, unknown-level, duplicate-below-threshold, and non-crossing cases are rejected.
7. An accepted decision plays one `UINotificationFeedbackTypeWarning` haptic.

## Deterministic checks
`tests/test_decision.c` covers successful activation and rejection for disabled state, first sample, charging, full, invalid level, repeated below-threshold updates, non-crossing updates, and threshold clamping. The release workflow compiles and executes this test before building packages.

## Settings
- Enable Alert
- Battery Threshold: 5% to 50%, default 15%

No diagnostics, test buttons, runtime class names, process IDs, or debug rows are exposed in the release pane.

## Installation
Add `https://nextjailbreak.com/` to Sileo, refresh sources, install the package matching the jailbreak architecture, and respring. Do not install both variants.

## Uninstall behavior
Removing the package and respringing removes the SpringBoard observer and Settings pane. It does not modify saved user data or system battery settings.

## Physical-device checklist
1. Confirm Settings shows Low Battery Haptic Alert with the enable switch and threshold slider.
2. Set the threshold one percentage point below the current charge.
3. Keep the phone unplugged and let it cross the threshold.
4. Confirm exactly one warning haptic occurs.
5. Confirm subsequent percentage changes below the threshold do not repeat the haptic.
6. Charge across the threshold and confirm no warning haptic occurs.
7. Disable the tweak, repeat a downward crossing, and confirm no haptic.
8. Confirm SpringBoard remains stable and ordinary battery alerts still work.

## Known limitations and runtime assumptions
- Apple states battery-level notifications are posted no more frequently than once per minute, so the haptic can arrive shortly after the displayed percentage changes.
- Runtime behavior is build-validated only until tested on the matching physical device.
- The haptic depends on system haptics/vibration being enabled and available.

## Market comparison and attribution
The current Havoc/rootless market and public tweak lists were reviewed for small haptic and battery utilities. Products such as broad system-haptic suites and unrelated flashlight gesture tweaks were used only to understand market categories. No paid assets, branding, descriptions, or proprietary code were copied. The runtime uses Apple public APIs and original decision logic; there are no upstream licence obligations beyond the repository's own licence.
