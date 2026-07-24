#!/bin/bash
set -euo pipefail

cat NextMediaApp/v146patch.part00 > NextMediaApp/v146patch.b64

git fetch --depth=1 origin d316a61b05b8256ad4e972407c507a0030162633
git show FETCH_HEAD:NextMediaApp/build145.sh > /tmp/NextMedia-build146-core.sh

python3 - <<'PY'
from pathlib import Path

path = Path('/tmp/NextMedia-build146-core.sh')
source = path.read_text()

needle = "tar -xzf /tmp/NextMedia-v145-patch.tar.gz\n"
addition = r'''

python3 - <<'PY146'
import base64
import hashlib
from pathlib import Path
encoded = Path('NextMediaApp/v146patch.b64').read_text().strip()
archive = base64.b64decode(encoded, validate=True)
expected = 'ec020d7595eb7a0c4702273108e8e4a68c1dcff8ed7307ff251ea705034e7968'
actual = hashlib.sha256(archive).hexdigest()
if actual != expected:
    raise SystemExit(f'v1.4.6 patch checksum mismatch: {actual}')
Path('/tmp/NextMedia-v146-patch.tar.gz').write_bytes(archive)
PY146
tar -xzf /tmp/NextMedia-v146-patch.tar.gz

grep -q 'stopPlaybackControl' projects/NextMedia/NextMedia/Views/NowPlayingView.swift
grep -q 'expandedControlButton' projects/NextMedia/NextMedia/Views/NowPlayingView.swift
grep -q 'simultaneousGesture' projects/NextMedia/NextMedia/Views/NowPlayingView.swift
grep -q 'Button(role: .destructive, action: player.stopPlayback)' projects/NextMedia/NextMedia/Views/NowPlayingView.swift
grep -q 'func stopPlayback()' projects/NextMedia/NextMedia/Services/PlayerManager.swift
grep -q 'shouldResumeSavedPosition' projects/NextMedia/NextMedia/Services/PlayerManager.swift
grep -q 'playbackStartModeKey' projects/NextMedia/NextMedia/Services/PlayerManager.swift
grep -q '@AppStorage("playbackStartMode")' projects/NextMedia/NextMedia/Views/SettingsView.swift
grep -Fq 'Resume from Last Position' projects/NextMedia/NextMedia/Views/SettingsView.swift
grep -Fq 'Always Start from Beginning' projects/NextMedia/NextMedia/Views/SettingsView.swift
'''
if needle not in source:
    raise SystemExit('Could not locate v1.4.5 patch extraction point')
source = source.replace(needle, needle + addition, 1)

source = source.replace("1.4.5", "1.4.6")
source = source.replace("== '11'", "== '12'")
source = source.replace("grep -qx '11'", "grep -qx '12'")

path.write_text(source)
PY

exec bash /tmp/NextMedia-build146-core.sh
