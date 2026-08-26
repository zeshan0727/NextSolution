# Internet Lost Haptic 1.0.0

Internet Lost Haptic is a focused iOS jailbreak tweak that plays one warning haptic when the system network path changes from usable (`nw_path_status_satisfied`) to unavailable (`nw_path_status_unsatisfied`). It does not alert for an ordinary Wi-Fi-to-cellular handoff because the path remains satisfied, and it does not modify network routing, radios, VPNs, credentials, traffic, or security policy.

## Native-feature verification

Apple's Network framework documents a path monitor and distinct satisfied, unsatisfied, and satisfiable/requires-connection states. On the iOS 15-16 target, Apple exposes connectivity state and system network UI, but the documented stock system does not provide a user-configurable haptic dedicated to the exact usable-path -> unavailable-path transition. Repository/package/history review found no existing Next Jailbreak package implementing this exact alert. Wi-Fi Drop Haptic is intentionally different: it alerts when the active path leaves Wi-Fi even if cellular remains usable; this tweak alerts only on a hard satisfied -> unsatisfied transition.

## Compatibility

- iOS 15.0 and later; primary target iOS 16.0.
- RootHide package target: `iphoneos-arm64e`.
- Standard rootless package target: `iphoneos-arm64`.
- Injects only into SpringBoard.

## Implementation

The runtime follows the proven Next Jailbreak structure used by Next Aura (`com.nextsolution.unlockvibrate`), PhoneAura, physically verified Next Home Lock 1.0.4/1.0.5, and recent successful dual-package daily releases. In particular: conservative SpringBoard targeting, arm64/arm64e build settings, 0x4000 segment alignment, PreferenceLoader, CFPreferences, Darwin preference notifications, and safe post-install SpringBoard/Preferences restart behavior. The network callback structure reuses the already-published Wi-Fi Drop Haptic's Network-framework monitor pattern while changing the critical decision rule to exact path status transitions.

The monitor is retained for SpringBoard lifetime, runs on a dedicated serial dispatch queue, and dispatches UIKit haptic generation to the main queue. No private runtime class or selector is required.

## Critical runtime rule

Alert only when all are true:

1. tweak is enabled;
2. an initial path state has already been observed;
3. previous status is `nw_path_status_satisfied`; and
4. current status is `nw_path_status_unsatisfied`.

The state is updated even while disabled, preventing a stale alert after re-enabling.

## Deterministic checks

`tests/test_runtime.py` covers 10 cases: initial satisfied, initial unsatisfied, successful internet-loss transition, unchanged usable path, Wi-Fi-to-cellular usable handoff, satisfied-to-requires-connection, requires-connection-to-unsatisfied, recovery, duplicate loss, and disabled loss. The build workflow also checks process filtering, symbols, dependency metadata, preference bundle loading, architecture, package layout, and version agreement.

## Settings

Settings -> Internet Lost Haptic contains one user-facing control: **Enable Internet Lost Alert**. There are no diagnostics, class names, hook status rows, process IDs, or test controls in the release pane.

## Installation

Add or refresh `https://nextjailbreak.com/` in Sileo, install only the package variant matching the jailbreak, then respring. RootHide users must use the RootHide package and standard rootless users must use the rootless package. Do not install both variants.

## Uninstall

Remove Internet Lost Haptic in Sileo and respring. It stores only its enable preference and does not alter network configuration or user data.

## Physical-device test checklist

1. Confirm the Settings pane opens and contains only the enable switch.
2. With Wi-Fi and cellular available, switch from Wi-Fi to cellular; confirm there is no added haptic.
3. Restore a usable path, then disable Wi-Fi and cellular/enter Airplane Mode so the path becomes unavailable; confirm exactly one warning haptic.
4. Stay offline; confirm the haptic does not repeat.
5. Reconnect; confirm recovery itself does not haptic.
6. Lose connectivity again; confirm one new warning haptic.
7. Disable the tweak, repeat a genuine loss transition, and confirm no added haptic.
8. Confirm SpringBoard and Settings remain stable throughout.

## Known limitations / runtime assumptions

`NWPath` describes whether the process has a usable network path; it is not an end-to-end probe of every website or service. A captive portal, upstream outage, DNS/application problem, or remote server failure can exist while the system path remains satisfied, so this tweak intentionally will not claim to detect every possible Internet outage. A real iOS 16.0 RootHide device is still required to confirm Network-framework callback delivery and UIKit haptic behavior inside SpringBoard. Build/logic validation must not be described as physical runtime verification.

## Market and upstream review

Havoc's SmartNetwork iOS 15-16 and current rootless/network-related catalogue entries were reviewed for market context only. This tweak does not reproduce SmartNetwork feature-for-feature and uses no Havoc product code, paid assets, descriptions, or branding. Apple's public Network framework documentation is the API reference. No paid/proprietary source was copied. If an open-source implementation is later incorporated, its licence and attribution must be recorded here before release.

## Safety

The tweak does not inspect packets, URLs, messages, credentials, contacts, photos, banking/payment information, or private user content. It does not change routing, cellular/Wi-Fi policy, VPN state, security settings, or DRM.
