#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
rm -rf "$R/nqrsrc" "$R/inspect"
mkdir -p "$R/nqrsrc" "$R/inspect"
cat tmp-build/nqr1012/part-* > "$R/nqr.b64"
python3 - <<'PY'
import base64,os,pathlib
r=pathlib.Path(os.environ['RUNNER_TEMP'])
(r/'nqr.tar.xz').write_bytes(base64.b64decode((r/'nqr.b64').read_bytes()))
PY
tar -xJf "$R/nqr.tar.xz" -C "$R/nqrsrc"
cat tmp-build-1325/patch/tweak-* > "$R/tweak1014.patch.xz.b64"
base64 -D < "$R/tweak1014.patch.xz.b64" > "$R/tweak1014.patch.xz"
xz -dc "$R/tweak1014.patch.xz" > "$R/tweak1014.patch"
patch -d "$R/nqrsrc" -p4 < "$R/tweak1014.patch"
base64 -D < tmp-build-1330/tweak1015.patch.xz.b64 > "$R/tweak1015.patch.xz"
xz -dc "$R/tweak1015.patch.xz" > "$R/tweak1015.patch"
patch -d "$R/nqrsrc" -p1 < "$R/tweak1015.patch"
cp "$R/nqrsrc/PendingReportSender.m" "$R/inspect/"
cp "$R/nqrsrc/PendingReportSender.h" "$R/inspect/"
cp "$R/nqrsrc/Tweak.xm" "$R/inspect/"
cp "$R/nqrsrc/Makefile" "$R/inspect/"
cp "$R/nqrsrc/control" "$R/inspect/"
grep -n -E 'Automation|Scheduler|Timer|schedule|NQRStartPending|NQRCheck|LastSuccess|Weekday' "$R/nqrsrc/PendingReportSender.m" > "$R/inspect/scheduler-lines.txt" || true
