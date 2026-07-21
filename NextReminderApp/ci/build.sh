#!/bin/bash
set -euo pipefail

# Next Reminder v1.0.1 verified release build.
cd "$(dirname "$0")/.."
ICON_DIR="NextReminder/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICON_DIR"
python3 ci/generate_icon.py "$ICON_DIR/AppIcon-1024.png"
for size in 40 58 60 80 87 120 180; do
  sips -z "$size" "$size" "$ICON_DIR/AppIcon-1024.png" \
    --out "$ICON_DIR/AppIcon-$size.png" >/dev/null
done

brew install xcodegen
xcodegen generate

set -o pipefail
xcodebuild \
  -project NextReminder.xcodeproj \
  -scheme NextReminder \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  CONFIGURATION_BUILD_DIR="$PWD/build" \
  clean build | tee xcodebuild.log

# Fail the build if icon/resources are missing.
test -f build/NextReminder.app/Assets.car
plutil -p build/NextReminder.app/Info.plist | grep -q 'CFBundleIcons'
file build/NextReminder.app/NextReminder | grep -q 'arm64'

rm -rf Payload
mkdir -p Payload
cp -R build/NextReminder.app Payload/
ditto -c -k --sequesterRsrc --keepParent Payload NextReminder-v1.0.1-unsigned.ipa
cp NextReminder-v1.0.1-unsigned.ipa NextReminder-v1.0.1-unsigned.tipa
shasum -a 256 NextReminder-v1.0.1-unsigned.tipa > NextReminder-v1.0.1-unsigned.tipa.sha256
