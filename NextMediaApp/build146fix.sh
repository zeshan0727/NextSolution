#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
source_path = Path('NextMediaApp/build146.sh')
source = source_path.read_text()
old = "replace_once(settings, 'Text(\"1.4.5\")', 'Text(\"1.4.6\")', 'About version')"
if old not in source:
    raise SystemExit('Could not locate duplicate About version edit')
source = source.replace(old, "pass  # About version is updated by the inherited version step", 1)
Path('/tmp/NextMedia-build146-fixed.sh').write_text(source)
PY

exec bash /tmp/NextMedia-build146-fixed.sh
