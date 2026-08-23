#!/bin/bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
p=Path('tmp-build/build-next-reminder-1322.sh')
s=p.read_text()
old="""plist.write_text(s)
pbx=r/'appsrc/NextReminder.xcodeproj/project.pbxproj'"""
new="""plist.write_text(s)
extplist=r/'appsrc/NextReminderLiveActivity/Info.plist'
es=extplist.read_text().replace('<string>1.3.22</string>','<string>1.3.23</string>').replace('<string>32</string>','<string>33</string>')
extplist.write_text(es)
pbx=r/'appsrc/NextReminder.xcodeproj/project.pbxproj'"""
if old not in s:
    raise SystemExit('extension plist insertion point not found')
s=s.replace(old,new,1)
s=s.replace("strings \"$APP/NextReminder\" | grep -q 'NextReminder.QuickReportBridgeAPIKey.v1'", "strings \"$APP/NextReminder\" > \"$R/app.strings\"\ngrep -q 'NextReminder.QuickReportBridgeAPIKey.v1' \"$R/app.strings\"")
s=s.replace("strings -a \"$F\" | grep -q 'Sending report'\nstrings -a \"$F\" | grep -q 'Report sent'\nstrings -a \"$F\" | grep -q 'v1/email-reminders/test'", "strings -a \"$F\" > \"$R/tweak.strings\"\ngrep -q 'Sending report' \"$R/tweak.strings\"\ngrep -q 'Report sent' \"$R/tweak.strings\"\ngrep -q 'v1/email-reminders/test' \"$R/tweak.strings\"")
p.write_text(s)
PY
exec bash tmp-build/build-next-reminder-1322.sh
