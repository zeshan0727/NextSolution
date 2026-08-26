# Wi-Fi Drop Haptic 1.0.0

## Feature
Wi-Fi Drop Haptic plays one warning haptic when the active iOS network path transitions from Wi-Fi to a non-Wi-Fi path. It does not change Wi-Fi settings, cellular settings, routing, credentials, VPNs, or network security.

## Native-feature verification
Target iOS is 15 and later, primarily iOS 16.0. Apple documents NWPathMonitor as the API for observing network-path changes and NWPath as the API for determining whether a path uses Wi-Fi. Stock iOS 16 shows network state in system UI but does not provide a dedicated haptic alert specifically for loss of the active Wi-Fi path. Repository history and current Packages were reviewed before implementation; no existing Next Jailbreak package provides this same feature.

Apple references reviewed:
- https://developer.apple.com/documentation/network/nwpathmonitor
- https://developer.apple.com/documentation/network/nwpath

## Working internal references inspected
- Next Aura / com.nextsolution.unlockvibrate: package identity and proven CFPreferences/Darwin preference patterns referenced through the current NextSolution package catalogue and release notes.
- PhoneAura: current NextSolution package/tutorial/catalogue references were inspected for naming, publication and website conventions.
- Next Home Lock 1.0.4/1.0.5: `DailyTweaks/2026-07-30-NextHomeLock` was used as the primary physically verified RootHide structural reference for SpringBoard targeting, `arm64 arm64e`, `0x4000` segment alignment, PreferenceLoader structure, CFPreferences, Darwin notifications and post-install process restart behavior.
- Charge 80 Haptic 1.0.0: `DailyTweaks/2026-08-09-Charge80Haptic` and its successful dual-package publication workflow were used as the most recent build/index reference.

No private SpringBoard lifecycle class is required by this tweak. The runtime relies on Apple's public Network framework callback rather than adding a recognizer to an assumed private view.

## Market comparison
Havoc's SmartNetwork iOS 15-16 listing was reviewed only as market context for the usefulness of network-state customization. SmartNetwork is a much broader paid product. No proprietary source, assets, text, branding, settings, or feature implementation were copied. Wi-Fi Drop Haptic is intentionally limited to one original convenience behavior.

## Upstream/open-source review and licence obligations
A web/GitHub search was performed for reputable open-source jailbreak implementations using the same Wi-Fi path-loss behavior. No source was copied into this project. The implementation uses Apple Network/UIKit APIs and original Next Jailbreak code, so there is no third-party source-code licence obligation for this release.

## Compatibility
- iOS 15.0+
- Primary physical target: iOS 16.0
- Rootless package: `iphoneos-arm64`
- RootHide package: `iphoneos-arm64e`
- Injection target: SpringBoard only

## Runtime design
A retained `nw_path_monitor_t` starts once in SpringBoard. Each callback classifies the current usable path as Wi-Fi only when the path is satisfied and `nw_path_uses_interface_type(..., nw_interface_type_wifi)` is true. The first callback initializes state without feedback. Later callbacks produce a warning haptic only for `previousWiFi == YES && currentWiFi == NO` while the tweak is enabled.

Critical assumptions:
- SpringBoard may use the public Network framework and receive path-monitor updates on iOS 15/16.
- A path switching away from Wi-Fi can represent Wi-Fi being disabled, disconnected, losing usable routing, or iOS preferring another interface. The tweak intentionally alerts on the active path leaving Wi-Fi rather than claiming to identify the exact radio-level reason.

## Settings
Settings > Wi-Fi Drop Haptic contains one user-facing control:
- Enable Wi-Fi Drop Alert

Preferences use CFPreferences with a Darwin notification. No physical preference plist path, diagnostic row, test button, runtime class name, PID, or hook status is exposed.

## Deterministic checks
`tests/test_runtime_logic.py` exercises:
1. Wi-Fi -> non-Wi-Fi activation.
2. Wi-Fi -> Wi-Fi rejection.
3. Repeated non-Wi-Fi rejection.
4. Non-Wi-Fi -> Wi-Fi rejection.
5. Disabled-state rejection.
6. Startup suppression.
7. Disabled startup suppression.
8. Initial Wi-Fi sample suppression.

The test also verifies decision ordering, state mutation ordering, monitor retention/startup markers and the expected warning-feedback route.

## Installation
Add `https://nextjailbreak.com/` to Sileo, refresh sources, install the package matching the jailbreak environment, then allow the package post-install action to restart Preferences and SpringBoard.

## Physical-device test checklist
This release must be labelled build-validated and awaiting device test until tested on a matching device.
1. Install the RootHide build on iOS 16.0 and confirm SpringBoard returns normally.
2. Open Settings > Wi-Fi Drop Haptic and confirm only the enable switch is shown.
3. Begin connected to a working Wi-Fi network and wait a few seconds for initial path state.
4. Turn Wi-Fi off or move out of range until iOS leaves the active Wi-Fi path; confirm exactly one warning haptic.
5. Stay on cellular/non-Wi-Fi and confirm no repeated haptic occurs for subsequent path updates.
6. Rejoin Wi-Fi; confirm joining Wi-Fi itself does not haptic.
7. Leave Wi-Fi again; confirm one new warning haptic.
8. Disable the tweak in Settings and repeat; confirm no haptic occurs.

## Uninstall behavior
Removing the package removes the tweak dylib, filter, preference bundle and PreferenceLoader entry. It does not modify saved Wi-Fi networks, credentials, routing, system networking configuration or user data.

## Known limitations
- The feature reports active network-path departure from Wi-Fi, not a low-level 802.11 disassociation reason.
- VPN or unusual multipath/network configurations may produce path changes that differ from the visible Wi-Fi icon.
- Physical runtime behavior is not claimed verified until tested on the target device.
