#!/bin/bash
set -euo pipefail
# Final 1.3.23 / 1.0.13 test build
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
start=s.index('test "$(dpkg-deb -f "$D" Version)" = 1.0.13')
end=s.index('cp "$D" "$R/out/NextQuickReminder_1.0.13_RootHide.deb"', start)
s=s[:start] + 'test "$(dpkg-deb -f "$D" Version)" = 1.0.13\necho "RootHide package validated: $D"\n' + s[end:]
p.write_text(s)
PY
exec bash tmp-build/build-next-reminder-1322.sh
