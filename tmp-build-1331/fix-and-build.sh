#!/bin/bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
p=Path('tmp-build-1331/build.sh')
s=p.read_text()
old="s=re.sub(r'^Version:\\s*1\\.0\\.15\\s*$','Version: 1.0.16',s,flags=re.M)"
new="s=re.sub(r'^Version:\\s*1\\.0\\.(?:14|15)\\s*$','Version: 1.0.16',s,flags=re.M)"
if old not in s:
    raise SystemExit('version bump expression not found')
p.write_text(s.replace(old,new,1))
PY
exec bash -x tmp-build-1331/build.sh
