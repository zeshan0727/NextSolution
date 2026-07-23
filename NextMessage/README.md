# Next Message

A Concept H-inspired redesign for Apple Messages.

## Current foundation

- iOS 15 and newer deployment target
- arm64 and arm64e builds
- RootHide and rootless packaging
- Light, Black, and Follow System appearance modes
- Frosted conversation cards
- Minimal conversation and composer styling
- Swipe Info action
- Stock Delete action preservation with a guarded fallback
- Conversation information toast showing:
  - total messages in the selected conversation
  - first conversation start date
- PreferenceLoader settings bundle with RootHide entitlements
- Live preference reload through Darwin notifications

## Package

- Identifier: `com.nextsolution.nextmessage`
- Name: `Next Message`
- Author: `Next Solution - Zeshan 0727`

## Build

```sh
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

The GitHub Actions workflow builds both package schemes on macOS so the arm64e system-app target uses the correct toolchain.

## First device test target

- iPhone 14 Pro Max
- iOS 16.0
- RootHide

## Development status

Version `0.1.0` is the first implementation foundation. Private Messages classes can vary across iOS releases, so device testing will be used to confirm and refine the exact conversation-list and chat-view hooks before release.
