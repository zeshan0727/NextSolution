#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
rm -rf "$R/appsrc" "$R/out" "$R/DD" "$R/iconvenv"
mkdir -p "$R/appsrc" "$R/out"

# Reconstruct the verified pre-report app source (1.3.22 base).
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
python3 - <<'PYDEC'
import base64,os,pathlib
r=pathlib.Path(os.environ['RUNNER_TEMP'])
(r/'nr.tar.xz').write_bytes(base64.b64decode((r/'nr.b64').read_bytes()))
PYDEC
echo '8334365b7095d7fb3b1cbe92a08a837c097a6ca3b6de7f34765d2541ceaf0046  '"$R/nr.tar.xz" | shasum -a 256 -c -
tar -xJf "$R/nr.tar.xz" -C "$R/appsrc"

# Save the exact stable Files implementation before any report/PDF changes.
cp "$R/appsrc/NextReminder/Sources/FileSharing.swift" "$R/FileSharing.stable.swift"
STABLE_SHA=$(shasum -a 256 "$R/FileSharing.stable.swift" | awk '{print $1}')
echo "Stable Files SHA: $STABLE_SHA"

# Apply the already-validated 1.3.25 and 1.3.26 changes to the rest of the app.
cat tmp-build-1325/patch/app-* > "$R/app1325.patch.xz.b64"
base64 -D < "$R/app1325.patch.xz.b64" > "$R/app1325.patch.xz"
xz -dc "$R/app1325.patch.xz" > "$R/app1325.patch"
patch -d "$R/appsrc" -p4 < "$R/app1325.patch"

base64 -D < tmp-build-1326/app1326.patch.xz.b64 > "$R/app1326.patch.xz"
echo 'd6eb26cdea30b5fbd9ced4877a06cf5af2e9039cc7389bf343c834ddfea443c3  '"$R/app1326.patch.xz" | shasum -a 256 -c -
xz -dc "$R/app1326.patch.xz" > "$R/app1326.patch"
patch -d "$R/appsrc" -p1 < "$R/app1326.patch"

# Stability-first rollback: restore the entire Files/File Sharing source exactly.
cp "$R/FileSharing.stable.swift" "$R/appsrc/NextReminder/Sources/FileSharing.swift"
test "$(shasum -a 256 "$R/appsrc/NextReminder/Sources/FileSharing.swift" | awk '{print $1}')" = "$STABLE_SHA"
! grep -q 'PendingReminderPDFReport' "$R/appsrc/NextReminder/Sources/FileSharing.swift"
! grep -q 'BackgroundReportSendEnabled' "$R/appsrc/NextReminder/Sources/FileSharing.swift"

P="$R/appsrc"

# Bump host + Live Activity to 1.3.28 build 38.
python3 - <<'PYVER'
from pathlib import Path
import os,re
root=Path(os.environ['RUNNER_TEMP'])/'appsrc'
pbx=root/'NextReminder.xcodeproj/project.pbxproj'
s=pbx.read_text()
s=re.sub(r'CURRENT_PROJECT_VERSION = \d+;', 'CURRENT_PROJECT_VERSION = 38;', s)
s=re.sub(r'MARKETING_VERSION = [0-9.]+;', 'MARKETING_VERSION = 1.3.28;', s)
pbx.write_text(s)
for rel in ['NextReminder/Resources/Info.plist','NextReminderLiveActivity/Info.plist']:
    p=root/rel
    if not p.exists():
        continue
    t=p.read_text()
    t=t.replace('<key>CFBundleShortVersionString</key>\n\t<string>1.3.26</string>', '<key>CFBundleShortVersionString</key>\n\t<string>1.3.28</string>')
    t=t.replace('<key>CFBundleVersion</key>\n\t<string>36</string>', '<key>CFBundleVersion</key>\n\t<string>38</string>')
    t=t.replace('<string>1.3.26</string>', '<string>1.3.28</string>')
    t=t.replace('<string>36</string>', '<string>38</string>')
    p.write_text(t)
PYVER

# Restore/compile a complete icon catalog (the 1.3.26 icon fix).
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
cat > "$ASSETS/AccentColor.colorset/Contents.json" <<'EOF'
{"colors":[],"info":{"author":"xcode","version":1}}
EOF
cat > "$ASSETS/LaunchBackground.colorset/Contents.json" <<'EOF'
{"colors":[],"info":{"author":"xcode","version":1}}
EOF

grep -q 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;' "$P/NextReminder.xcodeproj/project.pbxproj"

xcodebuild -project "$P/NextReminder.xcodeproj" -scheme NextReminder \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$R/DD" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build

APP=$(find "$R/DD/Build/Products/Release-iphoneos" -maxdepth 1 -name NextReminder.app -print -quit)
test -n "$APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")" = '1.3.28'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")" = '38'
EXT="$APP/PlugIns/NextReminderLiveActivity.appex/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXT")" = '1.3.28'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXT")" = '38'
test -f "$APP/Assets.car"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIcons' "$APP/Info.plist" >/dev/null
strings "$APP/NextReminder" > "$R/app.strings"
! grep -q 'Latest 3 saved' "$R/app.strings"
! grep -q 'Pending Reminder Report' "$R/app.strings"

mkdir -p "$R/out/Payload"
cp -R "$APP" "$R/out/Payload/"
(cd "$R/out" && zip -qry NextReminder_1.3.28_Unsigned.tipa Payload)
rm -rf "$R/out/Payload"
cd "$R/out"
shasum -a 256 NextReminder_1.3.28_Unsigned.tipa > SHA256SUMS.txt
ls -lh
