#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).with_name("build-v143.sh")
text = path.read_text()
if "python3 ci/patch_v146.py" not in text:
    text = text.replace("python3 ci/patch_v145.py\n", "python3 ci/patch_v145.py\npython3 ci/patch_v146.py\n", 1)
text = text.replace("1.3.15", "1.3.16")
text = text.replace("grep -qx '25'", "grep -qx '26'")
text = text.replace("v1.3.15 build and verification completed", "v1.3.16 build and verification completed")
path.write_text(text)
print("Prepared cumulative v1.3.16 build driver.")
