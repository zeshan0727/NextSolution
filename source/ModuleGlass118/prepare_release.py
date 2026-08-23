#!/usr/bin/env python3
"""Prepare one independently built Module Glass 1.1.18 package variant."""

from pathlib import Path
import plistlib
import re
import sys


if len(sys.argv) != 3:
    raise SystemExit("usage: prepare_release.py PROJECT_DIR iphoneos-arm64|iphoneos-arm64e")

project = Path(sys.argv[1]).resolve()
architecture = sys.argv[2]
if architecture not in {"iphoneos-arm64", "iphoneos-arm64e"}:
    raise SystemExit(f"unsupported architecture: {architecture}")

bundle = project / "layout/Library/PreferenceBundles/ModuleGlassPrefs.bundle"
root_path = bundle / "CCModuleBackgrounds.plist"
info_path = bundle / "Info.plist"
control_path = project / "control"
for required in (root_path, info_path, control_path):
    if not required.exists():
        raise SystemExit(f"missing release input: {required}")

with root_path.open("rb") as stream:
    root = plistlib.load(stream)
items = list(root.get("items", []))

license_keys = {"licenseStatusDisplay", "licenseDeviceID", "deviceIDDisplay"}
license_actions = {
    "copyLicenseDeviceID",
    "buyLicense",
    "checkActivation",
    "moduleGlassCopyDeviceID:",
    "moduleGlassBuyActivation:",
    "moduleGlassCheckActivation:",
    "moduleGlassRestoreActivation:",
}

cleaned = []
for item in items:
    label = str(item.get("label", "")).strip().upper()
    if item.get("cell") == "PSLinkCell" and label in {"ACTIVATION", "LICENSE & DEVICE"}:
        continue
    if item.get("cell") == "PSGroupCell" and label in {"ACTIVATION", "MODULE GLASS ACTIVATION", "LICENSE & DEVICE"}:
        continue
    if item.get("key") in license_keys or item.get("action") in license_actions:
        continue
    cleaned.append(item)

if len(cleaned) < 31:
    raise SystemExit(f"expected the complete 1.1.17 settings list, found only {len(cleaned)} items")
if cleaned[-1].get("label") != "Respring":
    raise SystemExit("activation must follow the existing final Respring control")

activation_items = [
    {
        "cell": "PSGroupCell",
        "label": "ACTIVATION",
        "footerText": "Module Glass requires a $1 USD lifetime license for this generated Next Solution Device ID. Activation and revocation use the live Next Solution license registry.",
    },
    {
        "cell": "PSTitleValueCell",
        "label": "Status",
        "defaults": "com.nextsolution.moduleglass",
        "key": "licenseStatusDisplay",
        "default": "Unactivated",
    },
    {
        "cell": "PSTitleValueCell",
        "label": "Device ID",
        "defaults": "com.nextsolution.moduleglass",
        "key": "licenseDeviceID",
        "default": "Generating…",
    },
    {"cell": "PSButtonCell", "label": "Copy Device ID", "action": "copyLicenseDeviceID"},
    {"cell": "PSButtonCell", "label": "Buy / Activate — $1.00", "action": "buyLicense"},
    {"cell": "PSButtonCell", "label": "Check Activation", "action": "checkActivation"},
]
root["items"] = cleaned + activation_items
with root_path.open("wb") as stream:
    plistlib.dump(root, stream, fmt=plistlib.FMT_XML, sort_keys=False)

with info_path.open("rb") as stream:
    info = plistlib.load(stream)
info["CFBundleShortVersionString"] = "1.1.18"
info["CFBundleVersion"] = "1.1.18"
with info_path.open("wb") as stream:
    plistlib.dump(info, stream, fmt=plistlib.FMT_XML, sort_keys=False)

control = control_path.read_text()
control = re.sub(r"(?m)^Version:.*$", "Version: 1.1.18", control)
control = re.sub(r"(?m)^Architecture:.*$", f"Architecture: {architecture}", control)
control = re.sub(
    r"(?m)^Description:.*$",
    "Description: Customize Control Center modules with per-module images, blur, opacity, glow, and Volume icon color controls. Version 1.1.18 adds the functional $1 lifetime activation section used by NextLock while preserving the validated Module Glass renderer and settings.",
    control,
)
control = re.sub(
    r"(?m)^Provides:.*$",
    "Provides: com.nextsolution.nextaura.runtime.ccbackgrounds (= 1.1.18)",
    control,
)
control = control.replace("<= 1.1.16", "<= 1.1.17")
control_path.write_text(control)

# The color picker is rebuilt for each package scheme; never reuse the RootHide binary.
legacy_dir = project / "layout/Library/MobileSubstrate/DynamicLibraries"
for name in ("ModuleGlassStandalonePrefsExtension.dylib", "ModuleGlassStandalonePrefsExtension.plist"):
    path = legacy_dir / name
    if path.exists():
        path.unlink()

labels = [item.get("label") for item in root["items"][-6:]]
expected = ["ACTIVATION", "Status", "Device ID", "Copy Device ID", "Buy / Activate — $1.00", "Check Activation"]
if labels != expected:
    raise SystemExit(f"activation section order mismatch: {labels}")
print(f"Prepared Module Glass 1.1.18 for {architecture} with activation after all {len(cleaned)} existing items")
