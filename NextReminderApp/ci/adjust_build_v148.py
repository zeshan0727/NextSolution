#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).with_name("build-v143.sh")
text = path.read_text()
if "python3 ci/patch_v148.py" not in text:
    text = text.replace("python3 ci/patch_v147.py\n", "python3 ci/patch_v147.py\npython3 ci/patch_v148.py\n", 1)
text = text.replace("1.3.17", "1.3.18")
text = text.replace("grep -qx '27'", "grep -qx '28'")
text = text.replace("v1.3.17 build and verification completed", "v1.3.18 build and verification completed")
path.write_text(text)
print("Prepared cumulative v1.3.18 build driver.")
