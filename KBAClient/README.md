# KBA Client for iPhone

A publishable SwiftUI customer portal for KB Accountant, designed around the services currently presented on `kbaccountant.com`.

## Test build 0.1.0

This first build is intentionally **local test mode**:

- Customer onboarding and market selection
- Eight KBA service categories
- Service search and jurisdiction filters
- Local service request creation and status timeline
- Local document import and deletion
- Consultation request form and optional local reminder
- UK, USA, Qatar and UAE contact actions
- Light, dark and system appearance
- Demo request tool for feature checking
- Complete local data reset

Requests, appointments and documents are **not transmitted**. The interface labels this clearly so testers cannot mistake the prototype for a live customer system.

## Build a TIPA

1. Install Xcode 16 and XcodeGen.
2. Run:

```bash
cd KBAClient
bash Scripts/prepare-assets.sh
xcodegen generate
xcodebuild -project KBAClient.xcodeproj -scheme KBAClient -configuration Release -sdk iphoneos -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/KBAClient.app Payload/
ditto -c -k --sequesterRsrc --keepParent Payload KBAClient-0.1.0-test.tipa
```

The GitHub Actions workflow performs the same build and uploads the TIPA plus SHA-256 checksum.

## Release gates

The final build must not be published until all items in `QA_TEST_PLAN.md` and `RELEASE_CHECKLIST.md` pass.

The same standard SwiftUI source can later be archived and signed for TestFlight/App Store because it does not use jailbreak or private iOS APIs. The TIPA packaging is only a testing distribution method.
