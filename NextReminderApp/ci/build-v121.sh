#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

python3 ci/patch_v121.py
python3 ci/patch_v121_fixes.py

# Verify requested source features exist before compiling.
grep -q 'Connect Gmail Account' NextReminder/Sources/GmailConnection.swift
grep -q 'Performance Summary' NextReminder/Sources/PerformanceAndRepeat.swift
grep -q 'Selected Days' NextReminder/Sources/Editor.swift
grep -q 'Sunday–Thursday' NextReminder/Sources/PerformanceAndRepeat.swift
grep -q 'nextreminder' project.yml

ICON_DIR="NextReminder/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICON_DIR"
python3 ci/generate_icon.py "$ICON_DIR/AppIcon-1024.png"
for size in 40 58 60 80 87 120 180; do
  sips -z "$size" "$size" "$ICON_DIR/AppIcon-1024.png" \
    --out "$ICON_DIR/AppIcon-$size.png" >/dev/null
done

if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi
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

APP="build/NextReminder.app"
test -f "$APP/Assets.car"
test -x "$APP/NextReminder"
plutil -p "$APP/Info.plist" | grep -q 'CFBundleIcons'
plutil -extract CFBundleShortVersionString raw "$APP/Info.plist" | grep -qx '1.2.1'
plutil -extract CFBundleVersion raw "$APP/Info.plist" | grep -qx '5'
plutil -p "$APP/Info.plist" | grep -q 'nextreminder'
file "$APP/NextReminder" | grep -q 'arm64'

rm -rf Payload
mkdir -p Payload
cp -R "$APP" Payload/
ditto -c -k --sequesterRsrc --keepParent Payload NextReminder-v1.2.1-unsigned.ipa
cp NextReminder-v1.2.1-unsigned.ipa NextReminder-v1.2.1-unsigned.tipa
shasum -a 256 NextReminder-v1.2.1-unsigned.tipa > NextReminder-v1.2.1-unsigned.tipa.sha256
unzip -t NextReminder-v1.2.1-unsigned.tipa >/dev/null

SCHEDULER_DIR="../NextReminderScheduler"
node --check "$SCHEDULER_DIR/server.js"
rm -f NextReminderScheduler-v1.2.1.zip
ditto -c -k --sequesterRsrc --keepParent "$SCHEDULER_DIR" NextReminderScheduler-v1.2.1.zip
unzip -t NextReminderScheduler-v1.2.1.zip >/dev/null

echo "Next Reminder v1.2.1 build and verification completed."
