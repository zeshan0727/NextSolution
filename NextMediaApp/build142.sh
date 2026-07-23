#!/bin/bash
set -euo pipefail

cat NextMediaApp/v141patch.part00 NextMediaApp/v141patch.part01 > NextMediaApp/v141patch.b64

git fetch --depth=1 origin f23b2f08015fdaf04826e147efd1906996824a87
git show FETCH_HEAD:NextMediaApp/build141.sh > /tmp/NextMedia-build142-core.sh

python3 - <<'PY'
from pathlib import Path

path = Path('/tmp/NextMedia-build142-core.sh')
source = path.read_text()

needle = "tar -xzf /tmp/NextMedia-v141-patch.tar.gz\n"
addition = r'''

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
source = source.replace(needle, needle + addition, 1)

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

path.write_text(source)
PY

exec bash /tmp/NextMedia-build142-core.sh
