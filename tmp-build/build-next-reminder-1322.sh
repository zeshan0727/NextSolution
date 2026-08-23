#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
mkdir -p "$R/appsrc" "$R/nqrsrc" "$R/out"
python3 - <<'PY'
from pathlib import Path
p=Path('tmp-build/nr1322xz/part-09')
f=Path('tmp-build/appfix/part09-block6000.txt').read_bytes()
b=bytearray(p.read_bytes())
assert len(b)==10000 and len(f)==500
b[6000:6500]=f
p.write_bytes(b)
PY
cat tmp-build/nr1322xz/part-* > "$R/nr.b64"
cat tmp-build/nqr1012/part-* > "$R/nqr.b64"
python3 - <<'PY'
import base64,os,pathlib
r=pathlib.Path(os.environ['RUNNER_TEMP'])
(r/'nr.tar.xz').write_bytes(base64.b64decode((r/'nr.b64').read_bytes()))
(r/'nqr.tar.xz').write_bytes(base64.b64decode((r/'nqr.b64').read_bytes()))
PY
echo '8334365b7095d7fb3b1cbe92a08a837c097a6ca3b6de7f34765d2541ceaf0046  '"$R/nr.tar.xz" | shasum -a 256 -c -
echo 'eba18cc3ee4117e3e190441ce3533e10613a182aa610a3c92756c72a84cfd757  '"$R/nqr.tar.xz" | shasum -a 256 -c -
tar -xJf "$R/nr.tar.xz" -C "$R/appsrc"
tar -xJf "$R/nqr.tar.xz" -C "$R/nqrsrc"

P="$R/appsrc"
mkdir -p "$P/NextReminder/Resources/Assets.xcassets"
printf '%s\n' '{"info":{"author":"xcode","version":1}}' > "$P/NextReminder/Resources/Assets.xcassets/Contents.json"
python3 - <<'PY'
import os,pathlib
p=pathlib.Path(os.environ['RUNNER_TEMP'])/'appsrc/NextReminder.xcodeproj/project.pbxproj'
s=p.read_text().splitlines()
p.write_text('\n'.join(x for x in s if 'ASSETCATALOG_COMPILER_APPICON_NAME' not in x and 'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' not in x)+'\n')
PY
xcodebuild -project "$P/NextReminder.xcodeproj" -scheme NextReminder -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$R/DD" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
APP=$(find "$R/DD/Build/Products/Release-iphoneos" -maxdepth 1 -name NextReminder.app -print -quit)
test -n "$APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")" = 1.3.22
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")" = 32
grep -R -q 'send-report' "$P/NextReminder/Sources/EmailAutomationCore.swift"
grep -R -q 'sendPendingReport' "$P/NextReminder/Sources/EmailAutomationCore.swift"
mkdir -p "$R/out/Payload"; cp -R "$APP" "$R/out/Payload/"
(cd "$R/out" && zip -qry NextReminder_1.3.22_Unsigned.tipa Payload)
rm -rf "$R/out/Payload"

grep -R -q 'nextreminder://send-report' "$R/nqrsrc"
grep -R -q 'Send Report' "$R/nqrsrc"
brew install dpkg ldid
T="$R/theos-rh"; git init "$T"; git -C "$T" remote add origin https://github.com/roothide/theos.git
git -C "$T" fetch --depth 1 origin 88506b2c22e9e07dd4ed055f23c9e398a117a2c7
git -C "$T" checkout --detach 88506b2c22e9e07dd4ed055f23c9e398a117a2c7
git -C "$T" submodule update --init --recursive --depth 1
export THEOS="$T" THEOS_PACKAGE_SCHEME=roothide
make -C "$R/nqrsrc" clean package FINALPACKAGE=1
D=$(find "$R/nqrsrc/packages" -name '*.deb' -print -quit); test -n "$D"
test "$(dpkg-deb -f "$D" Version)" = 1.0.12
X=$(mktemp -d); dpkg-deb -x "$D" "$X"; F=$(find "$X" -name NextQuickReminder.dylib -print -quit); test -n "$F"
strings -a "$F" | grep -q 'Send Report'
strings -a "$F" | grep -q 'nextreminder://send-report'
cp "$D" "$R/out/NextQuickReminder_1.0.12_RootHide.deb"
cd "$R/out"
shasum -a 256 NextReminder_1.3.22_Unsigned.tipa NextQuickReminder_1.0.12_RootHide.deb > SHA256SUMS.txt
ls -lh
