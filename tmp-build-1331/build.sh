#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
rm -rf "$R/nqrsrc" "$R/out" "$R/theos-rh"
mkdir -p "$R/nqrsrc" "$R/out"
cat tmp-build/nqr1012/part-* > "$R/nqr.b64"
python3 - <<'PY'
import base64,os,pathlib
r=pathlib.Path(os.environ['RUNNER_TEMP'])
(r/'nqr.tar.xz').write_bytes(base64.b64decode((r/'nqr.b64').read_bytes()))
PY
echo 'eba18cc3ee4117e3e190441ce3533e10613a182aa610a3c92756c72a84cfd757  '"$R/nqr.tar.xz" | shasum -a 256 -c -
tar -xJf "$R/nqr.tar.xz" -C "$R/nqrsrc"
cat tmp-build-1325/patch/tweak-* > "$R/tweak1014.patch.xz.b64"
base64 -D < "$R/tweak1014.patch.xz.b64" > "$R/tweak1014.patch.xz"
xz -dc "$R/tweak1014.patch.xz" > "$R/tweak1014.patch"
patch -d "$R/nqrsrc" -p4 < "$R/tweak1014.patch"
base64 -D < tmp-build-1330/tweak1015.patch.xz.b64 > "$R/tweak1015.patch.xz"
xz -dc "$R/tweak1015.patch.xz" > "$R/tweak1015.patch"
patch -d "$R/nqrsrc" -p1 < "$R/tweak1015.patch"
cp tmp-build-1331/PersistentReportScheduler.m "$R/nqrsrc/PersistentReportScheduler.m"
python3 - <<'PYMOD'
from pathlib import Path
import os,re
root=Path(os.environ['RUNNER_TEMP'])/'nqrsrc'
p=root/'Makefile'; s=p.read_text()
old='NextQuickReminder_FILES = Tweak.xm PendingReportSender.m ConsoleBridge.m BackgroundLockscreen.xm MultiTriggersSettings.xm SystemApertureReminderV109.xm'
new='NextQuickReminder_FILES = Tweak.xm PendingReportSender.m PersistentReportScheduler.m ConsoleBridge.m BackgroundLockscreen.xm MultiTriggersSettings.xm SystemApertureReminderV109.xm'
if old not in s: raise SystemExit('Makefile source list not found')
p.write_text(s.replace(old,new,1))
p=root/'Tweak.xm'; s=p.read_text()
if 'NQRStartPendingReportAutomationScheduler();' not in s: raise SystemExit('Old scheduler start call not found')
s=s.replace('NQRStartPendingReportAutomationScheduler();','NQRStartPersistentReportScheduler();',1)
insert='extern void NQRStartPersistentReportScheduler(void);\n'
if insert not in s:
    first=s.find('\n')
    s=s[:first+1]+insert+s[first+1:]
p.write_text(s)
p=root/'control'; s=p.read_text(); s=re.sub(r'^Version:\s*1\.0\.15\s*$','Version: 1.0.16',s,flags=re.M); p.write_text(s)
PYMOD

grep -q 'Version: 1.0.16' "$R/nqrsrc/control"
grep -q 'PersistentReportScheduler.m' "$R/nqrsrc/Makefile"
grep -q 'NQRStartPersistentReportScheduler();' "$R/nqrsrc/Tweak.xm"
! grep -q 'NQRStartPendingReportAutomationScheduler();' "$R/nqrsrc/Tweak.xm"
grep -q 'PCPersistentTimer' "$R/nqrsrc/PersistentReportScheduler.m"
grep -q 'setDisableSystemWaking' "$R/nqrsrc/PersistentReportScheduler.m"
grep -q 'PersistentConnection.framework' "$R/nqrsrc/PersistentReportScheduler.m"
grep -q 'NextReminder.PendingReportAutomationHour.v1' "$R/nqrsrc/PersistentReportScheduler.m"
grep -q 'NextReminder.PendingReportAutomationWeekdays.v1' "$R/nqrsrc/PersistentReportScheduler.m"
grep -q 'NextReminderDatabase.json' "$R/nqrsrc/PendingReportSender.m"
grep -q 'v1/file-shares' "$R/nqrsrc/PendingReportSender.m"

brew install dpkg ldid
T="$R/theos-rh"
git init "$T"
git -C "$T" remote add origin https://github.com/roothide/theos.git
git -C "$T" fetch --depth 1 origin 88506b2c22e9e07dd4ed055f23c9e398a117a2c7
git -C "$T" checkout --detach 88506b2c22e9e07dd4ed055f23c9e398a117a2c7
git -C "$T" submodule update --init --recursive --depth 1
export THEOS="$T" THEOS_PACKAGE_SCHEME=roothide
make -C "$R/nqrsrc" clean package FINALPACKAGE=1
D=$(find "$R/nqrsrc/packages" -name '*.deb' -print -quit)
test -n "$D"
test "$(dpkg-deb -f "$D" Package)" = 'com.nextsolution.nextquickreminder'
test "$(dpkg-deb -f "$D" Version)" = '1.0.16'
X=$(mktemp -d); dpkg-deb -x "$D" "$X"
F=$(find "$X" -name NextQuickReminder.dylib -print -quit); test -n "$F"
strings -a "$F" > "$R/tweak.strings"
grep -q 'PCPersistentTimer' "$R/tweak.strings"
grep -q 'Starting PCPersistentTimer report scheduler' "$R/tweak.strings"
grep -q 'system waking enabled' "$R/tweak.strings"
grep -q 'NextReminder.PendingReportAutomationHour.v1' "$R/tweak.strings"
grep -q 'NextReminderDatabase.json' "$R/tweak.strings"
grep -q 'v1/file-shares' "$R/tweak.strings"
cp "$D" "$R/out/NextQuickReminder_1.0.16_RootHide.deb"
cd "$R/out"
shasum -a 256 NextQuickReminder_1.0.16_RootHide.deb > SHA256SUMS.txt
ls -lh
cat SHA256SUMS.txt
