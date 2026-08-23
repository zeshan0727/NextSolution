#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
rm -rf "$R/appsrc" "$R/inspect"
mkdir -p "$R/appsrc" "$R/inspect"
python3 - <<'PYFIX'
from pathlib import Path
p=Path('tmp-build/nr1322xz/part-09')
f=Path('tmp-build/appfix/part09-block6000.txt').read_bytes()
b=bytearray(p.read_bytes()); b[6000:6500]=f; p.write_bytes(b)
PYFIX
cat tmp-build/nr1322xz/part-* > "$R/nr.b64"
python3 - <<'PYDEC'
import base64,os,pathlib
r=pathlib.Path(os.environ['RUNNER_TEMP'])
(r/'nr.tar.xz').write_bytes(base64.b64decode((r/'nr.b64').read_bytes()))
PYDEC
tar -xJf "$R/nr.tar.xz" -C "$R/appsrc"
cat tmp-build-1325/patch/app-* > "$R/app1325.patch.xz.b64"
base64 -D < "$R/app1325.patch.xz.b64" > "$R/app1325.patch.xz"
xz -dc "$R/app1325.patch.xz" > "$R/app1325.patch"
patch -d "$R/appsrc" -p4 < "$R/app1325.patch"
base64 -D < tmp-build-1326/app1326.patch.xz.b64 > "$R/app1326.patch.xz"
xz -dc "$R/app1326.patch.xz" > "$R/app1326.patch"
patch -d "$R/appsrc" -p1 < "$R/app1326.patch"
cp "$R/appsrc/NextReminder/Sources/FileSharing.swift" "$R/inspect/FileSharing.swift"
cp "$R/appsrc/NextReminder/Sources/RootView.swift" "$R/inspect/RootView.swift" 2>/dev/null || true
cp "$R/appsrc/NextReminder/Sources/ContentView.swift" "$R/inspect/ContentView.swift" 2>/dev/null || true
cp "$R/appsrc/NextReminder.xcodeproj/project.pbxproj" "$R/inspect/project.pbxproj"
find "$R/appsrc/NextReminder/Sources" -maxdepth 1 -type f -name '*.swift' -print | sort > "$R/inspect/source-files.txt"
