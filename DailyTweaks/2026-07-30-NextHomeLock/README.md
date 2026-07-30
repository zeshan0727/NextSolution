# Next Home Lock 1.0.2

Next Home Lock adds one focused feature: double-tap a genuinely empty area of the Home Screen to lock the device.

## Version history and fixes

### 1.0.2

Version 1.0.1 installed the gesture on `SBRootFolderView`, but the safety filter rejected every touch because the valid root class itself contains the word `Folder`. The filter now recognizes the root container before checking interactive child classes. Folder icons and folder UI remain blocked using narrower class-name checks.

### 1.0.1

Version 1.0.0 injected into SpringBoard but attached its recognizer through `SBIconController viewDidLoad`, which is not a dependable Home Screen view lifecycle point on iOS 16. Version 1.0.1 moved installation to `SBRootFolderView` and added compatible lock fallbacks.

## Native feature verification

Apple's iPhone User Guide documents the stock manual lock action as pressing the side button, with automatic locking controlled separately. AssistiveTouch can expose a Lock Screen control, but iOS 16 does not provide a built-in option to double-tap an empty Home Screen area to lock. The existing Next Solution source and package indexes were also searched for this exact feature before implementation.

## Compatibility

- iOS 15.0 and later
- Primary test target: iPhone 14 Pro Max on iOS 16.0
- RootHide Bootstrap build
- Standard rootless build
- SpringBoard only

## Behaviour

The gesture is installed on the actual Home Screen root-folder view. It locks only after a two-tap gesture on a recognized Home Screen background surface.

Touches are rejected when they originate from or pass through icons, folder icons or folder UI, the dock, widgets, page controls, search, App Library, Today View, buttons, Control Center, the app switcher, context menus, editing UI, or notification-style platter views. The gesture is disabled while the Home Screen is in icon-editing mode.

The recognizer does not cancel normal touches. There is no daemon, analytics, clipboard access, network activity, or background data collection.

## Installation

1. Refresh the Next Solution repository.
2. Upgrade or install version 1.0.2 for the matching jailbreak environment.
3. Respring when requested.
4. On the Home Screen, double-tap an empty space between icons.

## Uninstall behaviour

Uninstalling the package and respringing removes the gesture completely. No preferences or user data are stored.

## Device test checklist

- Confirm Sileo shows version 1.0.2.
- Double-tap empty Home Screen space locks the device.
- Single tap does nothing.
- Double-tapping an app icon does not lock and does not interfere with launching.
- Double-tapping a widget or the dock does not lock.
- The gesture is disabled while icons are being rearranged.
- Folder, Spotlight/Search, Today View, App Library and Control Center interactions remain normal.
- No gesture remains after uninstall and respring.

## Known limitations

SpringBoard view class names can differ on future iOS versions. The package is conservatively filtered and is primarily intended for iOS 15 and iOS 16.

## Market comparison

Havoc and public jailbreak tweak catalogues were reviewed for gesture-oriented rootless tweak patterns. This implementation is original, free, limited to one Home Screen action, and does not copy paid source code, assets, branding or descriptions.
