# Next Home Lock 1.0.5

Next Home Lock adds one focused feature: double-tap an empty Home Screen area to lock the device.

## Version 1.0.5

Version 1.0.5 keeps the physically verified 1.0.4 runtime unchanged and simplifies **Settings → Next Home Lock** to one switch:

- **Enable Next Home Lock**

All diagnostic rows and test buttons were removed from the visible Settings pane. The internal SpringBoard method remains the proven `SBIconListView` native `touchesEnded:withEvent:` path with SpringBoard simulated lock-button action and fallback lock routes.

## Working implementation

The runtime follows the established Home Screen path used by Hao Nguyen's open-source **Lock Screen Without Button** tweak:

- hook `SBIconListView`
- observe its native `touchesEnded:withEvent:` callback
- read the system touch tap count
- on the second background tap, ask SpringBoard to perform `_simulateLockButtonPress`

The project uses working Next Aura and PhoneAura conventions for RootHide and rootless packaging, `CFPreferences`, PreferenceLoader and Darwin preference-change notifications.

## Compatibility

- iOS 16.0 and later
- Primary target: iPhone 14 Pro Max on iOS 16.0
- RootHide Bootstrap
- Standard rootless jailbreaks
- SpringBoard only
- PreferenceLoader required

## Settings

Open **Settings → Next Home Lock**.

Turn **Enable Next Home Lock** on or off. Changes are sent immediately to SpringBoard through the existing preference notification, so no additional diagnostic controls are shown.

## Runtime behaviour

`SBIconListView` receives touches on the Home Screen icon-list background. A single tap continues to Apple's original implementation. An enabled double tap requests a device lock and consumes that background double tap.

Lock routes are attempted in this order:

1. `SpringBoard _simulateLockButtonPress`
2. `pluginUserAgent lockAndDimDevice`
3. `SBLockScreenManager lockUIFromSource:withOptions:`
4. `SBLockScreenManager lockUIFromSource:`
5. `SBSLockDevice`

## Physical-device test

1. Install or upgrade to version 1.0.5 for the matching jailbreak environment.
2. Perform a full respring.
3. Open **Settings → Next Home Lock**.
4. Turn the switch off and confirm double-tap no longer locks.
5. Turn the switch on and confirm double-tap locks again.

## Privacy and safety

There is no daemon, analytics, network activity, clipboard access, message access or account-data access. The tweak is filtered to SpringBoard.

## Uninstall behaviour

Uninstalling and respringing removes the hook and Settings pane.

## Build validation

The release workflow validates both architectures, the SpringBoard filter, `SBIconListView`, `touchesEnded:withEvent:`, `_simulateLockButtonPress`, fallback symbols, the PreferenceLoader entry and bundle, the single enabled switch, `CFPreferences`, Darwin preference notifications and version metadata. Runtime confirmation still requires the physical-device switch test.

## Attribution and licence

The core `SBIconListView` double-tap and `_simulateLockButtonPress` approach is derived from **Lock Screen Without Button** by Hao Nguyen (`haoict`), licensed under GPLv3. Next Home Lock is distributed under GPLv3 and includes the upstream licence text. Next Aura and PhoneAura were used as internal working references for RootHide build, preferences and packaging conventions.
