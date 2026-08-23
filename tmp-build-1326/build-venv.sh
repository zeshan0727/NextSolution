#!/bin/bash
set -euo pipefail
cp tmp-build-1326/build.sh "$RUNNER_TEMP/build-1326-real.sh"
python3 - <<'PY'
from pathlib import Path
import os
p=Path(os.environ['RUNNER_TEMP'])/'build-1326-real.sh'
s=p.read_text()
s=s.replace('python3 -m pip install --quiet pillow\npython3 - <<\'PYICON\'', 'python3 -m venv "$R/iconvenv"\n"$R/iconvenv/bin/pip" install --quiet pillow\n"$R/iconvenv/bin/python" - <<\'PYICON\'')
p.write_text(s)
PY
exec bash "$RUNNER_TEMP/build-1326-real.sh"
