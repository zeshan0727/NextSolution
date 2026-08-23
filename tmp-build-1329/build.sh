#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
rm -rf "$R/appsrc" "$R/out" "$R/DD" "$R/iconvenv"
mkdir -p "$R/appsrc" "$R/out"

awk '/# Restore\/compile a complete icon catalog/{exit} {print}' tmp-build-1328/build.sh > "$R/reconstruct-1328.sh"
bash "$R/reconstruct-1328.sh"
P="$R/appsrc"
FILES_SHA=$(shasum -a 256 "$P/NextReminder/Sources/FileSharing.swift" | awk '{print $1}')

cp tmp-build-1329/PendingReports.swift "$P/NextReminder/Sources/PendingReports.swift"
python3 - <<'PYREPORT'
from pathlib import Path
import os
p=Path(os.environ['RUNNER_TEMP'])/'appsrc/NextReminder/Sources/PendingReports.swift'
s=p.read_text()
old='''            if !PendingReportEmailService.isValidEmail(recipient) {\n                NavigationLink {\n                    EmailAutomationSettingsView()\n                } label: {\n                    Label("Set preset email", systemImage: "gearshape.fill")\n                        .font(.subheadline.weight(.semibold))\n                }\n            }\n'''
new='''            if !PendingReportEmailService.isValidEmail(recipient) {\n                Text("Set the default address in Settings → Email Reminder Automations.")\n                    .font(.caption.weight(.medium))\n                    .foregroundStyle(Color.nextOrange)\n            }\n'''
if old in s:
    s=s.replace(old,new,1)
p.write_text(s)
PYREPORT

python3 - <<'PYROOT'
from pathlib import Path
import os
p=Path(os.environ['RUNNER_TEMP'])/'appsrc/NextReminder/Sources/RootReminders.swift'
s=p.read_text()
old='''                emailSchedulesSummary\n                WorkweekPerformanceCard()'''
new='''                emailSchedulesSummary\n                pendingReportsSummary\n                WorkweekPerformanceCard()'''
if old not in s:
    raise SystemExit('Could not insert Pending Reports card')
s=s.replace(old,new,1)
marker='''    private var header: some View {'''
card='''    private var pendingReportsSummary: some View {\n        NavigationLink {\n            PendingReportsView()\n        } label: {\n            HStack(spacing: 13) {\n                ZStack {\n                    RoundedRectangle(cornerRadius: 14, style: .continuous)\n                        .fill(Color.nextOrange.opacity(0.14))\n                    Image(systemName: "doc.text.fill")\n                        .font(.title3.bold())\n                        .foregroundStyle(.nextOrange)\n                }\n                .frame(width: 50, height: 50)\n\n                VStack(alignment: .leading, spacing: 4) {\n                    Text("Pending Reports")\n                        .font(.headline)\n                        .foregroundStyle(.primary)\n                    Text("Generate PDF • Keep latest 3 • Send to preset email")\n                        .font(.caption)\n                        .foregroundStyle(.secondary)\n                }\n                Spacer()\n                Image(systemName: "chevron.right")\n                    .font(.caption.bold())\n                    .foregroundStyle(.secondary)\n            }\n            .padding(14)\n            .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 17, style: .continuous))\n            .overlay(\n                RoundedRectangle(cornerRadius: 17, style: .continuous)\n                    .stroke(Color.nextOrange.opacity(0.18), lineWidth: 1)\n            )\n        }\n        .buttonStyle(.plain)\n    }\n\n'''
if marker not in s:
    raise SystemExit('Could not locate RootReminders header marker')
s=s.replace(marker,card+marker,1)
p.write_text(s)
PYROOT

python3 - <<'PYPBX'
from pathlib import Path
import os
p=Path(os.environ['RUNNER_TEMP'])/'appsrc/NextReminder.xcodeproj/project.pbxproj'
s=p.read_text()
build='A12900000000000000000001'
ref='A12900000000000000000002'
assert build not in s and ref not in s
needle='\t\t5F6B7FEA659424E5D3A21C80 /* FileSharing.swift in Sources */ = {isa = PBXBuildFile; fileRef = EF199847B7956FCE30860684 /* FileSharing.swift */; };\n'
assert needle in s
s=s.replace(needle,needle+f'\t\t{build} /* PendingReports.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* PendingReports.swift */; }};\n',1)
needle='\t\tEF199847B7956FCE30860684 /* FileSharing.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FileSharing.swift; sourceTree = "<group>"; };\n'
assert needle in s
s=s.replace(needle,needle+f'\t\t{ref} /* PendingReports.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PendingReports.swift; sourceTree = "<group>"; }};\n',1)
needle='\t\t\t\tEF199847B7956FCE30860684 /* FileSharing.swift */,\n'
assert needle in s
s=s.replace(needle,needle+f'\t\t\t\t{ref} /* PendingReports.swift */,\n',1)
needle='\t\t\t\t5F6B7FEA659424E5D3A21C80 /* FileSharing.swift in Sources */,\n'
assert needle in s
s=s.replace(needle,needle+f'\t\t\t\t{build} /* PendingReports.swift in Sources */,\n',1)
p.write_text(s)
PYPBX

python3 - <<'PYVER'
from pathlib import Path
import os,re
root=Path(os.environ['RUNNER_TEMP'])/'appsrc'
pbx=root/'NextReminder.xcodeproj/project.pbxproj'
s=pbx.read_text()
s=re.sub(r'CURRENT_PROJECT_VERSION = 38;', 'CURRENT_PROJECT_VERSION = 39;', s)
s=re.sub(r'MARKETING_VERSION = 1\.3\.28;', 'MARKETING_VERSION = 1.3.29;', s)
pbx.write_text(s)
for rel in ['NextReminder/Resources/Info.plist','NextReminderLiveActivity/Info.plist']:
    p=root/rel
    if not p.exists():
        continue
    t=p.read_text().replace('<string>1.3.28</string>','<string>1.3.29</string>').replace('<string>38</string>','<string>39</string>')
    p.write_text(t)
PYVER

test "$(shasum -a 256 "$P/NextReminder/Sources/FileSharing.swift" | awk '{print $1}')" = "$FILES_SHA"
! grep -q 'PendingReminderPDFReport' "$P/NextReminder/Sources/FileSharing.swift"
grep -q 'struct PendingReportsView' "$P/NextReminder/Sources/PendingReports.swift"
grep -q 'Max 3 saved' "$P/NextReminder/Sources/PendingReports.swift"
grep -q 'Pending Reports' "$P/NextReminder/Sources/RootReminders.swift"

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
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")" = '1.3.29'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")" = '39'
EXT="$APP/PlugIns/NextReminderLiveActivity.appex/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXT")" = '1.3.29'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXT")" = '39'
test -f "$APP/Assets.car"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIcons' "$APP/Info.plist" >/dev/null
strings "$APP/NextReminder" > "$R/app.strings"
grep -q 'Pending Reports' "$R/app.strings"
grep -q 'Generate Pending Report' "$R/app.strings"
grep -q 'Max 3 saved' "$R/app.strings"

mkdir -p "$R/out/Payload"
cp -R "$APP" "$R/out/Payload/"
(cd "$R/out" && zip -qry NextReminder_1.3.29_Unsigned.tipa Payload)
rm -rf "$R/out/Payload"
cd "$R/out"
shasum -a 256 NextReminder_1.3.29_Unsigned.tipa > SHA256SUMS.txt
ls -lh
