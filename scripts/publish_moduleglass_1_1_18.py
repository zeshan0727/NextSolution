#!/usr/bin/env python3
"""Publish the validated Module Glass 1.1.18 packages into an APT repository."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from email.utils import format_datetime
import hashlib
from pathlib import Path
import re


PACKAGE = "com.nextsolution.nextaura.cc-module-backgrounds"
VERSION = "1.1.18"
DESCRIPTION = (
    "Customize Control Center modules with per-module images, blur, opacity, glow, "
    "and Volume icon color controls. Version 1.1.18 adds the functional $1 lifetime "
    "activation section used by NextLock while preserving the validated Module Glass "
    "renderer and settings."
)
VARIANTS = (
    (
        "Rootless",
        "iphoneos-arm64",
        "ModuleGlass_1.1.18_Rootless.deb",
        "da89ebce4bc808e056b2fafd2495c95aeb44da24e14a8796614dc0e5cc2c92eb",
    ),
    (
        "RootHide",
        "iphoneos-arm64e",
        "ModuleGlass_1.1.18_RootHide.deb",
        "c654ce526113dcc3aabcb4b7a99376d30c9ca53e539b9db56f8c67f10aa35cb7",
    ),
)


def digest(path: Path, algorithm: str) -> str:
    value = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def field(block: str, name: str) -> str | None:
    match = re.search(rf"(?m)^{re.escape(name)}:\s*(.+)$", block)
    return match.group(1).strip() if match else None


def stanza(root: Path, architecture: str, filename: str, expected_sha256: str) -> str:
    package_path = root / "debfiles" / filename
    if not package_path.is_file():
        raise SystemExit(f"missing package: {package_path}")
    sha256 = digest(package_path, "sha256")
    if sha256 != expected_sha256:
        raise SystemExit(f"unexpected SHA256 for {filename}: {sha256}")
    return "\n".join(
        (
            f"Package: {PACKAGE}",
            f"Version: {VERSION}",
            f"Architecture: {architecture}",
            "Maintainer: Next Jailbreak",
            "Depends: firmware (>= 16.0), mobilesubstrate, preferenceloader",
            "Provides: com.nextsolution.nextaura.runtime.ccbackgrounds (= 1.1.18)",
            "Conflicts: com.nextsolution.nextaura.runtime.ccbackgrounds (<= 1.1.17), com.nextsolution.unlockvibrate",
            "Breaks: com.nextsolution.nextaura.runtime.ccbackgrounds (<= 1.1.17)",
            "Replaces: com.nextsolution.nextaura.runtime.ccbackgrounds (<= 1.1.17)",
            f"Filename: ./debfiles/{filename}",
            f"Size: {package_path.stat().st_size}",
            f"MD5sum: {digest(package_path, 'md5')}",
            f"SHA1: {digest(package_path, 'sha1')}",
            f"SHA256: {sha256}",
            "Section: Tweaks",
            "Priority: optional",
            "Homepage: https://nextjailbreak.com/",
            f"Description: {DESCRIPTION}",
            "Author: Next Jailbreak",
            "Depiction: https://nextjailbreak.com/depictions/moduleglass.html",
            "Icon: https://nextjailbreak.com/icons/nextaura/cc-module-backgrounds.png",
            "Name: Module Glass",
        )
    )


def update_release(path: Path, should_bump: bool) -> None:
    text = path.read_text()
    if should_bump:
        match = re.search(r"(?m)^Version:\s*(\d+)\.(\d+)\.(\d+)\s*$", text)
        if not match:
            raise SystemExit(f"Release Version not found in {path}")
        major, minor, patch = map(int, match.groups())
        text = text[: match.start()] + f"Version: {major}.{minor}.{patch + 1}" + text[match.end() :]
    now = format_datetime(datetime.now(timezone.utc), usegmt=True)
    if re.search(r"(?m)^Date:.*$", text):
        text = re.sub(r"(?m)^Date:.*$", f"Date: {now}", text)
    else:
        text = text.rstrip() + f"\nDate: {now}\n"
    path.write_text(text)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default=".", help="APT repository root")
    args = parser.parse_args()
    root = Path(args.root).resolve()
    packages_path = root / "Packages"
    release_path = root / "Release"
    if not packages_path.is_file() or not release_path.is_file():
        raise SystemExit(f"not an APT repository: {root}")

    blocks = [block for block in packages_path.read_text().strip().split("\n\n") if block.strip()]
    had_release = any(field(block, "Package") == PACKAGE and field(block, "Version") == VERSION for block in blocks)
    blocks = [
        block
        for block in blocks
        if not (field(block, "Package") == PACKAGE and field(block, "Version") == VERSION)
    ]
    matching = [index for index, block in enumerate(blocks) if field(block, "Package") == PACKAGE]
    insert_at = (matching[-1] + 1) if matching else len(blocks)
    release_stanzas = [stanza(root, architecture, filename, sha256) for _, architecture, filename, sha256 in VARIANTS]
    blocks[insert_at:insert_at] = release_stanzas
    packages_path.write_text("\n\n".join(blocks) + "\n")
    update_release(release_path, should_bump=not had_release)
    print(f"Published Module Glass {VERSION}: Rootless + RootHide in {root}")


if __name__ == "__main__":
    main()
