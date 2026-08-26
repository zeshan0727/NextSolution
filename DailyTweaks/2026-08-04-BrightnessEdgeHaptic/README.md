# Brightness Edge Haptic

## Feature
Plays a warning haptic when display brightness newly reaches minimum and a success haptic when it newly reaches maximum.

## Native-feature verification
Apple documents `UIScreenBrightnessDidChangeNotification` as a brightness-change callback, but stock iOS 15 and iOS 16 do not provide distinct haptic confirmation when the brightness slider reaches its minimum or maximum edge. Repository history and current package metadata were reviewed to confirm this feature is not already published in NextSolution.

## Compatibility
- iOS 15 and later
- Primary target: iPhone 14 Pro Max, iOS 16.0, RootHide
- RootHide: iphoneos-arm64e
- Rootless: iphoneos-arm64

## Working references inspected
The project follows the repository patterns used by Next Home Lock 1.0.4/1.0.5 and recent working daily tweaks: SpringBoard-only filtering, arm64/arm64e builds, 0x4000 segment alignment, PreferenceLoader layout, CFPreferences, Darwin preference notifications and post-install respring. NextAura and PhoneAura package layouts and metadata were also reviewed where source was available; compiled packages were not treated as source code.

## Runtime design
The tweak observes Apple's documented `UIScreenBrightnessDidChangeNotification` in SpringBoard. It retains the observer token, initializes state without producing a false haptic, classifies brightness into minimum/middle/maximum, and only responds to a transition into an edge. It does not attach gesture recognizers or rely on a private view lifecycle.

## Deterministic checks
`Tests/test_brightness_decision.c` covers minimum, middle and maximum classification; successful minimum/maximum activation; disabled rejection; duplicate-state rejection; initial-state suppression; and leaving-edge rejection.

## Settings
One Enable/Disable switch under Settings > Brightness Edge Haptic.

## Installation
Add `https://nextjailbreak.com/` to Sileo, refresh sources and install the package matching RootHide or standard rootless.

## Uninstall
Remove the package and respring. No user content is collected or retained.

## Device test checklist
1. Confirm the Settings pane opens and the switch persists.
2. Move brightness from the middle to minimum and confirm one warning haptic.
3. Keep the slider at minimum and confirm no repeated haptic.
4. Move to the middle, then maximum, and confirm one success haptic.
5. Disable the tweak and repeat both edge transitions; no haptic should play.
6. Respring while brightness is already at an edge; no false startup haptic should play.

## Known limitations and unverified assumptions
Build validation cannot prove that SpringBoard receives the documented brightness notification on the user's exact iOS 16.0 RootHide environment. Physical-device confirmation is required before the tutorial branch may be merged.

## Market comparison and attribution
The current Havoc catalogue and iOS 16 compatibility lists were reviewed for general convenience and haptic feature patterns. No paid/proprietary source, branding, assets or descriptions were copied. Runtime implementation uses Apple public UIKit notification behavior and original decision logic; no third-party code is included.
