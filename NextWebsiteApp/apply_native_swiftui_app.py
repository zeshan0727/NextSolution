#!/usr/bin/env python3
"""Generate the fully native SwiftUI Next Solution app sources."""
from pathlib import Path
import base64
import zlib

ROOT = Path(__file__).resolve().parent
PAYLOAD = ROOT / "native_payload"
DESTINATION = ROOT / "NextSolution"

FILES = {
    "AppData.swift": ["AppData.swift.zlib.b64"],
    "Components.swift": ["Components.swift.zlib.b64"],
    "Models.swift": ["Models.swift.zlib.b64"],
    "NextSolutionApp.swift": ["NextSolutionApp.swift.zlib.b64"],
    "Services.swift": ["Services.swift.zlib.b64"],
    "Views.swift": ["Views.swift.zlib.b64.part1", "Views.swift.zlib.b64.part2"],
}

DESTINATION.mkdir(parents=True, exist_ok=True)
for output_name, payload_names in FILES.items():
    encoded = "".join((PAYLOAD / name).read_text().strip() for name in payload_names)
    source = zlib.decompress(base64.b64decode(encoded))
    destination = DESTINATION / output_name
    destination.write_bytes(source)
    print(f"Generated {destination.relative_to(ROOT)} ({len(source)} bytes)")

all_source = b"\n".join((DESTINATION / name).read_bytes() for name in FILES)
assert b"WebKit" not in all_source, "The native app must not contain WebKit"
assert b"WKWebView" not in all_source, "The native app must not contain WKWebView"
print("Generated the fully native SwiftUI Next Solution app.")
