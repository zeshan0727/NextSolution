#!/bin/bash
set -euo pipefail

cat NextMediaApp/v141patch.part00 NextMediaApp/v141patch.part01 > NextMediaApp/v141patch.b64

git fetch --depth=1 origin f23b2f08015fdaf04826e147efd1906996824a87
git show FETCH_HEAD:NextMediaApp/build141.sh > /tmp/NextMedia-build143-core.sh

python3 - <<'PY'
from pathlib import Path

path = Path('/tmp/NextMedia-build143-core.sh')
source = path.read_text()

# Reapply the verified 1.4.2 draggable square-player layer.
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

# Add the 1.4.3 live-video, About credit and biometric-lock layer.
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
extra_checks = r'''grep -q 'FloatingVideoPlayerView(player: player.player)' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift
grep -q 'resizeAspectFill' projects/NextMedia/NextMedia/Views/MiniPlayerView.swift
grep -q 'import LocalAuthentication' projects/NextMedia/NextMedia/Services/AppLockManager.swift
grep -q 'deviceOwnerAuthenticationWithBiometrics' projects/NextMedia/NextMedia/Services/AppLockManager.swift
grep -Fq 'Unlock with \(lock.biometricDisplayName)' projects/NextMedia/NextMedia/Views/SettingsView.swift
grep -Fq 'NEXT SOLUTION ~ ZESHAN0727' projects/NextMedia/NextMedia/Views/SettingsView.swift
grep -q 'NSFaceIDUsageDescription' projects/NextMedia/NextMedia/Info.plist
grep -q 'LocalAuthentication.framework' projects/NextMedia/project.yml'''
if validation_anchor not in source:
    raise SystemExit('Could not locate source validation anchor')
source = source.replace(validation_anchor, validation_anchor + "\n" + extra_checks, 1)

source = source.replace(
    "assert 'Zeeshan' not in settings and 'Zeshan' not in settings and '0727' not in settings",
    "assert 'NEXT SOLUTION ~ ZESHAN0727' in settings"
)
source = source.replace("1.4.2", "1.4.3")
source = source.replace("== '8'", "== '9'")
source = source.replace("grep -qx '8'", "grep -qx '9'")

path.write_text(source)
PY

exec bash /tmp/NextMedia-build143-core.sh
