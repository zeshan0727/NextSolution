# Full Charge Haptic

Full Charge Haptic plays one success haptic when the iPhone first reaches a full charge while it is connected to power.

## Native-feature verification

Target: iOS 15 and later, primarily iOS 16.0. Stock iOS shows charging state and battery percentage but does not provide a user-configurable full-charge haptic. Apple documents `UIDeviceBatteryLevelDidChangeNotification`, `UIDeviceBatteryStateDidChangeNotification`, and `batteryMonitoringEnabled`; this tweak uses those public UIKit callbacks rather than an assumed private class lifecycle.

Apple references:
- https://developer.apple.com/documentation/uikit/uidevice/batteryleveldidchangenotification
- https://developer.apple.com/documentation/uikit/uidevice/batterystatedidchangenotification
- https://developer.apple.com/documentation/uikit/uidevice/isbatterymonitoringenabled

Repository history was checked for existing battery, charging, full-charge, low-power, brightness-edge, and haptic packages. No published tweak in NextSolution provides this exact full-charge-only haptic.

## Working references inspected

- Next Home Lock 1.0.5: SpringBoard-only filtering, architecture targets, `-segalign 4000`, package layout, CFPreferences, Darwin notification reload, and post-install restart pattern.
- Brightness Edge Haptic: public UIKit notification observer, retained observer objects, initial-state suppression, PreferenceLoader layout, deterministic decision tests, and dual RootHide/rootless workflow structure.
- NextAura and PhoneAura package metadata/layout in the repository were reviewed as compatibility references; no proprietary implementation was copied.

## Market comparison

The current Havoc catalogue was reviewed for rootless iOS 15–16 utility and battery patterns, including system-monitor and notification products. Full Charge Haptic is intentionally smaller and does not copy paid code, assets, branding, descriptions, or feature sets.

## Runtime design

SpringBoard enables `UIDevice.batteryMonitoringEnabled`, retains observers for battery-level and battery-state notifications, and evaluates one deterministic transition:

- Accept only when enabled, initialized, previously not full, now at least 99.5%, and battery state is charging or full.
- Reject initial-load state to prevent a false haptic after respring.
- Reject unplugged 100%, duplicate full notifications, disabled state, unknown battery values, and non-full changes.

The 99.5% threshold accommodates UIKit float rounding while still representing the displayed 100% boundary.

## Compatibility

- iOS 15+
- Primary target: iPhone 14 Pro Max, iOS 16.0, RootHide
- RootHide: `iphoneos-arm64e`
- Standard rootless: `iphoneos-arm64`

## Settings

Settings → Full Charge Haptic:
- Enable Full Charge Haptic

No diagnostics or test controls are exposed in the release pane.

## Installation

Add `https://nextjailbreak.com/` to Sileo, refresh sources, install the package matching the jailbreak environment, and respring.

## Uninstall

Remove the package in Sileo and respring. The tweak stores only the `enabled` preference and does not modify user data.

## Deterministic checks

`tests/test_runtime_logic.py` covers:
- Full while charging
- Full battery state
- Below-threshold rejection
- Unplugged rejection
- Disabled rejection
- Initial-load suppression
- Duplicate-full rejection
- Non-full rejection

## Physical-device test checklist

1. Confirm the Settings pane loads and the switch persists.
2. Install while below full charge and connect power.
3. Allow the battery to reach displayed 100%; confirm one success haptic.
4. Leave connected at 100%; confirm no repeated haptics.
5. Disable the tweak, drop below full, recharge to 100%, and confirm no haptic.
6. Respring while already at 100%; confirm no immediate false haptic.

## Known limitations and runtime assumptions

Build validation cannot prove that SpringBoard on every iOS build continues receiving UIKit battery notifications for the full charging session. Runtime behaviour remains awaiting physical testing on the matching iOS 16.0 RootHide device.

## Attribution and licence

Original implementation by Next Jailbreak. It uses Apple-documented UIKit APIs and repository-owned structural patterns. No paid or proprietary tweak source or assets were copied. Repository licence terms apply.
