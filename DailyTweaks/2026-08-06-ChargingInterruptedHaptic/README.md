# Charging Interrupted Haptic

Charging Interrupted Haptic is a focused iOS jailbreak tweak that plays one warning haptic when the device transitions from a powered battery state (charging or full) to unplugged.

## Native-feature verification

Stock iOS 15 and iOS 16 expose battery state and charging information but do not provide a dedicated user-configurable warning haptic when an active charging connection is interrupted. Apple documents `UIDeviceBatteryStateDidChangeNotification` and requires `batteryMonitoringEnabled = YES` before battery-state notifications are posted. The repository catalogue and recent daily tweaks were searched before implementation; no existing Next Jailbreak package provides this exact charging-interruption alert.

## Compatibility

- iOS 15 and later
- Primary target: iPhone 14 Pro Max on iOS 16.0 with RootHide
- RootHide: `iphoneos-arm64e`
- Standard rootless: `iphoneos-arm64`

## Working internal references inspected

- Next Home Lock 1.0.4/1.0.5: SpringBoard-only filter, RootHide/rootless packaging, segment alignment, PreferenceLoader layout and post-install respring pattern.
- Full Charge Haptic: retained UIKit battery observer, initial-state suppression and documented battery monitoring.
- Next Aura package layout and release metadata.
- PhoneAura rootless/RootHide package architecture and repository-index patterns.

The implementation deliberately uses Apple's native battery-state notification rather than an assumed private view, gesture recognizer or unverified private-class lifecycle.

## Market comparison

The current Havoc catalogue and iOS 15–16 tweak lists were reviewed for battery, safety and haptic products. Broad products such as SmartBattery and Rose cover larger feature sets; this project is intentionally a free, original, single-purpose charging-interruption warning and does not copy proprietary source, assets, branding or descriptions.

## Settings

Settings → Charging Interrupted Haptic:

- Enable Charging Alert

No developer diagnostics or test controls are exposed in the release pane.

## Runtime decision path

1. Inject only into SpringBoard.
2. Enable UIKit battery monitoring.
3. Retain an observer for `UIDeviceBatteryStateDidChangeNotification`.
4. Record the first valid state without alerting.
5. Alert only for `charging/full → unplugged` while enabled.
6. Update the previous state before delivering feedback, preventing duplicate alerts.
7. Ignore unknown states, startup state, disabled state and all non-disconnect transitions.

## Deterministic checks

`tests/test_runtime_logic.py` exercises:

- charging → unplugged activation
- full → unplugged activation
- initial-load suppression
- disabled-state rejection
- duplicate-unplugged rejection
- unplugged → charging rejection
- charging → full rejection
- unknown-state rejection

The release workflow also validates source ordering, retained observer storage, SpringBoard targeting, selector/constants presence, preference loading, architecture, package paths, metadata and segment alignment.

## Installation

Add `https://nextjailbreak.com/` to Sileo, refresh sources, locate Charging Interrupted Haptic and install the package matching the jailbreak environment. The package resprings SpringBoard after installation.

## Uninstall behavior

Removing the package removes the tweak dylib, filter and preference bundle. Existing preference values may remain harmlessly in CFPreferences until manually cleared. No background daemon, launch daemon or user data is created.

## Device test checklist

1. Install the RootHide build on iOS 16.0 and confirm the Settings pane loads.
2. Leave the tweak enabled.
3. Connect power and wait until the battery state shows charging.
4. Disconnect power and confirm one warning haptic.
5. Leave the device unplugged and confirm no repeated haptic.
6. Reconnect power; confirm no alert on connection.
7. Disable the tweak, disconnect power again and confirm no haptic.
8. Respring while unplugged and confirm no startup false positive.

## Known limitations and unverified assumptions

- UIKit reports logical battery-state changes; accessory or power-source behavior that does not change `UIDeviceBatteryState` cannot trigger the tweak.
- Runtime behavior is build-validated but remains awaiting testing on the user's physical iOS 16.0 RootHide device.
- Haptic intensity is determined by iOS and device hardware.

## Upstream attribution and licensing

No paid or proprietary tweak code is used. The runtime is original and relies on documented UIKit APIs. Internal repository structures were reused from the user's own Next Jailbreak projects. External catalogues were used only for market comparison. This project should retain the repository's existing licensing terms and this attribution section if redistributed.
