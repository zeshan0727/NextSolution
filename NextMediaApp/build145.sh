#!/bin/bash
set -euo pipefail

cat NextMediaApp/v145patch.part00 NextMediaApp/v145patch.part01 > NextMediaApp/v145patch.b64

git fetch --depth=1 origin dea9740ffdb44b9594b7580df3574f579064e01c
git show FETCH_HEAD:NextMediaApp/build144.sh > /tmp/NextMedia-build145-core.sh

python3 - <<'PY'
from pathlib import Path

path = Path('/tmp/NextMedia-build145-core.sh')
source = path.read_text()

needle = "tar -xzf /tmp/NextMedia-v144-patch.tar.gz\n"
addition = r'''

python3 - <<'PY145'
import base64
import hashlib
from pathlib import Path
encoded = Path('NextMediaApp/v145patch.b64').read_text().strip()
archive = base64.b64decode(encoded, validate=True)
expected = 'aaff2db1ac59254fe7d46486faa388560af262b4c6c54087100e89b7ff3e46da'
actual = hashlib.sha256(archive).hexdigest()
if actual != expected:
    raise SystemExit(f'v1.4.5 patch checksum mismatch: {actual}')
Path('/tmp/NextMedia-v145-patch.tar.gz').write_bytes(archive)
PY145
tar -xzf /tmp/NextMedia-v145-patch.tar.gz
'''
if needle not in source:
    raise SystemExit('Could not locate v1.4.4 patch extraction point')
source = source.replace(needle, needle + addition, 1)

validation_anchor = "grep -q 'Show downloadable media' projects/NextMedia/NextMedia/Views/BrowserView.swift"
checks = r'''grep -q 'audiovisualBackgroundPlaybackPolicy = .continuesIfPossible' projects/NextMedia/NextMedia/Services/PlayerManager.swift
grep -q 'activateAudioSession()' projects/NextMedia/NextMedia/Services/PlayerManager.swift
grep -q 'AVAudioSession.interruptionNotification' projects/NextMedia/NextMedia/Services/PlayerManager.swift
grep -q 'canStartPictureInPictureAutomaticallyFromInline = true' projects/NextMedia/NextMedia/Views/PlayerContainerView.swift
grep -q 'isPictureInPicturePossible' projects/NextMedia/NextMedia/Views/PlayerContainerView.swift
grep -q 'restoreUserInterfaceForPictureInPictureStopWithCompletionHandler' projects/NextMedia/NextMedia/Views/PlayerContainerView.swift
grep -q 'restoreFromPictureInPicture' projects/NextMedia/NextMedia/Views/NowPlayingView.swift
grep -q 'video-surface-' projects/NextMedia/NextMedia/Views/NowPlayingView.swift
grep -q 'if phase == .background' projects/NextMedia/NextMedia/NextMediaApp.swift
grep -q 'if player.isPlayerFullscreen' projects/NextMedia/NextMedia/Views/RootView.swift
grep -q 'UIBackgroundModes' projects/NextMedia/NextMedia/Info.plist
if grep -q 'phase == .background || phase == .inactive' projects/NextMedia/NextMedia/NextMediaApp.swift; then
  echo 'Inactive scene transitions must not lock the app during PiP startup'
  exit 1
fi'''
if validation_anchor not in source:
    raise SystemExit('Could not locate source validation anchor')
source = source.replace(validation_anchor, validation_anchor + "\n" + checks, 1)

source = source.replace("1.4.4", "1.4.5")
source = source.replace("== '10'", "== '11'")
source = source.replace("grep -qx '10'", "grep -qx '11'")

path.write_text(source)
PY

exec bash /tmp/NextMedia-build145-core.sh
