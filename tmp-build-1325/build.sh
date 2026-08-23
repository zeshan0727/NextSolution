#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
mkdir -p "$R/appsrc" "$R/nqrsrc" "$R/out"

# Repair and reconstruct the already-verified 1.3.22 / 1.0.12 source payloads.
python3 - <<'PYFIX'
from pathlib import Path
p=Path('tmp-build/nr1322xz/part-09')
f=Path('tmp-build/appfix/part09-block6000.txt').read_bytes()
b=bytearray(p.read_bytes())
assert len(b)==10000 and len(f)==500
b[6000:6500]=f
p.write_bytes(b)
PYFIX
cat tmp-build/nr1322xz/part-* > "$R/nr.b64"
cat tmp-build/nqr1012/part-* > "$R/nqr.b64"
python3 - <<'PYDEC'
import base64,os,pathlib
r=pathlib.Path(os.environ['RUNNER_TEMP'])
(r/'nr.tar.xz').write_bytes(base64.b64decode((r/'nr.b64').read_bytes()))
(r/'nqr.tar.xz').write_bytes(base64.b64decode((r/'nqr.b64').read_bytes()))
PYDEC
echo '8334365b7095d7fb3b1cbe92a08a837c097a6ca3b6de7f34765d2541ceaf0046  '"$R/nr.tar.xz" | shasum -a 256 -c -
echo 'eba18cc3ee4117e3e190441ce3533e10613a182aa610a3c92756c72a84cfd757  '"$R/nqr.tar.xz" | shasum -a 256 -c -
tar -xJf "$R/nr.tar.xz" -C "$R/appsrc"
tar -xJf "$R/nqr.tar.xz" -C "$R/nqrsrc"

# Decode and apply only the 1.3.25 / 1.0.14 changes.
cat tmp-build-1325/patch/app-* > "$R/app.patch.xz.b64"
cat tmp-build-1325/patch/tweak-* > "$R/tweak.patch.xz.b64"
base64 -D < "$R/app.patch.xz.b64" > "$R/app.patch.xz"
base64 -D < "$R/tweak.patch.xz.b64" > "$R/tweak.patch.xz"
xz -dc "$R/app.patch.xz" > "$R/app.patch"
xz -dc "$R/tweak.patch.xz" > "$R/tweak.patch"
patch -d "$R/appsrc" -p3 < "$R/app.patch"
patch -d "$R/nqrsrc" -p3 < "$R/tweak.patch"

# Source-level guards for this test.
grep -q 'NextReminder.BackgroundReportSendEnabled.v1' "$R/appsrc/NextReminder/Sources/FileSharing.swift"
grep -q 'Latest 3 saved' "$R/appsrc/NextReminder/Sources/FileSharing.swift"
grep -q 'Array(reports.prefix(3))' "$R/appsrc/NextReminder/Sources/FileSharing.swift"
grep -q 'Gmail login preserved' "$R/appsrc/NextReminder/Sources/FileSharing.swift"
grep -q 'v1/file-shares' "$R/nqrsrc/PendingReportSender.m"
grep -q 'NextReminder.GmailConnection.v1' "$R/nqrsrc/PendingReportSender.m"
grep -q 'NextReminder.BackgroundReportSendEnabled.v1' "$R/nqrsrc/PendingReportSender.m"
grep -q 'Send PDF Report' "$R/nqrsrc/Tweak.xm"

# Text-source archive intentionally does not carry the original asset catalog.
P="$R/appsrc"
mkdir -p "$P/NextReminder/Resources/Assets.xcassets"
printf '%s\n' '{"info":{"author":"xcode","version":1}}' > "$P/NextReminder/Resources/Assets.xcassets/Contents.json"
python3 - <<'PYASSET'
import os,pathlib
p=pathlib.Path(os.environ['RUNNER_TEMP'])/'appsrc/NextReminder.xcodeproj/project.pbxproj'
lines=p.read_text().splitlines()
p.write_text('\n'.join(x for x in lines if 'ASSETCATALOG_COMPILER_APPICON_NAME' not in x and 'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' not in x)+'\n')
PYASSET

xcodebuild -project "$P/NextReminder.xcodeproj" -scheme NextReminder \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$R/DD" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
APP=$(find "$R/DD/Build/Products/Release-iphoneos" -maxdepth 1 -name NextReminder.app -print -quit)
test -n "$APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")" = '1.3.25'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")" = '35'
strings "$APP/NextReminder" > "$R/app.strings"
grep -q 'Background Send' "$R/app.strings"
grep -q 'Latest 3 saved' "$R/app.strings"
grep -q 'Gmail login preserved' "$R/app.strings"
mkdir -p "$R/out/Payload"
cp -R "$APP" "$R/out/Payload/"
(cd "$R/out" && zip -qry NextReminder_1.3.25_Unsigned.tipa Payload)
rm -rf "$R/out/Payload"

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
test "$(dpkg-deb -f "$D" Version)" = '1.0.14'
X=$(mktemp -d)
dpkg-deb -x "$D" "$X"
F=$(find "$X" -name NextQuickReminder.dylib -print -quit)
test -n "$F"
strings -a "$F" > "$R/tweak.strings"
grep -q 'Send PDF Report' "$R/tweak.strings"
grep -q 'v1/file-shares' "$R/tweak.strings"
grep -q 'NextReminder.GmailConnection.v1' "$R/tweak.strings"
grep -q 'PDF report sent' "$R/tweak.strings"
cp "$D" "$R/out/NextQuickReminder_1.0.14_RootHide.deb"
cd "$R/out"
shasum -a 256 NextReminder_1.3.25_Unsigned.tipa NextQuickReminder_1.0.14_RootHide.deb > SHA256SUMS.txt
ls -lh
