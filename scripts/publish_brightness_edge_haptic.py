#!/usr/bin/env python3
from pathlib import Path
from datetime import datetime, timezone
import re
import sys

stanzas_path = Path(sys.argv[1])
packages_path = Path("Packages")
old = packages_path.read_text() if packages_path.exists() else ""
rows = [x.strip() for x in re.split(r"\n\s*\n", old) if x.strip()]
rows = [x for x in rows if not re.search(r"^Package: com\.nextsolution\.brightnessedgehaptic$", x, re.M)]
new = [x.strip() for x in re.split(r"\n\s*\n", stanzas_path.read_text()) if x.strip()]
if len(new) != 2:
    raise SystemExit(f"expected two generated package stanzas, got {len(new)}")
packages_path.write_text("\n\n".join(rows + new) + "\n")
release = Path("Release")
if release.exists():
    text = release.read_text()
    stamp = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S UTC")
    text = re.sub(r"^Date: .*$", f"Date: {stamp}", text, flags=re.M)
    release.write_text(text)
