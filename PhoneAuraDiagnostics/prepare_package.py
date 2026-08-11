#!/usr/bin/env python3
from __future__ import annotations

import argparse
import plistlib
import re
from pathlib import Path

VERSION = "0.5.1"


def load_plist(path: Path):
    with path.open("rb") as handle:
        return plistlib.load(handle)


def save_plist(path: Path, value) -> None:
    with path.open("wb") as handle:
        plistlib.dump(value, handle, fmt=plistlib.FMT_XML, sort_keys=False)


def update_control(path: Path) -> None:
    text = path.read_text()
    text = re.sub(r"^Version: .*$", f"Version: {VERSION}", text, flags=re.MULTILINE)
    description = (
        "PhoneAura 0.5.1 Diagnostic restores the stable 0.4.16 PhoneAura runtime and adds a passive "
        "PhoneAura Console for feature-by-feature diagnosis. The console records runtime loading, preferences, "
        "Favorites, Recents, Contacts, Keypad, tabs, contact permissions, view-controller snapshots, heartbeats "
        "and available MobilePhone crash reports without installing the unstable 0.5.0 contact-book hook."
    )
    text = re.sub(r"^Description: .*$", f"Description: {description}", text, flags=re.MULTILINE)
    path.write_text(text)


def update_bundle_version(path: Path) -> None:
    info = load_plist(path)
    info["CFBundleShortVersionString"] = VERSION
    info["CFBundleVersion"] = "51"
    save_plist(path, info)


def update_root(path: Path) -> None:
    root = load_plist(path)
    if root and isinstance(root[0], dict):
        root[0]["label"] = "PHONEAURA 0.5.1 DIAGNOSTIC"
        root[0]["footerText"] = (
            "Diagnostic recovery build. The unstable 0.5.0 contact-book companion hook is not loaded. "
            "The original stable 0.4.16 PhoneAura runtime is preserved and a separate PhoneAura Console app "
            "collects passive diagnostics for each Phone tab and feature."
        )

    root = [row for row in root if not (isinstance(row, dict) and row.get("key") == "contactBookSelector")]
    root = [row for row in root if not (isinstance(row, dict) and row.get("label") == "CONTACT BOOKS")]
    root.append({
        "cell": "PSGroupCell",
        "label": "DIAGNOSTIC CONSOLE",
        "footerText": (
            "A separate PhoneAura Console app is installed on the Home Screen. Open it, reproduce one PhoneAura issue, "
            "tap the matching feature test, then Share Log and send the report for diagnosis."
        ),
    })
    save_plist(path, root)


def update_scripts(layout: Path) -> None:
    for name in ("postinst", "prerm"):
        path = layout / "DEBIAN" / name
        if not path.exists():
            continue
        text = path.read_text()
        if "PhoneAuraConsole" not in text:
            text = text.replace("exit 0", "killall -9 PhoneAuraConsole 2>/dev/null || true\nexit 0")
        path.write_text(text)
        path.chmod(0o755)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("layout", type=Path)
    parser.add_argument("--root-prefix", default="")
    args = parser.parse_args()

    layout = args.layout
    prefix = layout / args.root_prefix if args.root_prefix else layout
    update_control(layout / "DEBIAN" / "control")
    update_bundle_version(prefix / "Library" / "PreferenceBundles" / "PhoneAuraPrefs.bundle" / "Info.plist")
    update_bundle_version(prefix / "Applications" / "PhoneAuraStudio.app" / "Info.plist")
    update_root(prefix / "Library" / "PreferenceBundles" / "PhoneAuraPrefs.bundle" / "Root.plist")
    update_scripts(layout)


if __name__ == "__main__":
    main()
