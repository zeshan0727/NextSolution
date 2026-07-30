# Next Charge Pulse

Daily tweak test release for July 30, 2026.

## Feature

Next Charge Pulse gives one clear success haptic when the device transitions from battery power to external power. It does not add feedback when power is disconnected, when charging reaches 100%, or immediately after a respring.

## Compatibility

- iOS 15.0 and later
- Primary test target: iPhone 14 Pro Max, iOS 16.0
- Rootless jailbreak package: `iphoneos-arm64`
- RootHide package: `iphoneos-arm64e`
- Injects only into SpringBoard

## Installation

Install the package matching the jailbreak environment from the Next Solution Sileo repository, then respring if the package manager does not do so automatically.

## Settings

There are no settings. The tweak is intentionally focused on one feature.

## Uninstall behaviour

Removing the package and respringing fully removes the observer and restores stock behaviour. The tweak does not modify system files or store user data.

## Test checklist

1. Install the package matching the jailbreak environment and respring.
2. Confirm there is no haptic caused only by the respring.
3. Disconnect external power and wait several seconds.
4. Connect a Lightning cable or supported wireless charger.
5. Confirm one success haptic occurs.
6. Leave the phone charging and confirm no repeated haptics occur.
7. Disconnect power and confirm no additional custom haptic occurs.
8. Reconnect power and confirm one haptic occurs again.

## Safety notes

- Uses `UIDeviceBatteryStateDidChangeNotification` and `UINotificationFeedbackGenerator`.
- Does not read clipboard, messages, credentials, files, contacts, location, network traffic, or notification content.
- Does not hook charging control, battery limits, passcode functions, security services, or application processes.

## Known limitations

The exact perceived haptic strength follows the device's Taptic Engine and system haptic behaviour. Hardware or system settings that suppress haptics may prevent feedback.

## Market comparison

The current Havoc catalogue was reviewed for general utility and system-feedback patterns. This implementation is original, contains no third-party source or assets, and does not reproduce a paid tweak feature-for-feature.
