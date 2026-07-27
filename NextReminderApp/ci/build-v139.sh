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
path = Path('ci/patch_v135.py')
text = path.read_text()
old = '''    ''' + "'''" + '''        SelectedDayScheduleStore.shared.remove(for: reminder.id)
    }

    func complete''' + "'''" + ''',
    ''' + "'''" + '''        SelectedDayScheduleStore.shared.remove(for: reminder.id)
        HourlyRepeatStore.shared.remove(for: reminder.id)
    }

    func complete''' + "'''" + '''
'''
new = '''    ''' + "'''" + '''        SelectedDayScheduleStore.shared.remove(for: reminder.id)
        UnattendedReminderTracker.shared.remove(reminder.id)
        refreshUnattendedBadge()
    }

    func complete''' + "'''" + ''',
    ''' + "'''" + '''        SelectedDayScheduleStore.shared.remove(for: reminder.id)
        HourlyRepeatStore.shared.remove(for: reminder.id)
        UnattendedReminderTracker.shared.remove(reminder.id)
        refreshUnattendedBadge()
    }

    func complete''' + "'''" + '''
'''
if old not in text:
    raise SystemExit('Could not adjust v1.3.5 service lifecycle pattern')
path.write_text(text.replace(old, new, 1))
PY

python3 ci/patch_v135.py
python3 ci/patch_v136.py
python3 ci/patch_v137.py
python3 ci/adjust_v138_root.py
python3 ci/patch_v138.py
python3 ci/patch_v139.py

python3 - <<'PY'
from pathlib import Path
file_sharing = Path('NextReminder/Sources/FileSharing.swift')
file_sharing.write_text(file_sharing.read_text().replace('@MainActor\nfinal class FileShareShortcutStore', 'final class FileShareShortcutStore'))
backup = Path('NextReminder/Sources/BackupRestore.swift')
backup.write_text(backup.read_text().replace('    static func createPackage(store: ReminderStore) throws -> NextReminderBackupPackage {', '    @MainActor\n    static func createPackage(store: ReminderStore) throws -> NextReminderBackupPackage {'))
PY

grep -q 'Stop Routine & Cancel Alerts' NextReminder/Sources/Editor.swift
grep -q 'showStopRoutineConfirmation' NextReminder/Sources/Editor.swift
grep -q 'stopRoutineImmediately' NextReminder/Sources/Editor.swift
grep -q 'HourlyRepeatStore.shared.remove' NextReminder/Sources/Editor.swift
grep -q 'await NotificationManager.shared.cancel' NextReminder/Sources/Editor.swift
grep -q 'existing.notificationsEnabled = false' NextReminder/Sources/Editor.swift
grep -q 'isStoppingExistingRoutine' NextReminder/Sources/Editor.swift

grep -q 'effectiveOffsets.insert(.atTime)' NextReminder/Sources/Services.swift
grep -q 'final class GmailConnectionHealthMonitor' NextReminder/Sources/GmailConnection.swift
grep -q 'static let startHour = 8' NextReminder/Sources/RoutineReminders.swift
grep -q 'Occurrence History' NextReminder/Sources/Detail.swift
grep -q 'case gta6Latest' NextReminder/Sources/XPostGenerator.swift

ICON_DIR="NextReminder/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICON_DIR"
python3 ci/generate_icon.py "$ICON_DIR/AppIcon-1024.png"
for size in 40 58 60 80 87 120 180; do
  sips -z "$size" "$size" "$ICON_DIR/AppIcon-1024.png" --out "$ICON_DIR/AppIcon-$size.png" >/dev/null
done

if ! command -v xcodegen >/dev/null 2>&1; then brew install xcodegen; fi
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
plutil -extract CFBundleShortVersionString raw "$APP/Info.plist" | grep -qx '1.3.9'
plutil -extract CFBundleVersion raw "$APP/Info.plist" | grep -qx '19'
file "$APP/NextReminder" | grep -q 'arm64'

rm -rf Payload
mkdir -p Payload
cp -R "$APP" Payload/
ditto -c -k --sequesterRsrc --keepParent Payload NextReminder-v1.3.9-unsigned.ipa
cp NextReminder-v1.3.9-unsigned.ipa NextReminder-v1.3.9-unsigned.tipa
shasum -a 256 NextReminder-v1.3.9-unsigned.tipa > NextReminder-v1.3.9-unsigned.tipa.sha256
unzip -t NextReminder-v1.3.9-unsigned.tipa >/dev/null

echo "Next Reminder v1.3.9 build and verification completed."
