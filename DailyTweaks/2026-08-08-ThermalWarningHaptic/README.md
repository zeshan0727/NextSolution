# Thermal Warning Haptic 1.0.0

Thermal Warning Haptic is one focused convenience/safety tweak: it plays one warning haptic when iOS newly enters a **serious** or **critical** thermal state. It does not change thermal limits, charging behavior, performance management, or any security policy.

## Native-feature verification

Checked before implementation on 2026-08-08:

- Apple documents `NSProcessInfoThermalStateDidChangeNotification` as the supported notification for system thermal-state changes, and specifically requires reading `thermalState` before registering for it.
- Apple defines the states nominal, fair, serious and critical; critical means heat is significantly impacting performance and the device needs to cool down.
- Stock iOS can slow/stop charging and can eventually show a temperature warning screen at extreme thresholds, but Apple does not document a user-selectable haptic warning when the thermal state first becomes serious/critical.
- `zeshan0727/NextSolution` package/index and recent daily-tweak history were checked. No published Thermal Warning Haptic package or equivalent one-feature project was present. NextAura includes thermal battery-color features, but not this dedicated one-shot thermal transition haptic.

Therefore the feature is not a duplicate of the stock iOS 15/16 behavior or an existing NextSolution daily tweak.

## Compatibility

- iOS 15 and later
- Primary target: iOS 16.0
- RootHide: `iphoneos-arm64e`
- Standard rootless: `iphoneos-arm64`
- SpringBoard only

## Runtime design

The tweak deliberately avoids private SpringBoard lifecycle classes. In SpringBoard it:

1. loads the `enabled` preference with CFPreferences;
2. reads `NSProcessInfo.processInfo.thermalState` **before** registering the observer, matching Apple's documented requirement;
3. registers and retains an observer for `NSProcessInfoThermalStateDidChangeNotification`;
4. records the last state and only accepts a transition from nominal/fair into serious/critical;
5. produces `UINotificationFeedbackTypeWarning` on the main queue;
6. rejects startup state, disabled state, unchanged states, recovery transitions and serious-to-critical duplicates.

No private filesystem preference path is used, so no RootHide path translation is required.

## Working references inspected

Repository history and current package/source structure were reviewed before implementation:

- **Next Aura (`com.nextsolution.unlockvibrate`)**: current RootHide/rootless package metadata and installed-layout expectations in `Packages`; historical Next Home Lock commits explicitly carrying the NextAura-style CFPreferences approach.
- **PhoneAura (`com.zeshan.phoneaura`)**: current dual-architecture package metadata, dependencies, live `nextjailbreak.com` depiction/homepage conventions, and publication-history branches/commits.
- **Next Home Lock 1.0.4/1.0.5**: proven SpringBoard process restriction, `arm64 arm64e`, RootHide scheme, `-segalign,4000`, aggregate PreferenceLoader subproject, CFPreferences + Darwin notification pattern, simple release pane, and post-install Preferences/SpringBoard restart.
- **Headphone Disconnect Haptic 1.0.0**: most recent successful dual-build workflow, package validation, diagnostic compiler artifacts, synchronized index publication, relative `./debfiles/` filenames, retry-on-main-race logic and cleanup pattern.

The current repository, recent commits, package index, published tutorial history and previous daily-tweak attempts were checked to avoid repeating battery/charging/headphone/screen-recording/brightness concepts.

## Upstream/open-source review and licensing

- Apple Foundation documentation supplied the public thermal notification/state contract; no Apple code was copied.
- The RootHide Developer documentation (MIT-licensed repository) was reviewed for RootHide packaging/path guidance. This tweak does not access jailbreak filesystem paths, so no `jbroot()` translation is needed.
- Public Theos/open-source tweak examples were reviewed for general packaging conventions. No third-party implementation of this thermal-haptic feature was copied, so there is no incorporated upstream source requiring code attribution.

## Havoc market comparison

The current Havoc catalogue was reviewed for iOS 15–16/rootless utility patterns, including system-wide haptic utilities and temperature/battery-related tweaks. Examples reviewed included Buzz Buzz Lite (broad system haptics, older iOS), Ampere (battery-indicator styling), SmartNotifications, Rune and other rootless system utilities. Thermal Warning Haptic is intentionally narrower: a single serious/critical thermal transition haptic. No Havoc source, assets, branding or descriptions were copied.

## Settings

Settings → **Thermal Warning Haptic** → **Enable Thermal Alert**.

There are no diagnostic rows, test buttons, runtime class names or debug controls in the release pane.

## Installation

Add `https://nextjailbreak.com/` to Sileo, refresh sources, install the RootHide or rootless package matching the jailbreak, then respring if the package manager does not do so automatically.

## Uninstall behavior

Uninstalling removes the tweak dylib, process filter, PreferenceLoader entry and preference bundle through normal package removal. The tweak makes no permanent system setting changes and does not modify thermal policies.

## Deterministic checks

`tests/test_runtime_logic.py` covers eight decisions:

- startup at serious is suppressed;
- fair → serious alerts;
- nominal → critical alerts;
- serious → critical does not duplicate;
- critical → fair does not alert;
- disabled state rejects;
- unchanged fair rejects;
- after recovery, a new entry into serious alerts again.

The release workflow additionally validates ordering (read `thermalState` before observer registration), retained observer storage, process targeting, package architectures/dependencies, segment alignment, PreferenceLoader resources, binary symbols and index metadata.

## Physical-device test checklist

Build validation is not runtime verification. On an iOS 16.0 RootHide device, verify:

1. the Settings pane opens and contains only the enable switch;
2. disabling the switch suppresses haptics;
3. when the system genuinely transitions from nominal/fair to serious/critical, exactly one warning haptic occurs;
4. remaining serious and then moving to critical does not produce a duplicate;
5. after returning to nominal/fair, a later serious/critical transition can alert again;
6. SpringBoard remains stable through resprings and preference changes.

## Known limitation / runtime assumption

The build can deterministically validate the decision function and source ordering, but it cannot force a real iPhone into Apple thermal states. The release must therefore be labelled **build-validated and awaiting physical-device test** until a matching device confirms delivery of the documented Foundation notification inside SpringBoard.
