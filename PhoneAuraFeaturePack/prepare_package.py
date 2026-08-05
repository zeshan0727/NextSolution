#!/usr/bin/env python3
from __future__ import annotations

import argparse
import plistlib
import re
from pathlib import Path

VERSION = "0.5.0"


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
        "PhoneAura 0.5.0 keeps the existing 0.4.16 design and stable runtime, adds a native-style "
        "contact book/account selector for All Contacts, iCloud, Exchange, Google and contact groups, "
        "and preserves Apple's native call, voicemail, emergency, Dual SIM, Wi-Fi Calling, Bluetooth, "
        "CarPlay, Siri and active-call controllers where supported by the installed iOS version, device, "
        "region and carrier."
    )
    text = re.sub(r"^Description: .*$", f"Description: {description}", text, flags=re.MULTILINE)
    path.write_text(text)


def update_bundle_info(path: Path) -> None:
    info = load_plist(path)
    info["CFBundleShortVersionString"] = VERSION
    info["CFBundleVersion"] = "60"
    save_plist(path, info)


def update_root(path: Path) -> None:
    root = load_plist(path)
    if root and isinstance(root[0], dict):
        root[0]["label"] = "PHONEAURA 0.5.0"
        root[0]["footerText"] = (
            "PhoneAura 0.5.0 keeps the current design and stable 0.4.16 runtime. "
            "It adds contact-book/account selection while Apple continues to handle native calling services."
        )

    existing_keys = {row.get("key") for row in root if isinstance(row, dict)}
    if "contactBookSelector" not in existing_keys:
        insert_at = len(root)
        for index, row in enumerate(root):
            if isinstance(row, dict) and row.get("label") == "APPEARANCE":
                insert_at = index
                break
        additions = [
            {
                "cell": "PSGroupCell",
                "label": "CONTACT BOOKS",
                "footerText": (
                    "Shows a native-style selector in the existing PhoneAura Contacts header. "
                    "Choose All Contacts, an account such as iCloud or Google, or a contact group/list."
                ),
            },
            {
                "cell": "PSSwitchCell",
                "default": True,
                "defaults": "com.zeshan.phoneaura",
                "key": "contactBookSelector",
                "label": "Contact Book Selector",
                "PostNotification": "com.zeshan.phoneaura/preferences.changed",
            },
        ]
        root[insert_at:insert_at] = additions

    if root and isinstance(root[-1], dict) and root[-1].get("cell") == "PSGroupCell":
        root[-1]["footerText"] = (
            "Restart the Phone app after changing complete tab replacements or the Contact Book Selector. "
            "Native Phone features remain subject to iOS version, iPhone model, carrier, language and region."
        )
    save_plist(path, root)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("layout", type=Path)
    parser.add_argument("--root-prefix", default="")
    args = parser.parse_args()

    layout = args.layout
    prefix = layout / args.root_prefix if args.root_prefix else layout
    update_control(layout / "DEBIAN" / "control")
    update_bundle_info(prefix / "Library" / "PreferenceBundles" / "PhoneAuraPrefs.bundle" / "Info.plist")
    update_bundle_info(prefix / "Applications" / "PhoneAuraStudio.app" / "Info.plist")
    update_root(prefix / "Library" / "PreferenceBundles" / "PhoneAuraPrefs.bundle" / "Root.plist")


if __name__ == "__main__":
    main()
