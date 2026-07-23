#!/bin/bash
set -euo pipefail

ROOT="$PWD"
PROJECT="$ROOT/projects/NextMedia"

cat NextMediaApp/source.part00 NextMediaApp/source.part01 NextMediaApp/source.part02 > /tmp/NextMedia-source.b64
python3 - <<'PY'
import base64
from pathlib import Path
encoded = Path('/tmp/NextMedia-source.b64').read_text().strip()
Path('/tmp/NextMedia-project.tar.gz').write_bytes(base64.b64decode(encoded, validate=True))
PY
tar -xzf /tmp/NextMedia-project.tar.gz
python3 projects/NextMedia/ci/generate_icons.py

cp NextMediaPatch/project.yml projects/NextMedia/project.yml
cp -R NextMediaPatch/NextMedia/. projects/NextMedia/NextMedia/
cat NextMediaApp/v12patch.part00 NextMediaApp/v12patch.part01 > /tmp/NextMedia-v12-patch.b64
python3 - <<'PY'
import base64
from pathlib import Path
encoded = Path('/tmp/NextMedia-v12-patch.b64').read_text().strip()
Path('/tmp/NextMedia-v12-patch.tar.gz').write_bytes(base64.b64decode(encoded, validate=True))
PY
tar -xzf /tmp/NextMedia-v12-patch.tar.gz

python3 -m venv /tmp/nextmedia-tools
/tmp/nextmedia-tools/bin/pip install --disable-pip-version-check pillow
/tmp/nextmedia-tools/bin/python NextMediaApp/prepare_v12.py

cat NextMediaApp/v13patch.part00a NextMediaApp/v13patch.part00b NextMediaApp/v13patch.part01 NextMediaApp/v13patch.part02 NextMediaApp/v13patch.part03 > /tmp/NextMedia-v13-patch.b64
python3 - <<'PY'
import base64
import hashlib
from pathlib import Path
encoded = Path('/tmp/NextMedia-v13-patch.b64').read_text().strip()
archive = base64.b64decode(encoded, validate=True)
expected = '5b43fc6819ea143cdba584d43ff57ae682edaf24b11a43e48474487339b2ba4b'
actual = hashlib.sha256(archive).hexdigest()
if actual != expected:
    raise SystemExit(f'v1.3 patch checksum mismatch: {actual}')
Path('/tmp/NextMedia-v13-patch.tar.gz').write_bytes(archive)
PY
tar -xzf /tmp/NextMedia-v13-patch.tar.gz

/tmp/nextmedia-tools/bin/python - <<'PY' | tee projects/NextMedia/icon-step.log
import base64
import hashlib
import json
import plistlib
from pathlib import Path
from PIL import Image

encoded = Path('NextMediaApp/icon131.b64').read_text().strip()
raw = base64.b64decode(encoded, validate=True)
expected = '63fb14a501b661d8a0f49521444771f31c29bfbcf38b679967064fb28e0d6aaa'
actual = hashlib.sha256(raw).hexdigest()
if actual != expected:
    raise SystemExit(f'icon checksum mismatch: {actual}')

source_path = Path('/tmp/NextMedia-glass-icon.jpg')
source_path.write_bytes(raw)
source = Image.open(source_path).convert('RGB')
if source.width != source.height:
    side = min(source.size)
    left = (source.width - side) // 2
    top = (source.height - side) // 2
    source = source.crop((left, top, left + side, top + side))

assets = Path('projects/NextMedia/NextMedia/Resources/Assets.xcassets')
generated = []
for set_name in ('AppIcon.appiconset', 'AppIconDark.appiconset'):
    icon_set = assets / set_name
    manifest_path = icon_set / 'Contents.json'
    if not manifest_path.exists():
        if set_name == 'AppIcon.appiconset':
            raise SystemExit(f'Missing required icon set: {manifest_path}')
        continue
    manifest = json.loads(manifest_path.read_text())
    for entry in manifest.get('images', []):
        filename = entry.get('filename')
        size_text = entry.get('size')
        scale_text = entry.get('scale')
        if not filename or not size_text or not scale_text:
            continue
        points = float(size_text.split('x')[0])
        scale = float(scale_text.rstrip('x'))
        pixels = int(round(points * scale))
        destination = icon_set / filename
        source.resize((pixels, pixels), Image.Resampling.LANCZOS).save(destination, 'PNG', optimize=True)
        generated.append(destination)
if not generated:
    raise SystemExit('No app icon files were generated')

plist_path = Path('projects/NextMedia/NextMedia/Info.plist')
with plist_path.open('rb') as handle:
    info = plistlib.load(handle)
info['CFBundleIconName'] = 'AppIcon'
with plist_path.open('wb') as handle:
    plistlib.dump(info, handle, sort_keys=False)
print(f'icon_sha256={actual}')
print(f'generated_count={len(generated)}')
PY

python3 - <<'PY'
import base64
from pathlib import Path
encoded = Path('NextMediaApp/v14patch.b64').read_text().strip()
Path('/tmp/NextMedia-v14-patch.tar.gz').write_bytes(base64.b64decode(encoded, validate=True))
PY
tar -xzf /tmp/NextMedia-v14-patch.tar.gz

python3 - <<'PY'
import base64
import hashlib
from pathlib import Path
encoded = Path('NextMediaApp/v141patch.b64').read_text().strip()
archive = base64.b64decode(encoded, validate=True)
expected = '501293ffb159c865ef51091f417ef27e3da4af4b1ebf76880e6424deb2851e1d'
actual = hashlib.sha256(archive).hexdigest()
if actual != expected:
    raise SystemExit(f'v1.4.1 patch checksum mismatch: {actual}')
Path('/tmp/NextMedia-v141-patch.tar.gz').write_bytes(archive)
PY
tar -xzf /tmp/NextMedia-v141-patch.tar.gz

grep -q 'onTapGesture(count: 2)' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift
grep -q 'frame(maxWidth: 330)' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift
grep -q 'Stop and close player' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift
grep -q 'safeAreaInsets.bottom + 53' projects/NextMedia/NextMedia/Views/RootView.swift
grep -q 'Minimize to floating player' projects/NextMedia/NextMedia/Views/NowPlayingView.swift
grep -q 'value.translation.height > 100' projects/NextMedia/NextMedia/Views/NowPlayingView.swift
grep -q 'Make MP3' projects/NextMedia/NextMedia/Views/NowPlayingView.swift
grep -q 'Ringtone' projects/NextMedia/NextMedia/Views/NowPlayingView.swift
grep -q 'Show downloadable media' projects/NextMedia/NextMedia/Views/BrowserView.swift
if grep -R -q 'promptedMedia' projects/NextMedia/NextMedia; then
  echo 'Old automatic media prompt code is still present'
  exit 1
fi

python3 - <<'PY'
import plistlib
from pathlib import Path
with Path('projects/NextMedia/NextMedia/Info.plist').open('rb') as handle:
    info = plistlib.load(handle)
assert info['CFBundleShortVersionString'] == '1.4.1', info
assert info['CFBundleVersion'] == '7', info
assert info['CFBundleIconName'] == 'AppIcon', info
settings = Path('projects/NextMedia/NextMedia/Views/SettingsView.swift').read_text()
assert 'Text("1.4.1")' in settings
assert 'Zeeshan' not in settings and 'Zeshan' not in settings and '0727' not in settings
PY

python3 - <<'PY'
from pathlib import Path
encoder = Path('projects/NextMedia/NextMedia/Audio/MP3Encoder.m')
source = encoder.read_text().replace('#import "lame.h"', '#import <LAME/lame.h>')
encoder.write_text(source)
PY

brew install xcodegen
cd "$PROJECT"
xcodegen generate 2>&1 | tee xcodegen.log
xcodebuild -resolvePackageDependencies -project NextMedia.xcodeproj -scheme NextMedia
set -o pipefail
xcodebuild \
  -project NextMedia.xcodeproj \
  -scheme NextMedia \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  clean build | tee xcodebuild.log

APP_PATH="build/Build/Products/Release-iphoneos/NextMedia.app"
test -f "$APP_PATH/Assets.car"
test -f "$APP_PATH/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Info.plist" | grep -qx '1.4.1'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Info.plist" | grep -qx '7'
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP_PATH/Info.plist" | grep -qx 'AppIcon'
test "$(stat -f%z "$APP_PATH/Assets.car")" -gt 50000
grep -q 'MiniPlayerView.swift' xcodebuild.log
grep -q 'RootView.swift' xcodebuild.log
grep -q 'NowPlayingView.swift' xcodebuild.log

rm -rf Payload dist
mkdir -p Payload dist
cp -R "$APP_PATH" Payload/NextMedia.app
/usr/bin/zip -qry "dist/NextMedia-1.4.1.ipa" Payload
cp "dist/NextMedia-1.4.1.ipa" "dist/NextMedia-1.4.1.tipa"
cd "$ROOT"
/usr/bin/zip -qry "projects/NextMedia/dist/NextMedia-1.4.1-source.zip" projects/NextMedia \
  -x 'projects/NextMedia/build/*' 'projects/NextMedia/Payload/*' 'projects/NextMedia/dist/*' 'projects/NextMedia/.build/*'
cd "$PROJECT"
shasum -a 256 dist/NextMedia-1.4.1.ipa dist/NextMedia-1.4.1.tipa dist/NextMedia-1.4.1-source.zip > dist/SHA256SUMS.txt
