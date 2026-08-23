#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
rm -rf "$R/appsrc" "$R/out" "$R/DD"
mkdir -p "$R/appsrc" "$R/out"

# Reconstruct the previously verified app source.
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

# Apply the validated 1.3.25 app changes first.
cat tmp-build-1325/patch/app-* > "$R/app1325.patch.xz.b64"
base64 -D < "$R/app1325.patch.xz.b64" > "$R/app1325.patch.xz"
xz -dc "$R/app1325.patch.xz" > "$R/app1325.patch"
patch -d "$R/appsrc" -p4 < "$R/app1325.patch"

# Apply 1.3.26: Files freeze fix + version bump.
base64 -D < tmp-build-1326/app1326.patch.xz.b64 > "$R/app1326.patch.xz"
echo 'd6eb26cdea30b5fbd9ced4877a06cf5af2e9039cc7389bf343c834ddfea443c3  '"$R/app1326.patch.xz" | shasum -a 256 -c -
xz -dc "$R/app1326.patch.xz" > "$R/app1326.patch"
patch -d "$R/appsrc" -p1 < "$R/app1326.patch"

P="$R/appsrc"
ASSETS="$P/NextReminder/Resources/Assets.xcassets"
ICONSET="$ASSETS/AppIcon.appiconset"
mkdir -p "$ICONSET" "$ASSETS/AccentColor.colorset" "$ASSETS/LaunchBackground.colorset"

# Generate a complete native Next Reminder icon set so future test builds cannot lose the icon.
python3 -m pip install --quiet pillow
python3 - <<'PYICON'
from PIL import Image, ImageDraw
from pathlib import Path
import os, json
root=Path(os.environ['RUNNER_TEMP'])/'appsrc/NextReminder/Resources/Assets.xcassets/AppIcon.appiconset'
root.mkdir(parents=True,exist_ok=True)
S=1024
img=Image.new('RGB',(S,S),(18,18,22))
d=ImageDraw.Draw(img)
for r in range(720,0,-8):
    t=r/720
    col=(int(255-(45*t)), int(103-(45*t)), int(28-(12*t)))
    box=(S/2-r,S/2-r,S/2+r,S/2+r)
    d.ellipse(box,fill=col)
card=(190,205,834,820)
d.rounded_rectangle(card,radius=145,fill=(25,25,30),outline=(255,255,255),width=10)
d.ellipse((410,330,614,534),fill=(255,255,255))
d.rounded_rectangle((390,430,634,625),radius=80,fill=(255,255,255))
d.rectangle((365,575,659,625),fill=(255,255,255))
d.ellipse((474,630,550,706),fill=(255,255,255))
d.ellipse((585,560,755,730),fill=(255,116,38),outline=(25,25,30),width=12)
d.line((625,645,665,683),fill='white',width=22)
d.line((665,683,724,616),fill='white',width=22)
base=root/'AppIcon-1024.png'
img.save(base,optimize=True)
for size in [40,58,60,80,87,120,180]:
    img.resize((size,size),Image.Resampling.LANCZOS).save(root/f'AppIcon-{size}.png',optimize=True)
contents={"images":[
 {"filename":"AppIcon-40.png","idiom":"iphone","scale":"2x","size":"20x20"},
 {"filename":"AppIcon-60.png","idiom":"iphone","scale":"3x","size":"20x20"},
 {"filename":"AppIcon-58.png","idiom":"iphone","scale":"2x","size":"29x29"},
 {"filename":"AppIcon-87.png","idiom":"iphone","scale":"3x","size":"29x29"},
 {"filename":"AppIcon-80.png","idiom":"iphone","scale":"2x","size":"40x40"},
 {"filename":"AppIcon-120.png","idiom":"iphone","scale":"3x","size":"40x40"},
 {"filename":"AppIcon-120.png","idiom":"iphone","scale":"2x","size":"60x60"},
 {"filename":"AppIcon-180.png","idiom":"iphone","scale":"3x","size":"60x60"},
 {"filename":"AppIcon-1024.png","idiom":"ios-marketing","scale":"1x","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
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
grep -q 'isLoadingPendingReports' "$P/NextReminder/Sources/FileSharing.swift"
grep -q 'DispatchQueue.global(qos: .utility)' "$P/NextReminder/Sources/FileSharing.swift"
! grep -A8 -F 'private func generatePendingReminderPDF()' "$P/NextReminder/Sources/FileSharing.swift" | grep -q 'refreshFromDisk()'

xcodebuild -project "$P/NextReminder.xcodeproj" -scheme NextReminder \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$R/DD" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
APP=$(find "$R/DD/Build/Products/Release-iphoneos" -maxdepth 1 -name NextReminder.app -print -quit)
test -n "$APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")" = '1.3.26'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")" = '36'
EXT="$APP/PlugIns/NextReminderLiveActivity.appex/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXT")" = '36'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXT")" = '1.3.26'
test -f "$APP/Assets.car"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIcons' "$APP/Info.plist" >/dev/null

mkdir -p "$R/out/Payload"
cp -R "$APP" "$R/out/Payload/"
(cd "$R/out" && zip -qry NextReminder_1.3.26_Unsigned.tipa Payload)
rm -rf "$R/out/Payload"
cd "$R/out"
shasum -a 256 NextReminder_1.3.26_Unsigned.tipa > SHA256SUMS.txt
ls -lh
