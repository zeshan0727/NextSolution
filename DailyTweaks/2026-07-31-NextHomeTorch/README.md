# Next Home Torch 1.0.0

Next Home Torch toggles the iPhone flashlight with a single two-finger tap on an empty Home Screen area. It is intentionally limited to SpringBoard and includes one user-facing Enable switch.

## Compatibility

- iOS 15 and later
- Primary device target: iPhone 14 Pro Max on iOS 16.0
- RootHide package: `iphoneos-arm64e`
- Standard rootless package: `iphoneos-arm64`

## Native-feature verification

Apple documents the Lock Screen and Control Center flashlight controls, but iOS 15/16 does not provide a system setting that maps a two-finger tap on empty Home Screen space to the flashlight. Apple also documents app-controlled Home indicator behavior separately; this tweak does not alter system security or replace an existing accessibility gesture. Repository searches performed before implementation found no existing Next Solution tweak using this two-finger Home Screen trigger.

References checked on 31 July 2026:

- Apple iPhone User Guide and Apple Support flashlight/control documentation.
- Current Havoc rootless/iOS 15–16 catalogue for comparable convenience gestures.
- Existing Next Solution source and package history.

## Working references inspected

- Next Home Lock 1.0.4/1.0.5: proven `SBIconListView -touchesEnded:withEvent:` lifecycle, SpringBoard-only filtering, RootHide-safe CFPreferences and Darwin notification reload.
- NextAura: package architecture, PreferenceLoader layout, RootHide build and segment alignment patterns.
- PhoneAura: preference bundle and release metadata patterns.

## Runtime design

`SBIconListView` receives the Home Screen background touch callback. The tweak accepts only exactly two ended touches, each with `tapCount == 1`. It then resolves `SBUIFlashlightController` dynamically and requires both `level` and `setLevel:` before changing anything. If the class or selectors are unavailable, it calls the original implementation and fails safely.

## Deterministic checks

The release workflow verifies:

- SpringBoard-only filter and process guard.
- Exact two-touch acceptance condition.
- Rejection of one-touch, three-touch, repeated-tap and non-ended input in a small simulation.
- Selector availability checks occur before `objc_msgSend`.
- `%orig` remains on all rejected or unsupported paths.
- RootHide/rootless architectures, package paths, PreferenceLoader bundle, one-switch Settings pane and package checksums.

## Settings

Settings → Next Home Torch → **Enable Next Home Torch**.

## Installation and test

1. Install the build matching the jailbreak environment.
2. Respring when prompted.
3. Open the Home Screen and place two fingers simultaneously on empty wallpaper space.
4. Lift both fingers once; the flashlight should toggle.
5. Repeat to turn it off.
6. Disable the tweak in Settings and confirm the same gesture no longer toggles the flashlight.

## Known limitations and awaiting device test

The build is validated but the `SBUIFlashlightController` selector set must still be confirmed on the user’s physical iPhone 14 Pro Max running iOS 16.0 RootHide. Some themes or Home Screen layout tweaks may consume multi-touch before `SBIconListView` receives it. Runtime behavior must not be called verified until the physical test succeeds.

## Uninstall

Remove the package in Sileo and respring. The tweak stores only the local enabled preference.

## Attribution and licence

Original Next Solution implementation. No paid or proprietary source or assets were copied. Released under the MIT licence included in this folder.
