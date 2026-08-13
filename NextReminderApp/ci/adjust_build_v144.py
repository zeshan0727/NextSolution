#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).with_name("build-v143.sh")
text = path.read_text()
if "python3 ci/patch_v144.py" not in text:
    text = text.replace("python3 ci/patch_v143.py\n", "python3 ci/patch_v143.py\npython3 ci/patch_v144.py\n", 1)
text = text.replace("1.3.13", "1.3.14")
text = text.replace("grep -qx '23'", "grep -qx '24'")
text = text.replace("v1.3.13 build and verification completed", "v1.3.14 build and verification completed")
path.write_text(text)
print("Prepared cumulative v1.3.14 build driver.")
