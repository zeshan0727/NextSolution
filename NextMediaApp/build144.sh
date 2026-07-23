#!/bin/bash
set -euo pipefail

cat NextMediaApp/v141patch.part00 NextMediaApp/v141patch.part01 > NextMediaApp/v141patch.b64
cat NextMediaApp/v143patch.part00 NextMediaApp/v143patch.part01 NextMediaApp/v143patch.part02 NextMediaApp/v143patch.part03 NextMediaApp/v143patch.part04 > NextMediaApp/v143patch.b64
cat NextMediaApp/v144patch.part00 NextMediaApp/v144patch.part01 NextMediaApp/v144patch.part02 > NextMediaApp/v144patch.b64

git fetch --depth=1 origin f23b2f08015fdaf04826e147efd1906996824a87
git show FETCH_HEAD:NextMediaApp/build141.sh > /tmp/NextMedia-build144-core.sh

python3 - <<'PY'
from pathlib import Path

path = Path('/tmp/NextMedia-build144-core.sh')
source = path.read_text()

needle = "tar -xzf /tmp/NextMedia-v141-patch.tar.gz\n"
addition142 = r'''

python3 - <<'PY142'
import base64
import hashlib
from pathlib import Path
encoded = Path('NextMediaApp/v142patch.b64').read_text().strip()
archive = base64.b64decode(encoded, validate=True)
expected = 'e0042d5197cceb8557e9326392fa00545f88f41828a2e496190d78ce4cd6f51f'
actual = hashlib.sha256(archive).hexdigest()
if actual != expected:
    raise SystemExit(f'v1.4.2 patch checksum mismatch: {actual}')
Path('/tmp/NextMedia-v142-patch.tar.gz').write_bytes(archive)
PY142
tar -xzf /tmp/NextMedia-v142-patch.tar.gz
'''
if needle not in source:
    raise SystemExit('Could not locate v1.4.1 patch extraction point')
source = source.replace(needle, needle + addition142, 1)

source = source.replace(
    "grep -q 'frame(maxWidth: 330)' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift",
    "grep -q 'frame(width: size, height: size)' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift\n"
    "grep -q '@AppStorage(\"floatingPlayerPositionX\")' projects/NextMedia/NextMedia/Views/RootView.swift\n"
    "grep -q 'DragGesture(minimumDistance: 7' projects/NextMedia/NextMedia/Views/RootView.swift\n"
    "grep -q 'saveFloatingPlayerPosition' projects/NextMedia/NextMedia/Views/RootView.swift"
)
source = source.replace(
    "grep -q 'safeAreaInsets.bottom + 53' projects/NextMedia/NextMedia/Views/RootView.swift",
    "grep -q 'tabBarClearance: CGFloat = 57' projects/NextMedia/NextMedia/Views/RootView.swift"
)
source = source.replace("1.4.1", "1.4.2")
source = source.replace("== '7'", "== '8'")
source = source.replace("grep -qx '7'", "grep -qx '8'")

needle143 = "tar -xzf /tmp/NextMedia-v142-patch.tar.gz\n"
addition143 = r'''

python3 - <<'PY143'
import base64
import hashlib
from pathlib import Path
encoded = Path('NextMediaApp/v143patch.b64').read_text().strip()
archive = base64.b64decode(encoded, validate=True)
expected = '60d10f4c2db5bddd15fc53b0a30041208bd70f5ed22671d749fd18df0ed2f745'
actual = hashlib.sha256(archive).hexdigest()
if actual != expected:
    raise SystemExit(f'v1.4.3 patch checksum mismatch: {actual}')
Path('/tmp/NextMedia-v143-patch.tar.gz').write_bytes(archive)
PY143
tar -xzf /tmp/NextMedia-v143-patch.tar.gz
'''
if needle143 not in source:
    raise SystemExit('Could not locate v1.4.2 patch extraction point')
source = source.replace(needle143, needle143 + addition143, 1)

validation_anchor = "grep -q 'Show downloadable media' projects/NextMedia/NextMedia/Views/BrowserView.swift"
checks143 = r'''grep -q 'FloatingVideoPlayerView(player: player.player)' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift
grep -q 'resizeAspectFill' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift
grep -q 'import LocalAuthentication' projects/NextMedia/NextMedia/Services/AppLockManager.swift
grep -q 'deviceOwnerAuthenticationWithBiometrics' projects/NextMedia/NextMedia/Services/AppLockManager.swift
grep -Fq 'Unlock with \(lock.biometricDisplayName)' projects/NextMedia/NextMedia/Views/SettingsView.swift
grep -Fq 'NEXT SOLUTION ~ ZESHAN0727' projects/NextMedia/NextMedia/Views/SettingsView.swift
grep -q 'NSFaceIDUsageDescription' projects/NextMedia/NextMedia/Info.plist
grep -q 'LocalAuthentication.framework' projects/NextMedia/project.yml'''
if validation_anchor not in source:
    raise SystemExit('Could not locate source validation anchor')
source = source.replace(validation_anchor, validation_anchor + "\n" + checks143, 1)

source = source.replace(
    "assert 'Zeeshan' not in settings and 'Zeshan' not in settings and '0727' not in settings",
    "assert 'NEXT SOLUTION ~ ZESHAN0727' in settings"
)
source = source.replace("1.4.2", "1.4.3")
source = source.replace("== '8'", "== '9'")
source = source.replace("grep -qx '8'", "grep -qx '9'")

needle144 = "tar -xzf /tmp/NextMedia-v143-patch.tar.gz\n"
addition144 = r'''

python3 - <<'PY144'
import base64
import hashlib
from pathlib import Path
encoded = Path('NextMediaApp/v144patch.b64').read_text().strip()
archive = base64.b64decode(encoded, validate=True)
expected = '5821b973f318d2134563c55530ea37d9c8f41abd400336be2278e5699ce23f64'
actual = hashlib.sha256(archive).hexdigest()
if actual != expected:
    raise SystemExit(f'v1.4.4 patch checksum mismatch: {actual}')
Path('/tmp/NextMedia-v144-patch.tar.gz').write_bytes(archive)
PY144
tar -xzf /tmp/NextMedia-v144-patch.tar.gz
'''
if needle144 not in source:
    raise SystemExit('Could not locate v1.4.3 patch extraction point')
source = source.replace(needle144, needle144 + addition144, 1)

checks144 = r'''grep -q '@State private var controlsVisible = true' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift
grep -q 'autoHideDelay: TimeInterval = 3.0' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift
grep -q 'ExclusiveGesture' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift
grep -q 'TapGesture(count: 2)' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift
grep -q 'TapGesture(count: 1)' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift
grep -q 'scheduleAutoHideIfNeeded' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift
grep -q 'onChange(of: player.isPlaying)' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift
grep -Fq 'Single tap to show or hide controls. Double tap to open the full player.' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift'''
source = source.replace(checks143, checks143 + "\n" + checks144, 1)
source = source.replace(
    "grep -q 'onTapGesture(count: 2)' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift",
    "grep -q 'TapGesture(count: 2)' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift"
)
source = source.replace("1.4.3", "1.4.4")
source = source.replace("== '9'", "== '10'")
source = source.replace("grep -qx '9'", "grep -qx '10'")

path.write_text(source)
PY

exec bash /tmp/NextMedia-build144-core.sh
