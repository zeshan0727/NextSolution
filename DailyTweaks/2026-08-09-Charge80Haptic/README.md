# Charge 80 Haptic 1.0.0

## Feature
Charge 80 Haptic plays one success haptic when battery level crosses from below 80% to 80% or higher while the iPhone is connected to power. It does not stop charging or change Apple's battery-management behavior.

## Native-feature verification
Apple's current iPhone guide documents adjustable Charge Limit (including 80%) for iPhone 15 and later. The primary target for this tweak is iPhone 14 Pro Max on iOS 16.0, which does not have that newer Charge Limit control. Optimized Battery Charging is different and does not provide this one-shot 80% haptic. Apple documents `UIDeviceBatteryLevelDidChangeNotification` and `UIDeviceBatteryStateDidChangeNotification`; battery monitoring must be enabled before those callbacks and readings are available.

## Compatibility
- iOS 15 and later
- Primary device target: iPhone 14 Pro Max, iOS 16.0, RootHide
- RootHide: `iphoneos-arm64e`
- Standard rootless: `iphoneos-arm64`

## Working references inspected
The implementation follows structural patterns already proven in this repository: Next Home Lock 1.0.4/1.0.5 for conservative SpringBoard targeting, arm64/arm64e and 0x4000 segment alignment; Next Aura (`com.nextsolution.unlockvibrate`) and PhoneAura package/history references for RootHide-compatible packaging conventions; and the successful Thermal Warning Haptic / Headphone Disconnect Haptic release workflows for CFPreferences, Darwin reloads, PreferenceLoader layout, dual builds, package validation and synchronized Sileo indexing. No hard-coded RootHide preference path is used.

## Upstream/open-source review
Apple UIKit documentation is the runtime API authority. RootHide's public Developer documentation was reviewed for package-scheme/path guidance (MIT-licensed project). Open-source battery-related jailbreak projects, including DevelopCubeLab/BatteryInfo (Apache-2.0), were reviewed only for ecosystem comparison; no source code was copied. Havoc battery/utility listings were reviewed for market comparison only; no paid code, assets, wording or branding were copied.

## Settings
Settings > Charge 80 Haptic contains one user-facing control: **Enable 80% Alert**.

## Runtime logic
SpringBoard enables UIKit battery monitoring, snapshots the initial percentage before registering observers, then listens to Apple's battery-level and battery-state notifications. A haptic is allowed only when the previous valid percentage is below 80, the current percentage is at least 80, the device is charging/full, the tweak is enabled, and an initial state already exists. This prevents startup, unplugged and duplicate alerts.

## Deterministic checks
`tests/test_runtime_logic.py` covers successful 79→80/81 transitions, charging/full states, startup suppression, disabled rejection, unplugged rejection, duplicate-edge rejection, already-above rejection, below-threshold rejection and unknown-reading rejection. CI also checks ordering (initial battery snapshot before observer registration), observer retention, process filtering, symbols, package paths, preference resources and architecture metadata.

## Installation
Add or refresh `https://nextjailbreak.com/` in Sileo and install the package matching the jailbreak environment. Respring after installation if the package manager does not do so automatically.

## Uninstall
Remove Charge 80 Haptic from the package manager and respring. The tweak stores only its enable preference and does not alter system battery policy.

## Physical-device test checklist
1. Open Settings and confirm only the enable switch is shown.
2. With battery below 80%, connect power and charge through 80%; confirm exactly one success haptic.
3. Leave the phone connected above 80%; confirm no repeated haptic.
4. Disable the tweak, drop below 80% in a later cycle, charge through 80%, and confirm no haptic.
5. Re-enable and confirm the next genuine below-80→80 charging crossing alerts once.
6. Confirm SpringBoard and Settings remain stable after respring.

## Known limitation / unverified runtime assumption
CI cannot force a real iPhone battery through an actual charging boundary. Runtime behavior remains awaiting physical-device confirmation. UIKit states battery-level notifications are rate-limited, so the callback may arrive at 80% or a slightly higher displayed percentage; the crossing logic intentionally accepts `>= 80`.
