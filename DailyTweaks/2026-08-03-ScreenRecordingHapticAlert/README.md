# Screen Recording Haptic Alert

Plays one haptic when screen capture starts and a different haptic when it stops. Capture includes screen recording, mirroring and AirPlay cloning.

## Native-feature verification
Apple documents `UIScreenCapturedDidChangeNotification` as the system callback for changes to screen capture state. Stock iOS 15 and iOS 16 show visual recording indicators but do not provide distinct start/stop haptic feedback. Repository history and package indexes were searched before implementation; no existing NextSolution package provides this single feature.

## Compatibility
- iOS 15 and later
- Primary target: iPhone 14 Pro Max, iOS 16.0, RootHide
- Builds: RootHide arm64e and standard rootless arm64

## Implementation
- Injects only into SpringBoard.
- Uses Apple's UIKit `UIScreenCapturedDidChangeNotification`; no assumed private view lifecycle.
- Reads `UIScreen.isCaptured` on the main queue.
- Establishes an initial baseline without playing a haptic.
- Plays system haptic 1520 when capture starts and 1521 when capture stops.
- Uses CFPreferences and a Darwin notification for the enable switch.
- Retains the notification observer for the SpringBoard lifetime.

## Settings
One user-facing option: **Enable Haptic Alert**.

## Deterministic checks
`tests/test_decision.py` covers capture start, capture stop, disabled rejection, initial-load rejection, and duplicate-state rejection.

## Installation and uninstall
Add `https://nextjailbreak.com/` to Sileo, install the matching package and respring. Uninstalling removes the tweak and Settings bundle; no user data is collected.

## Device test checklist
1. Confirm the Settings pane appears.
2. Start Control Center screen recording and confirm one haptic.
3. Stop recording and confirm a different haptic.
4. Confirm no repeated haptic while state is unchanged.
5. Disable the tweak and repeat; no haptic should play.
6. Re-enable without respring and repeat.

## Known limitations and runtime assumptions
Build validation cannot prove SpringBoard receives the UIKit notification on the user's exact device. The release must be treated as build-validated and awaiting physical-device test.

## Working references inspected
- Next Home Lock 1.0.4/1.0.5 structure, SpringBoard filter, Makefiles, segment alignment, PreferenceLoader packaging, CFPreferences, Darwin reload and release workflow.
- Existing NextSolution package indexes and recent daily-tweak failures.
- NextAura and PhoneAura package metadata/layout where source was unavailable.

## Market comparison
Havoc was reviewed for rootless iOS 15–16 system and recording-related tweaks. DNDMyRecording changes Do Not Disturb on older iOS; this project only adds distinct start/stop haptics and does not copy proprietary code, assets, branding or descriptions.

## Attribution and licence
Original implementation using documented Apple UIKit APIs. No paid or proprietary tweak code was copied.
