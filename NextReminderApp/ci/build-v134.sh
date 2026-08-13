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
python3 ci/patch_v132.py
python3 ci/patch_v133.py
python3 ci/patch_v134.py

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

grep -q 'let base = reminder.dueDate' NextReminder/Sources/CompletedFilterActions.swift
grep -q 'Current due:' NextReminder/Sources/CompletedFilterActions.swift
grep -q 'repeated extensions accumulate correctly' NextReminder/Sources/CompletedFilterActions.swift
grep -q 'newDate = reminder.dueDate.addingTimeInterval(seconds)' NextReminder/Sources/CompletedFilterActions.swift
! grep -q 'newDate = originalDueDate.addingTimeInterval(seconds)' NextReminder/Sources/CompletedFilterActions.swift
grep -q 'case gta6Latest' NextReminder/Sources/XPostGenerator.swift
grep -q 'case gtaComparisons' NextReminder/Sources/XPostGenerator.swift
grep -q 'Retry Visual Only' NextReminder/Sources/XPostGenerator.swift
grep -q 'placeholderResults' NextReminder/Sources/XPostGenerator.swift

ICON_DIR="NextReminder/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICON_DIR"
python3 ci/generate_icon.py "$ICON_DIR/AppIcon-1024.png"
for size in 40 58 60 80 87 120 180; do
  sips -z "$size" "$size" "$ICON_DIR/AppIcon-1024.png" --out "$ICON_DIR/AppIcon-$size.png" >/dev/null
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
plutil -extract CFBundleShortVersionString raw "$APP/Info.plist" | grep -qx '1.3.4'
plutil -extract CFBundleVersion raw "$APP/Info.plist" | grep -qx '14'
file "$APP/NextReminder" | grep -q 'arm64'

rm -rf Payload
mkdir -p Payload
cp -R "$APP" Payload/
ditto -c -k --sequesterRsrc --keepParent Payload NextReminder-v1.3.4-unsigned.ipa
cp NextReminder-v1.3.4-unsigned.ipa NextReminder-v1.3.4-unsigned.tipa
shasum -a 256 NextReminder-v1.3.4-unsigned.tipa > NextReminder-v1.3.4-unsigned.tipa.sha256
unzip -t NextReminder-v1.3.4-unsigned.tipa >/dev/null

echo "Next Reminder v1.3.4 build and verification completed."
