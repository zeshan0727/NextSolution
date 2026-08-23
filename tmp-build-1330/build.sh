#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
rm -rf "$R/appsrc" "$R/nqrsrc" "$R/out" "$R/DD" "$R/iconvenv" "$R/theos-rh"
mkdir -p "$R/out"

# ---- Reconstruct exact confirmed-working Next Reminder 1.3.29 source ----
awk '/^ASSETS=/{exit} {print}' tmp-build-1329/build.sh > "$R/reconstruct-app.sh"
bash "$R/reconstruct-app.sh"
P="$R/appsrc"
FILES_SHA=$(shasum -a 256 "$P/NextReminder/Sources/FileSharing.swift" | awk '{print $1}')

# Add only the automatic schedule UI/preferences to PendingReports.swift.
base64 -D < tmp-build-1330/app1330.patch.xz.b64 > "$R/app1330.patch.xz"
xz -dc "$R/app1330.patch.xz" > "$R/app1330.patch"
patch -d "$P" -p1 < "$R/app1330.patch"

# Bump app + Live Activity to 1.3.30 build 40.
python3 - <<'PYVER'
from pathlib import Path
import os,re
root=Path(os.environ['RUNNER_TEMP'])/'appsrc'
pbx=root/'NextReminder.xcodeproj/project.pbxproj'
s=pbx.read_text()
s=re.sub(r'CURRENT_PROJECT_VERSION = 39;', 'CURRENT_PROJECT_VERSION = 40;', s)
s=re.sub(r'MARKETING_VERSION = 1\.3\.29;', 'MARKETING_VERSION = 1.3.30;', s)
pbx.write_text(s)
for rel in ['NextReminder/Resources/Info.plist','NextReminderLiveActivity/Info.plist']:
    p=root/rel
    if p.exists():
        t=p.read_text().replace('<string>1.3.29</string>','<string>1.3.30</string>').replace('<string>39</string>','<string>40</string>')
        p.write_text(t)
PYVER

# Critical regression guard: Files must remain byte-for-byte identical to the working build.
test "$(shasum -a 256 "$P/NextReminder/Sources/FileSharing.swift" | awk '{print $1}')" = "$FILES_SHA"
! grep -q 'PendingReminderPDFReport' "$P/NextReminder/Sources/FileSharing.swift"
grep -q 'NextReminder.PendingReportAutomationEnabled.v1' "$P/NextReminder/Sources/PendingReports.swift"
grep -q 'NextReminder.PendingReportAutomationWeekdays.v1' "$P/NextReminder/Sources/PendingReports.swift"
grep -q 'Automatic Email' "$P/NextReminder/Sources/PendingReports.swift"
grep -q 'reportAutomationChanged' "$P/NextReminder/Sources/PendingReports.swift"

# Restore/compile complete icon catalog exactly as 1.3.29.
ASSETS="$P/NextReminder/Resources/Assets.xcassets"
ICONSET="$ASSETS/AppIcon.appiconset"
mkdir -p "$ICONSET" "$ASSETS/AccentColor.colorset" "$ASSETS/LaunchBackground.colorset"
python3 -m venv "$R/iconvenv"
"$R/iconvenv/bin/pip" install --quiet pillow
"$R/iconvenv/bin/python" - <<'PYICON'
from PIL import Image, ImageDraw
from pathlib import Path
import os,json
root=Path(os.environ['RUNNER_TEMP'])/'appsrc/NextReminder/Resources/Assets.xcassets/AppIcon.appiconset'
root.mkdir(parents=True,exist_ok=True)
S=1024
img=Image.new('RGB',(S,S),(18,18,22)); d=ImageDraw.Draw(img)
for r in range(720,0,-8):
    t=r/720
    col=(int(255-(45*t)), int(103-(45*t)), int(28-(12*t)))
    d.ellipse((S/2-r,S/2-r,S/2+r,S/2+r),fill=col)
d.rounded_rectangle((190,205,834,820),radius=145,fill=(25,25,30),outline=(255,255,255),width=10)
d.ellipse((410,330,614,534),fill=(255,255,255)); d.rounded_rectangle((390,430,634,625),radius=80,fill=(255,255,255)); d.rectangle((365,575,659,625),fill=(255,255,255)); d.ellipse((474,630,550,706),fill=(255,255,255)); d.ellipse((585,560,755,730),fill=(255,116,38),outline=(25,25,30),width=12); d.line((625,645,665,683),fill='white',width=22); d.line((665,683,724,616),fill='white',width=22)
img.save(root/'AppIcon-1024.png',optimize=True)
for size in [40,58,60,80,87,120,180]: img.resize((size,size),Image.Resampling.LANCZOS).save(root/f'AppIcon-{size}.png',optimize=True)
contents={"images":[{"filename":"AppIcon-40.png","idiom":"iphone","scale":"2x","size":"20x20"},{"filename":"AppIcon-60.png","idiom":"iphone","scale":"3x","size":"20x20"},{"filename":"AppIcon-58.png","idiom":"iphone","scale":"2x","size":"29x29"},{"filename":"AppIcon-87.png","idiom":"iphone","scale":"3x","size":"29x29"},{"filename":"AppIcon-80.png","idiom":"iphone","scale":"2x","size":"40x40"},{"filename":"AppIcon-120.png","idiom":"iphone","scale":"3x","size":"40x40"},{"filename":"AppIcon-120.png","idiom":"iphone","scale":"2x","size":"60x60"},{"filename":"AppIcon-180.png","idiom":"iphone","scale":"3x","size":"60x60"},{"filename":"AppIcon-1024.png","idiom":"ios-marketing","scale":"1x","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
(root/'Contents.json').write_text(json.dumps(contents,indent=2)+'\n')
(root.parent/'Contents.json').write_text('{"info":{"author":"xcode","version":1}}\n')
PYICON
cat > "$ASSETS/AccentColor.colorset/Contents.json" <<'EOF2'
{"colors":[],"info":{"author":"xcode","version":1}}
EOF2
cat > "$ASSETS/LaunchBackground.colorset/Contents.json" <<'EOF2'
{"colors":[],"info":{"author":"xcode","version":1}}
EOF2

grep -q 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;' "$P/NextReminder.xcodeproj/project.pbxproj"
xcodebuild -project "$P/NextReminder.xcodeproj" -scheme NextReminder \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$R/DD" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
APP=$(find "$R/DD/Build/Products/Release-iphoneos" -maxdepth 1 -name NextReminder.app -print -quit)
test -n "$APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")" = '1.3.30'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")" = '40'
EXT="$APP/PlugIns/NextReminderLiveActivity.appex/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXT")" = '1.3.30'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXT")" = '40'
test -f "$APP/Assets.car"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIcons' "$APP/Info.plist" >/dev/null
mkdir -p "$R/out/Payload"
cp -R "$APP" "$R/out/Payload/"
(cd "$R/out" && zip -qry NextReminder_1.3.30_Unsigned.tipa Payload)
rm -rf "$R/out/Payload"

# ---- Reconstruct exact Next Quick Reminder 1.0.14 source ----
mkdir -p "$R/nqrsrc"
cat tmp-build/nqr1012/part-* > "$R/nqr.b64"
python3 - <<'PYDEC'
import base64,os,pathlib
r=pathlib.Path(os.environ['RUNNER_TEMP'])
(r/'nqr.tar.xz').write_bytes(base64.b64decode((r/'nqr.b64').read_bytes()))
PYDEC
echo 'eba18cc3ee4117e3e190441ce3533e10613a182aa610a3c92756c72a84cfd757  '"$R/nqr.tar.xz" | shasum -a 256 -c -
tar -xJf "$R/nqr.tar.xz" -C "$R/nqrsrc"
cat tmp-build-1325/patch/tweak-* > "$R/tweak1014.patch.xz.b64"
base64 -D < "$R/tweak1014.patch.xz.b64" > "$R/tweak1014.patch.xz"
xz -dc "$R/tweak1014.patch.xz" > "$R/tweak1014.patch"
patch -d "$R/nqrsrc" -p4 < "$R/tweak1014.patch"

# Apply 1.0.15 fresh-report scheduler patch.
base64 -D < tmp-build-1330/tweak1015.patch.xz.b64 > "$R/tweak1015.patch.xz"
xz -dc "$R/tweak1015.patch.xz" > "$R/tweak1015.patch"
patch -d "$R/nqrsrc" -p1 < "$R/tweak1015.patch"
python3 - <<'PYTWEAKVER'
from pathlib import Path
import os,re
root=Path(os.environ['RUNNER_TEMP'])/'nqrsrc'
p=root/'control'
s=p.read_text()
s=re.sub(r'^Version:\s*1\.0\.14\s*$', 'Version: 1.0.15', s, flags=re.M)
p.write_text(s)
PYTWEAKVER

grep -q 'Version: 1.0.15' "$R/nqrsrc/control"
grep -q 'NextReminder.PendingReportAutomationEnabled.v1' "$R/nqrsrc/PendingReportSender.m"
grep -q 'NextReminderDatabase.json' "$R/nqrsrc/PendingReportSender.m"
grep -q 'reportAutomationLastSuccessDay' "$R/nqrsrc/PendingReportSender.m"
grep -q 'Automatic pending-report scheduler started' "$R/nqrsrc/PendingReportSender.m"
grep -q 'NextQuickReminder-iOS/1.0.15' "$R/nqrsrc/PendingReportSender.m"
grep -q 'NQRStartPendingReportAutomationScheduler' "$R/nqrsrc/Tweak.xm"
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
test "$(dpkg-deb -f "$D" Version)" = '1.0.15'
X=$(mktemp -d)
dpkg-deb -x "$D" "$X"
F=$(find "$X" -name NextQuickReminder.dylib -print -quit)
test -n "$F"
strings -a "$F" > "$R/tweak.strings"
grep -q 'NextReminder.PendingReportAutomationEnabled.v1' "$R/tweak.strings"
grep -q 'NextReminderDatabase.json' "$R/tweak.strings"
grep -q 'Automatic pending-report scheduler started' "$R/tweak.strings"
grep -q 'NextQuickReminder-iOS/1.0.15' "$R/tweak.strings"
grep -q 'v1/file-shares' "$R/tweak.strings"
cp "$D" "$R/out/NextQuickReminder_1.0.15_RootHide.deb"

cd "$R/out"
shasum -a 256 NextReminder_1.3.30_Unsigned.tipa NextQuickReminder_1.0.15_RootHide.deb > SHA256SUMS.txt
ls -lh
cat SHA256SUMS.txt
