#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
cp tmp-build-1326/build.sh "$R/build1327-real.sh"
python3 - <<'PY'
from pathlib import Path
import os
p=Path(os.environ['RUNNER_TEMP'])/'build1327-real.sh'
s=p.read_text()

# Use an isolated Python environment for Pillow on hosted macOS.
s=s.replace(
    'python3 -m pip install --quiet pillow\npython3 - <<\'PYICON\'',
    'python3 -m venv "$R/iconvenv"\n"$R/iconvenv/bin/pip" install --quiet pillow\n"$R/iconvenv/bin/python" - <<\'PYICON\''
)

# Apply the 1.3.27 stability patch after the verified 1.3.26 patch.
needle='patch -d "$R/appsrc" -p1 < "$R/app1326.patch"\n'
insert='''patch -d "$R/appsrc" -p1 < "$R/app1326.patch"\n\n# 1.3.27 stability-first Files isolation patch.\nbase64 -D < tmp-build-1327/filesharing1327.patch.xz.b64 > "$R/app1327.patch.xz"\nxz -dc "$R/app1327.patch.xz" > "$R/app1327.patch"\npatch -d "$R/appsrc" -p1 < "$R/app1327.patch"\n'''
if needle not in s:
    raise SystemExit('Could not locate 1.3.26 patch application')
s=s.replace(needle,insert,1)

# Bump app and Live Activity versions immediately before Xcode build.
needle='xcodebuild -project "$P/NextReminder.xcodeproj" -scheme NextReminder \\\n'
bump='''python3 - <<'PYVER'\nfrom pathlib import Path\nimport os\nroot=Path(os.environ['RUNNER_TEMP'])/'appsrc'\npbx=root/'NextReminder.xcodeproj/project.pbxproj'\nt=pbx.read_text().replace('CURRENT_PROJECT_VERSION = 36;', 'CURRENT_PROJECT_VERSION = 37;').replace('MARKETING_VERSION = 1.3.26;', 'MARKETING_VERSION = 1.3.27;')\npbx.write_text(t)\nfor rel in ['NextReminder/Resources/Info.plist','NextReminderLiveActivity/Info.plist']:\n    q=root/rel\n    if q.exists():\n        x=q.read_text().replace('<string>1.3.26</string>','<string>1.3.27</string>').replace('<string>36</string>','<string>37</string>')\n        q.write_text(x)\nPYVER\n\n# Landing-screen guards: report work must be behind explicit navigation.\ngrep -q 'private var pendingReminderReportEntry' "$P/NextReminder/Sources/FileSharing.swift"\ngrep -q 'PDF reports, saved copies & background send' "$P/NextReminder/Sources/FileSharing.swift"\npython3 - <<'PYGUARD'\nfrom pathlib import Path\nimport os,re\ns=(Path(os.environ['RUNNER_TEMP'])/'appsrc/NextReminder/Sources/FileSharing.swift').read_text()\nbody=s[s.index('var body: some View'):s.index('private var pendingReminderReportEntry')]
assert 'pendingReminderReportEntry' in body\nassert 'pendingReminderReportSection' not in body\nonappear=re.search(r'\\.onAppear \\{(.*?)\\n        \\}', body, re.S)\nassert onappear and 'loadSavedPendingReports()' not in onappear.group(1)\nassert 'NextReminder-iOS/1.3.27.37' in s\nPYGUARD\n\n'''+needle
if needle not in s:
    raise SystemExit('Could not locate xcodebuild invocation')
s=s.replace(needle,bump,1)

# Update build expectations/output naming only.
s=s.replace("= '1.3.26'", "= '1.3.27'")
s=s.replace("= '36'", "= '37'")
s=s.replace('NextReminder_1.3.26_Unsigned.tipa','NextReminder_1.3.27_Unsigned.tipa')

p.write_text(s)
PY
exec bash "$R/build1327-real.sh"
