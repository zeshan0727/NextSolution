# Next Home Lock 1.0.4

Next Home Lock adds one focused feature: double-tap an empty Home Screen area to lock the device.

## Why version 1.0.4 is a full rebuild

Versions 1.0.0–1.0.3 used custom gesture recognizers attached through `SBIconController` or `SBRootFolderView`. Those approaches compiled and packaged correctly but failed on the physical iPhone 14 Pro Max running iOS 16.0 with RootHide.

Version 1.0.4 removes that entire implementation. It now follows the established Home Screen path used by Hao Nguyen's open-source **Lock Screen Without Button** tweak:

- hook `SBIconListView`
- observe its native `touchesEnded:withEvent:` callback
- read the system touch tap count
- on the second background tap, ask SpringBoard to perform `_simulateLockButtonPress`

The implementation is extended with iOS 16 targeting, RootHide/rootless packaging, preference control, diagnostics and additional lock fallbacks. The upstream project is GPLv3 and is credited below.

## Working-tweak patterns adopted

The project structure was also aligned with the working Next Aura and PhoneAura packages in the Next Solution repository:

- explicit RootHide package scheme with rootless override support
- `arm64 arm64e` build architectures
- iOS 16 target
- SpringBoard-only injection filter
- `-Wl,-segalign,4000`
- a real PreferenceLoader subproject under `/Library/PreferenceBundles`
- `CFPreferences` for cross-process preferences and runtime diagnostics
- Darwin notifications for live settings and the Test Lock command

## Compatibility

- iOS 16.0 and later
- Primary physical-device target: iPhone 14 Pro Max, iOS 16.0
- RootHide Bootstrap build
- Standard rootless build
- SpringBoard only
- PreferenceLoader required

## Runtime behaviour

`SBIconListView` receives touches on the Home Screen icon-list background. A single tap continues to Apple's original implementation. A double tap requests a device lock and consumes that background double tap.

Lock routes are attempted in this order:

1. `SpringBoard _simulateLockButtonPress`
2. `pluginUserAgent lockAndDimDevice`
3. `SBLockScreenManager lockUIFromSource:withOptions:`
4. `SBLockScreenManager lockUIFromSource:`
5. `SBSLockDevice`

## Settings diagnostics

Open **Settings → Next Home Lock** after installing and respringing.

The pane shows live values for:

- installed version
- runtime method
- SpringBoard injection and PID
- last load time
- `SBIconListView` class availability
- whether the native touch hook has actually run
- the most recent tap count and view class
- availability of `_simulateLockButtonPress`
- whether the Settings test command reached SpringBoard
- the final lock route selected

The pane uses `CFPreferences` domains rather than a hard-coded physical plist path so RootHide path translation does not hide the runtime status.

## Exact physical-device test

1. Refresh the Next Solution repository.
2. Install or upgrade to version 1.0.4 for the correct jailbreak environment.
3. Perform a full respring.
4. Open **Settings → Next Home Lock** and confirm **SpringBoard Injection** says `Active`.
5. Press **Test Lock Now**.
6. Unlock the phone and tap empty Home Screen space once.
7. Return to Settings and press **Refresh Diagnostics**. **Touch Hook** should say `Reached`.
8. Return Home and double-tap the same empty area.
9. If it does not lock, report the values for SpringBoard Injection, Icon List Class, Touch Hook, Last Tap, Test Command and Last Lock Route.

## Native-feature verification

Stock iOS 16 supports locking through the side button, automatic locking and accessibility controls, but it does not provide a built-in empty-Home-Screen double-tap lock option.

## Privacy and safety

There is no daemon, analytics, network activity, clipboard access, message access or account-data access. Only local preference and diagnostic values are stored. The tweak is filtered to SpringBoard.

## Uninstall behaviour

Uninstalling and respringing removes the hook and Settings pane. The small `CFPreferences` diagnostic domains may remain as harmless history.

## Build validation

The release workflow must validate both architectures and packages, the SpringBoard filter, `SBIconListView`, `touchesEnded:withEvent:`, `_simulateLockButtonPress`, all fallback symbols, PreferenceLoader entry and bundle, `CFPreferences` domains, Darwin notifications, version metadata and source ordering. These checks are build validation; actual runtime behaviour is confirmed only by the physical-device test.

## Attribution and licence

The core `SBIconListView` double-tap and `_simulateLockButtonPress` approach is derived from **Lock Screen Without Button** by Hao Nguyen (`haoict`), licensed under GPLv3. Next Home Lock 1.0.4 is distributed under GPLv3 and includes the upstream licence text. Next Aura and PhoneAura were used as internal working references for RootHide build, preferences and packaging conventions.
