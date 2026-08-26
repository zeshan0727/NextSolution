# Low Power Mode Haptic 1.0.0

## Feature
Plays a success haptic when Low Power Mode turns on and a warning haptic when it turns off.

## Native-feature verification
Apple documents the Low Power Mode state and `NSProcessInfoPowerStateDidChangeNotification`, but stock iOS 15 and iOS 16 do not provide a dedicated haptic confirmation when the user changes Low Power Mode. Repository history and the published `Packages` index were searched for low-power-mode haptic packages and no existing Next Jailbreak tweak implementing this feature was found.

## Compatibility
- iOS 15 and later
- Primary target: iPhone 14 Pro Max on iOS 16.0 with RootHide
- RootHide: `iphoneos-arm64e`
- Standard rootless: `iphoneos-arm64`

## Implementation
The tweak injects only into SpringBoard. It observes Apple's documented `NSProcessInfoPowerStateDidChangeNotification`, reads `lowPowerModeEnabled`, compares it with the previously recorded state, and plays one haptic only for a genuine state transition. Initial loading, duplicate notifications, disabled preferences, and unchanged state are rejected.

## Working references inspected
- Next Home Lock 1.0.5: architecture settings, SpringBoard-only filter, segment alignment, PreferenceLoader layout, CFPreferences, Darwin notification reload, post-install respring and successful release workflow.
- NextAura and PhoneAura package entries: RootHide/rootless architecture naming, dependencies, package paths and repository metadata. Their full current source was not available in the repository, so no unavailable implementation was claimed or copied.
- Existing Next Jailbreak package index and recent failed Home Screen Flashlight releases were reviewed to avoid repeating private-class lifecycle and missing-Settings-entry mistakes.

## Settings
Settings → Low Power Mode Haptic → Enable Low Power Mode Haptic.

## Installation
Add `https://nextjailbreak.com/` to Sileo, refresh sources, install the package matching the jailbreak architecture, and respring. Do not install both variants.

## Uninstall behavior
Removing the package and respringing restores stock behavior. The tweak does not modify saved user data or system configuration.

## Runtime decision path
1. SpringBoard loads the tweak.
2. The current Low Power Mode value is stored without playing feedback.
3. Apple posts `NSProcessInfoPowerStateDidChangeNotification`.
4. The current state is compared with the previous state.
5. Disabled, initial, duplicate and unchanged cases are rejected.
6. Off → on plays success feedback; on → off plays warning feedback.

## Deterministic checks
`tests/test_decision.c` covers initialization rejection, disabled rejection, duplicate rejection, successful enable activation and successful disable activation. The release workflow compiles and runs this test before either package is built.

## Physical-device test checklist
1. Install the RootHide package and respring.
2. Confirm the Settings pane and enable switch appear.
3. Open Control Center and turn Low Power Mode on; confirm one success haptic.
4. Turn it off; confirm one warning haptic.
5. Repeat each transition and confirm there is only one haptic per state change.
6. Disable the tweak in Settings and confirm both transitions become silent.
7. Re-enable it and confirm feedback returns without a reboot.

## Known limitations and runtime assumptions
Build validation cannot prove that SpringBoard on every device receives the documented notification while injected. The release is build-validated and must be treated as awaiting physical-device confirmation until tested on the target iOS 16.0 RootHide device.

## Upstream attribution and licensing
No third-party source code is copied. Apple documentation was used to select the public notification and state property. UIKit's standard feedback generator is used directly.

## Havoc market comparison
The current Havoc catalogue was reviewed for iOS 15–16 convenience and haptic patterns. No paid assets, descriptions, branding or proprietary implementation were copied. This tweak intentionally provides only one narrowly scoped feature.
