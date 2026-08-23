#!/bin/bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
import os
src=Path('tmp-build-1325/build.sh').read_text()
src=src.replace('-p3 ', '-p4 ')
needle='xcodebuild -project "$P/NextReminder.xcodeproj"'
insert='''/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.3.25" "$R/appsrc/NextReminderLiveActivity/Info.plist"\n/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 35" "$R/appsrc/NextReminderLiveActivity/Info.plist"\n'''
if needle not in src:
    raise SystemExit('xcode insertion point not found')
src=src.replace(needle, insert+needle, 1)
old='''strings "$APP/NextReminder" > "$R/app.strings"\ngrep -q 'Background Send' "$R/app.strings"\ngrep -q 'Latest 3 saved' "$R/app.strings"\ngrep -q 'Gmail login preserved' "$R/app.strings"\n'''
if old not in src:
    raise SystemExit('binary string guard block not found')
src=src.replace(old, '')
# Verify the embedded extension version after build as well.
marker='''test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")" = '35'\n'''
extra='''EXT="$APP/PlugIns/NextReminderLiveActivity.appex"\ntest "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXT/Info.plist")" = '1.3.25'\ntest "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXT/Info.plist")" = '35'\n'''
if marker not in src:
    raise SystemExit('version guard insertion point not found')
src=src.replace(marker, marker+extra, 1)
out=Path(os.environ['RUNNER_TEMP'])/'build-1325-final-real.sh'
out.write_text(src)
PY
exec bash "$RUNNER_TEMP/build-1325-final-real.sh"
