# Headphone Disconnect Haptic 1.0.0

A small Next Jailbreak tweak for iOS 15+ that plays one warning haptic when a wired or Bluetooth personal-audio route is actually removed and audio falls back away from headphones.

## Single feature

When iOS posts `AVAudioSessionRouteChangeNotification` with `AVAudioSessionRouteChangeReasonOldDeviceUnavailable`, the tweak checks the previous and current audio routes. It vibrates only when the previous route contained wired headphones or Bluetooth headphone audio and the current route no longer contains a personal-audio output. Switching from one headphone route to another is deliberately rejected.

## Native-feature verification

This was checked before implementation.

- Apple documents audio-route changes and specifically identifies `AVAudioSessionRouteChangeReasonOldDeviceUnavailable` for a removed route. Apple also documents that media apps should normally pause when headphones disconnect: https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes
- Apple Support documents that when a Bluetooth audio accessory goes out of range, playback destination returns to the iPhone: https://support.apple.com/guide/iphone/play-audio-iphone-a-bluetooth-accessory-iph01b6ea9a3/ios
- Apple's iPhone headphone-notification documentation covers hearing-exposure warnings, not a disconnect haptic. No stock iOS 15/16 setting or Apple-documented system behavior was found that provides a warning haptic specifically when a headphone route disappears.
- `zeshan0727/NextJailbreak` was searched for `AVAudioSessionRouteChangeNotification`, headphone-disconnect implementations, package names and recent daily tweaks. No existing published or source tweak in this repository provides this feature.

Therefore this is not intended to duplicate a documented stock iOS 15/16 feature.

## Working internal references inspected

Primary reference: `DailyTweaks/2026-07-30-NextHomeLock` version 1.0.5, physically verified on the target iOS 16.0 RootHide device. The implementation reuses its conservative structural patterns: SpringBoard-only filter, `ARCHS = arm64 arm64e`, RootHide-default Theos scheme, `-Wl,-segalign,4000`, PreferenceLoader bundle layout, CFPreferences storage, Darwin preference reload, and post-install Preferences/SpringBoard restart.

NextAura (`com.nextsolution.unlockvibrate`) and PhoneAura (`com.zeshan.phoneaura`) were also inspected through the current repository package index, existing release/tutorial history and available branches. Their compiled packages and proven RootHide layout confirm the repository conventions used here. Their complete current source trees are not present on `main`, so no unavailable or proprietary implementation was assumed or copied.

## External references and attribution

- Apple AVFAudio route-change documentation and the public `AVAudioSessionRouteChangeNotification` API are the runtime reference.
- The Theos SDK `AVAudioSession.h` header was reviewed to confirm the public route-change keys and reason constants.
- Havoc market comparison reviewed current rootless/system-audio patterns including Listening, SmartNetwork iOS 15-16 and Hikari. None was copied. Headphone Disconnect Haptic is a deliberately narrow route-removal warning rather than an audio-control suite, network manager or sound-effects customizer.
- No paid/proprietary source or assets are used.
- No third-party source code is included, so there are no upstream code-license obligations beyond the normal platform/toolchain licenses.

## Compatibility

- iOS 15.0 and later
- Primary target: iPhone 14 Pro Max, iOS 16.0, RootHide
- RootHide package: `iphoneos-arm64e`
- Standard rootless package: `iphoneos-arm64`
- Requires MobileSubstrate-compatible injection and PreferenceLoader

## Settings

Settings → Headphone Disconnect Haptic contains one release control only:

- **Enable Disconnect Alert** — on by default.

No diagnostic rows, test buttons, process IDs, hook names or runtime implementation details are exposed in the release pane.

## Runtime design

The tweak injects only into SpringBoard. It uses the documented `AVAudioSessionRouteChangeNotification` instead of attaching a gesture recognizer or hooking an assumed private view/class lifecycle. The notification observer is retained for SpringBoard's process lifetime. It observes with `object:nil` because Apple does not guarantee a specific notification object; this avoids silently filtering out a valid hardware route-change notification.

A warning haptic requires all of these conditions:

1. the tweak is enabled;
2. the route-change reason is `OldDeviceUnavailable`;
3. the previous route contained wired headphones, Bluetooth A2DP, Bluetooth HFP or Bluetooth LE audio;
4. the current route no longer contains one of those personal-audio outputs.

Events for a newly connected device, category changes, speaker-only route changes, disabled state and direct switching from one personal-audio route to another are rejected.

## Deterministic checks

`tests/test_runtime_logic.py` exercises successful activation and rejection cases, including wired unplug, Bluetooth disconnect, disabled state, new-device events, category changes, non-headphone route removal, and switching between personal-audio routes.

The release workflow also checks:

- source ordering and retained observer assignment;
- `object:nil` notification registration regression check;
- documented route-change reason and previous-route keys;
- process filter is SpringBoard only;
- RootHide/rootless architecture and package metadata;
- `0x4000` segment alignment;
- expected dylib strings/symbol references;
- PreferenceLoader entry and preference bundle paths;
- exactly one user-facing switch and no diagnostics in Settings;
- package checksums and relative `./debfiles/` Sileo paths.

## Runtime assumptions and limitation

Compilation and deterministic logic do not prove hardware behavior. The remaining device-test assumption is that SpringBoard's `AVAudioSession` receives the documented hardware route-change notification on the target iOS 16.0 RootHide environment. The release must be described as **build-validated and awaiting physical-device test** until the user confirms the haptic on real wired/Bluetooth disconnects.

The warning is intentionally haptic-only. It does not pause media, alter Bluetooth state, change routes, read audio content, or collect device information.

## Installation

Add `https://nextjailbreak.com/` to Sileo, refresh sources, search for **Headphone Disconnect Haptic**, and install the package variant matching the jailbreak. Do not install both variants. Respring after installation and open Settings → Headphone Disconnect Haptic.

## Physical-device test checklist

1. Confirm version 1.0.0 appears in Sileo and the Settings pane loads.
2. With the tweak enabled, connect wired headphones (where supported) or Bluetooth headphones/AirPods.
3. Disconnect the active headphone route and confirm exactly one warning haptic.
4. Reconnect and confirm connection itself does not trigger the warning.
5. If possible, switch from one headphone output to another and confirm no false disconnect warning while a personal-audio output remains active.
6. Disable the tweak in Settings and repeat a disconnect; confirm there is no tweak haptic.
7. Confirm SpringBoard remains stable and normal audio routing continues unchanged.

## Uninstall and recovery

The tweak stores only its enable preference. Removing the package removes the injected dylib, PreferenceLoader entry and settings bundle; no user media or system audio configuration is modified. If SpringBoard enters Safe Mode during testing, open Sileo and remove Headphone Disconnect Haptic, then respring. Keep Sileo accessible during the first device test.
