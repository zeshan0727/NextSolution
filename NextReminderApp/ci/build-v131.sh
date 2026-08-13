#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

python3 ci/patch_v121.py
python3 ci/patch_v121_fixes.py
python3 ci/patch_v122.py
python3 ci/patch_v123.py
python3 ci/patch_v124.py
python3 ci/patch_v125.py
python3 ci/patch_v130.py
python3 ci/patch_v131.py

# Avoid actor-isolation issues on iOS 16 / Swift 5 mode.
python3 - <<'PY'
from pathlib import Path

file_sharing = Path('NextReminder/Sources/FileSharing.swift')
text = file_sharing.read_text().replace(
    '@MainActor\nfinal class FileShareShortcutStore',
    'final class FileShareShortcutStore'
)
file_sharing.write_text(text)

backup = Path('NextReminder/Sources/BackupRestore.swift')
text = backup.read_text().replace(
    '    static func createPackage(store: ReminderStore) throws -> NextReminderBackupPackage {',
    '    @MainActor\n    static func createPackage(store: ReminderStore) throws -> NextReminderBackupPackage {'
)
backup.write_text(text)
PY

# Verify the requested X draft package and all retained v1.3.0 features.
grep -q 'AIHubView' NextReminder/Sources/RootReminders.swift
grep -q 'XPostGeneratorView' NextReminder/Sources/XPostGenerator.swift
grep -q 'Generate X Post' NextReminder/Sources/XPostGenerator.swift
grep -q 'latest 7 days' NextReminder/Sources/XPostGenerator.swift
grep -q '"web_search"' NextReminder/Sources/XPostGenerator.swift
grep -q 'https://api.openai.com/v1/responses' NextReminder/Sources/XPostGenerator.swift
grep -q 'https://api.openai.com/v1/images/generations' NextReminder/Sources/XPostGenerator.swift
grep -q 'gpt-image-1' NextReminder/Sources/XPostGenerator.swift
grep -q 'Post Details & Tags' NextReminder/Sources/XPostGenerator.swift
grep -q 'Alt for Photo' NextReminder/Sources/XPostGenerator.swift
grep -q 'First Comment' NextReminder/Sources/XPostGenerator.swift
grep -q 'News Source' NextReminder/Sources/XPostGenerator.swift
grep -q 'Save Visual to Photos' NextReminder/Sources/XPostGenerator.swift
grep -q 'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly' NextReminder/Sources/XPostGenerator.swift
grep -q 'OpenAIXGeneratorSettingsView' NextReminder/Sources/Settings.swift
grep -q 'NSPhotoLibraryAddUsageDescription' project.yml
grep -q 'NextReminderBackupPackage' NextReminder/Sources/BackupRestore.swift
grep -q 'DeepSeekAIView' NextReminder/Sources/DeepSeekAI.swift
grep -q 'Automation Center' NextReminder/Sources/Settings.swift
grep -q 'case files' NextReminder/Sources/RootReminders.swift

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
plutil -extract CFBundleShortVersionString raw "$APP/Info.plist" | grep -qx '1.3.1'
plutil -extract CFBundleVersion raw "$APP/Info.plist" | grep -qx '11'
plutil -extract NSPhotoLibraryAddUsageDescription raw "$APP/Info.plist" | grep -q 'Save generated X post visuals'
plutil -extract NSCameraUsageDescription raw "$APP/Info.plist" | grep -q 'Capture and scan documents'
plutil -p "$APP/Info.plist" | grep -q 'nextreminder'
file "$APP/NextReminder" | grep -q 'arm64'

rm -rf Payload
mkdir -p Payload
cp -R "$APP" Payload/
ditto -c -k --sequesterRsrc --keepParent Payload NextReminder-v1.3.1-unsigned.ipa
cp NextReminder-v1.3.1-unsigned.ipa NextReminder-v1.3.1-unsigned.tipa
shasum -a 256 NextReminder-v1.3.1-unsigned.tipa > NextReminder-v1.3.1-unsigned.tipa.sha256
unzip -t NextReminder-v1.3.1-unsigned.tipa >/dev/null

echo "Next Reminder v1.3.1 build and verification completed."
