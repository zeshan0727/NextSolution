#!/usr/bin/env python3
"""Generate the fully native SwiftUI Next Jailbreak app sources."""
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

PUBLIC_REBRAND = {
    b"Next Solution": b"Next Jailbreak",
    b"https://youtube.com/@zeshan0727": b"https://youtube.com/@nextjailbreak",
    b"https://x.com/nextsoluti0n": b"https://x.com/nextjailbreak",
    b"https://instagram.com/nextsolut1on": b"https://instagram.com/nextjailbreak",
}

DESTINATION.mkdir(parents=True, exist_ok=True)
for output_name, payload_names in FILES.items():
    encoded = "".join((PAYLOAD / name).read_text().strip() for name in payload_names)
    source = zlib.decompress(base64.b64decode(encoded))
    for former, current in PUBLIC_REBRAND.items():
        source = source.replace(former, current)
    destination = DESTINATION / output_name
    destination.write_bytes(source)
    print(f"Generated {destination.relative_to(ROOT)} ({len(source)} bytes)")

# Keep the Module Glass companion inside the native app's Downloads section.
# The compressed payload remains the stable base; this patch is intentionally
# applied after generation so future native builds continue to expose the tool.
app_data_path = DESTINATION / "AppData.swift"
app_data = app_data_path.read_text()
module_glass_id = 'id: "module-glass-preview"'
if module_glass_id not in app_data:
    downloads_marker = "    static let downloads: [DownloadItem] = [\n"
    module_glass_download = '''        DownloadItem(\n            id: "module-glass-preview",\n            title: "Module Glass Preview",\n            detail: "Live companion for previewing and changing Module Glass Control Center backgrounds on a TrollStore device.",\n            version: "1.0.0",\n            kind: .app,\n            icon: "square.grid.2x2.fill",\n            url: URL(string: "https://raw.githubusercontent.com/zeshan0727/NextJailbreak/main/NextWebsiteApp/downloads/ModuleGlass-Preview-1.0.0.tipa")!,\n            fileName: "ModuleGlass-Preview-1.0.0.tipa",\n            externalOnly: false\n        ),\n'''
    if downloads_marker not in app_data:
        raise RuntimeError("Could not find AppData.downloads marker")
    app_data = app_data.replace(downloads_marker, downloads_marker + module_glass_download, 1)
    app_data_path.write_text(app_data)
    print("Added Module Glass Preview to native Downloads.")

all_source = b"\n".join((DESTINATION / name).read_bytes() for name in FILES)
assert b"WebKit" not in all_source, "The native app must not contain WebKit"
assert b"WKWebView" not in all_source, "The native app must not contain WKWebView"
assert b"module-glass-preview" in all_source, "Module Glass Preview must be present in Downloads"
for former in PUBLIC_REBRAND:
    assert former not in all_source, f"Former public branding remains in native source: {former!r}"
print("Generated the fully native SwiftUI Next Jailbreak app.")
