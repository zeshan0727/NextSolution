# Next Home Lock 1.0.3

Next Home Lock adds one focused feature: double-tap a genuinely empty area of the Home Screen to lock the device.

## Version history and fixes

### 1.0.3 diagnostics release

Version 1.0.3 adds a PreferenceLoader pane under **Settings → Next Home Lock**. It separates the runtime path into visible checkpoints:

- package version installed
- tweak loaded inside SpringBoard
- `SBRootFolderView` class and hook reached
- gesture recognizer attached and host class
- last Home Screen touch accepted or rejected with its reason
- last double-tap recognition result
- last lock route selected
- Settings test command received by SpringBoard

The **Test Lock Now** button sends the Darwin notification `com.nextsolution.nexthomelock.test-lock` to SpringBoard. If that button locks the phone, injection and the lock route are working and the remaining fault is in gesture attachment or filtering. If the command is not received, the pane will show that injection is not active.

Runtime status is stored locally at `/var/mobile/Library/Preferences/com.nextsolution.nexthomelock.runtime.plist`. No network, analytics, clipboard, message or account data is accessed.

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
- PreferenceLoader required for diagnostics

## Behaviour

The gesture is installed on the actual Home Screen root-folder view. It locks only after a two-tap gesture on a recognized Home Screen background surface.

Touches are rejected when they originate from or pass through icons, folder icons or folder UI, the dock, widgets, page controls, search, App Library, Today View, buttons, Control Center, the app switcher, context menus, editing UI, or notification-style platter views. The gesture is disabled while the Home Screen is in icon-editing mode.

The recognizer does not cancel normal touches. There is no daemon, analytics, clipboard access, network activity, or background data collection.

## Installation and diagnostic test

1. Refresh the Next Solution repository.
2. Upgrade or install version 1.0.3 for the matching jailbreak environment.
3. Respring when requested.
4. Open **Settings → Next Home Lock**.
5. Confirm **SpringBoard Injection** says `Active` and **Gesture Attachment** says `Attached`.
6. Press **Test Lock Now**. The device should lock immediately if the injected tweak and lock selector are functional.
7. Unlock, double-tap empty Home Screen space, then return to the diagnostic pane and press **Refresh Diagnostics**.
8. Report the exact values shown for SpringBoard Injection, Root Folder Hook, Gesture Attachment, Last Touch Decision, Last Gesture, Test Command and Last Lock Route.

## Uninstall behaviour

Uninstalling the package and respringing removes the gesture and Settings pane. The local runtime status plist may remain as harmless diagnostic history and can be deleted manually.

## Build validation

The release workflow validates both package architectures, PreferenceLoader dependency, SpringBoard filter, dylib symbols, preference bundle, Settings entry plist, diagnostic notification name, runtime status path and version metadata. These checks confirm package structure and diagnostic instrumentation, not physical-device runtime behaviour.

## Known limitations

SpringBoard view class names can differ between iOS versions and jailbreak environments. Version 1.0.3 is intentionally diagnostic so the exact failing runtime checkpoint can be identified on the target RootHide device.

## Market comparison

Havoc and public jailbreak tweak catalogues were reviewed for gesture-oriented rootless tweak patterns. This implementation is original, free, limited to one Home Screen action, and does not copy paid source code, assets, branding or descriptions.
