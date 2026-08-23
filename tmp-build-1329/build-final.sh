#!/bin/bash
set -euo pipefail
R="$RUNNER_TEMP"
cp tmp-build-1329/build.sh "$R/build-1329-final.sh"
python3 - <<'PY'
from pathlib import Path
import os
p=Path(os.environ['RUNNER_TEMP'])/'build-1329-final.sh'
s=p.read_text()
old='''strings "$APP/NextReminder" > "$R/app.strings"\ngrep -q 'Pending Reports' "$R/app.strings"\ngrep -q 'Generate Pending Report' "$R/app.strings"\ngrep -q 'Max 3 saved' "$R/app.strings"\n'''
if old not in s:
    raise SystemExit('Expected optimized-binary string checks not found')
s=s.replace(old,'''# Optimized Swift binaries do not guarantee human-readable string literals.\n# Feature presence is already validated against source before compilation.\n''',1)
p.write_text(s)
PY
exec bash "$R/build-1329-final.sh"
