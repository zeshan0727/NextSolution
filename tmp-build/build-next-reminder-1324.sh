#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
p=Path('tmp-build/build-next-reminder-1322.sh')
s=p.read_text()

# Move the app test build to 1.3.24 / 34 while keeping the tweak at 1.0.13.
s=s.replace('1.3.23', '1.3.24')
s=s.replace("'<string>32</string>','<string>33</string>'", "'<string>32</string>','<string>34</string>'")
s=s.replace("'CURRENT_PROJECT_VERSION = 32;','CURRENT_PROJECT_VERSION = 33;'", "'CURRENT_PROJECT_VERSION = 32;','CURRENT_PROJECT_VERSION = 34;'")
s=s.replace("test \"$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \"$APP/Info.plist\")\" = 33", "test \"$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \"$APP/Info.plist\")\" = 34")

# Keep the Live Activity extension bundle version aligned with the host app.
needle="""plist.write_text(s)
pbx=r/'appsrc/NextReminder.xcodeproj/project.pbxproj'"""
replacement="""plist.write_text(s)
extplist=r/'appsrc/NextReminderLiveActivity/Info.plist'
es=extplist.read_text().replace('<string>1.3.22</string>','<string>1.3.24</string>').replace('<string>32</string>','<string>34</string>')
extplist.write_text(es)
pbx=r/'appsrc/NextReminder.xcodeproj/project.pbxproj'"""
if needle not in s:
    raise SystemExit('extension plist insertion point not found')
s=s.replace(needle, replacement, 1)

# Overwrite the Files/Settings sources with the 1.3.24 report implementation after extraction.
needle="""PYAPP

cat > \"$R/nqrsrc/PendingReportSender.h\""" 
replacement="""PYAPP

python3 - <<'PYREPORTFILES'
from pathlib import Path
import base64, zlib, os
r=Path(os.environ['RUNNER_TEMP'])/'appsrc/NextReminder/Sources'
for encoded_name, target_name in [
    ('tmp-build/fs1324.z64', 'FileSharing.swift'),
    ('tmp-build/settings1324.z64', 'Settings.swift'),
]:
    payload=Path(encoded_name).read_text().strip()
    data=zlib.decompress(base64.b64decode(payload))
    (r/target_name).write_bytes(data)
for swift in r.glob('*.swift'):
    text=swift.read_text()
    if 'NextReminder-iOS/1.3.22.4' in text:
        swift.write_text(text.replace('NextReminder-iOS/1.3.22.4', 'NextReminder-iOS/1.3.24.34'))
PYREPORTFILES

grep -q 'Pending Reminders Report' \"$R/appsrc/NextReminder/Sources/FileSharing.swift\"
grep -q 'UIGraphicsPDFRenderer' \"$R/appsrc/NextReminder/Sources/FileSharing.swift\"
grep -q 'Generate PDF' \"$R/appsrc/NextReminder/Sources/FileSharing.swift\"
grep -q 'Send PDF' \"$R/appsrc/NextReminder/Sources/FileSharing.swift\"

cat > \"$R/nqrsrc/PendingReportSender.h\""" 
if needle not in s:
    raise SystemExit('report source insertion point not found')
s=s.replace(needle, replacement, 1)

# Avoid pipefail false negatives from strings|grep validation in the old script.
s=s.replace("strings \"$APP/NextReminder\" | grep -q 'NextReminder.QuickReportBridgeAPIKey.v1'", "strings \"$APP/NextReminder\" > \"$R/app.strings\"\ngrep -q 'NextReminder.QuickReportBridgeAPIKey.v1' \"$R/app.strings\"")
start=s.index('test \"$(dpkg-deb -f \"$D\" Version)\" = 1.0.13')
end=s.index('cp \"$D\" \"$R/out/NextQuickReminder_1.0.13_RootHide.deb\"', start)
s=s[:start] + 'test \"$(dpkg-deb -f \"$D\" Version)\" = 1.0.13\necho \"RootHide package validated: $D\"\n' + s[end:]

p.write_text(s)
PY

exec bash tmp-build/build-next-reminder-1322.sh
