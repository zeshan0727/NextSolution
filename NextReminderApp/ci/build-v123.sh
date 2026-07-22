#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

python3 ci/patch_v121.py
python3 ci/patch_v121_fixes.py
python3 ci/patch_v122.py
python3 ci/patch_v123.py

# Avoid actor-isolated StateObject initialization issues on iOS 16 / Swift 5 mode.
python3 - <<'PY'
from pathlib import Path
p = Path('NextReminder/Sources/FileSharing.swift')
text = p.read_text().replace('@MainActor\nfinal class FileShareShortcutStore', 'final class FileShareShortcutStore')
p.write_text(text)
PY

# Verify requested features before compiling.
grep -q 'FileSharingView' NextReminder/Sources/FileSharing.swift
grep -q 'v1/file-shares' NextReminder/Sources/FileSharing.swift
grep -q 'Barjous' NextReminder/Sources/FileSharing.swift
grep -q 'Atelier Home' NextReminder/Sources/FileSharing.swift
grep -q 'DocumentScannerView' NextReminder/Sources/FileSharing.swift
grep -q '"+1 Hour"' NextReminder/Sources/CompletedFilterActions.swift
grep -q '"+2 Hours"' NextReminder/Sources/CompletedFilterActions.swift
grep -q '"+1 Day"' NextReminder/Sources/CompletedFilterActions.swift
grep -q 'case files' NextReminder/Sources/RootReminders.swift
grep -q 'NSCameraUsageDescription' project.yml

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
plutil -extract CFBundleShortVersionString raw "$APP/Info.plist" | grep -qx '1.2.3'
plutil -extract CFBundleVersion raw "$APP/Info.plist" | grep -qx '7'
plutil -extract NSCameraUsageDescription raw "$APP/Info.plist" | grep -q 'Capture and scan documents'
plutil -p "$APP/Info.plist" | grep -q 'nextreminder'
file "$APP/NextReminder" | grep -q 'arm64'

rm -rf Payload
mkdir -p Payload
cp -R "$APP" Payload/
ditto -c -k --sequesterRsrc --keepParent Payload NextReminder-v1.2.3-unsigned.ipa
cp NextReminder-v1.2.3-unsigned.ipa NextReminder-v1.2.3-unsigned.tipa
shasum -a 256 NextReminder-v1.2.3-unsigned.tipa > NextReminder-v1.2.3-unsigned.tipa.sha256
unzip -t NextReminder-v1.2.3-unsigned.tipa >/dev/null

echo "Next Reminder v1.2.3 build and verification completed."
