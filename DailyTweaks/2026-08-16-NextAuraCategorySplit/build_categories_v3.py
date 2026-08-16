#!/usr/bin/env python3
import argparse
import importlib.util
import plistlib
import shutil
import tempfile
from pathlib import Path

from PIL import Image

BASE = Path(__file__).with_name("build_categories_v2.py")
spec = importlib.util.spec_from_file_location("aura_v2", BASE)
v2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v2)

CATEGORY_VERSION = "1.0.2"
PREFS_RUNTIME_VERSION = "1.0.2"
RUNTIME_VERSION = v2.RUNTIME_VERSION
CATEGORIES = v2.CATEGORIES
RUNTIMES = v2.RUNTIMES

# Make imported helpers emit the new metadata.
v2.CATEGORY_VERSION = CATEGORY_VERSION
v2.PREFS_RUNTIME_VERSION = PREFS_RUNTIME_VERSION


def build_preferences_runtime(base_root: Path, out: Path, dynamic_plist: Path, icon_dir: Path, compiled_bundle: Path):
    stage = Path(tempfile.mkdtemp(prefix="aura-prefs-runtime-v102-"))
    try:
        if not compiled_bundle.exists():
            raise FileNotFoundError(compiled_bundle)
        target = stage / "Library" / "PreferenceBundles" / "AuraPrefs.bundle"
        shutil.copytree(compiled_bundle, target, dirs_exist_ok=True)

        original = base_root / "Library" / "PreferenceBundles" / "UnlockVibratePrefs.bundle"
        safe_keys = original / "SafeLabKeys.plist"
        if safe_keys.exists():
            shutil.copy2(safe_keys, target / "SafeLabKeys.plist")

        # Every category page lives beside the principal controller executable.
        for slug, _name, plist_name, _runtimes, _description in CATEGORIES:
            src = dynamic_plist if plist_name == "DynamicIsland" else original / f"{plist_name}.plist"
            if not src.exists():
                raise FileNotFoundError(f"Missing Settings page {plist_name}: {src}")
            shutil.copy2(src, target / f"{plist_name}.plist")

            # PreferenceLoader list icon: deliberately compact (29pt @2x).
            source_icon = icon_dir / f"{slug}.png"
            with Image.open(source_icon) as image:
                compact = image.convert("RGBA").resize((58, 58), Image.Resampling.LANCZOS)
                compact.save(target / f"NextAura-{slug}.png", "PNG", optimize=True)

        info_path = target / "Info.plist"
        with info_path.open("rb") as f:
            info = plistlib.load(f)
        info["CFBundleShortVersionString"] = PREFS_RUNTIME_VERSION
        info["CFBundleVersion"] = PREFS_RUNTIME_VERSION
        info["NSPrincipalClass"] = "AuraCategoryListController"
        with info_path.open("wb") as f:
            plistlib.dump(info, f, sort_keys=False)

        fields = v2.internal_fields(
            v2.runtime_id("preferences"),
            "Aura Preferences Runtime",
            "Internal native category Preferences controller shared by Aura tweaks.",
            PREFS_RUNTIME_VERSION,
        )
        fields["Depends"] = "firmware (>= 16.0), preferenceloader"
        v2.control(stage, fields)
        v2.postinst(stage, False, True)
        deb = out / f"NextAura_Runtime_preferences_{PREFS_RUNTIME_VERSION}_RootHide.deb"
        v2.build(stage, deb)
        return deb
    finally:
        shutil.rmtree(stage, ignore_errors=True)


def build_category(out: Path, item):
    slug, name, plist_name, runtimes, description = item
    stage = Path(tempfile.mkdtemp(prefix=f"aura-category-v102-{slug}-"))
    try:
        loader_dir = stage / "Library" / "PreferenceLoader" / "Preferences"
        loader_dir.mkdir(parents=True, exist_ok=True)
        loader = {
            "entry": {
                "bundle": "AuraPrefs",
                "cell": "PSLinkCell",
                "isController": True,
                "icon": f"NextAura-{slug}.png",
                "label": name,
                "plist": plist_name,
            }
        }
        with (loader_dir / f"NextAura-{slug}.plist").open("wb") as f:
            plistlib.dump(loader, f, sort_keys=False)

        deps = [
            "firmware (>= 16.0)",
            "preferenceloader",
            f"{v2.runtime_id('preferences')} (>= {PREFS_RUNTIME_VERSION})",
        ]
        deps.extend(f"{v2.runtime_id(r)} (>= {RUNTIME_VERSION})" for r in runtimes)
        fields = {
            "Package": v2.package_id(slug),
            "Name": name,
            "Version": CATEGORY_VERSION,
            "Architecture": "iphoneos-arm64e",
            "Description": description,
            "Maintainer": "Next Solution",
            "Author": "Next Solution - zeshan0727",
            "Section": "Tweaks",
            "Depends": ", ".join(deps),
            "Conflicts": v2.OLD_PACKAGE,
            "Priority": "optional",
            "Homepage": v2.HOMEPAGE,
            "Icon": v2.icon_url(slug),
        }
        v2.control(stage, fields)
        v2.postinst(stage, True, True)
        deb = out / f"NextAura_{slug.replace('-', '_')}_{CATEGORY_VERSION}_RootHide.deb"
        v2.build(stage, deb)
        return deb
    finally:
        shutil.rmtree(stage, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-deb", required=True)
    ap.add_argument("--island-dylib", required=True)
    ap.add_argument("--island-plist", required=True)
    ap.add_argument("--dynamic-plist", required=True)
    ap.add_argument("--prefs-bundle", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    icon_dir = v2.generate_icons(out)
    base_root = Path(tempfile.mkdtemp(prefix="aura-base-v102-"))
    try:
        v2.run("dpkg-deb", "-x", Path(args.base_deb).resolve(), base_root)
        dynamic_plist = Path(args.dynamic_plist).resolve()
        pref_runtime = build_preferences_runtime(
            base_root, out, dynamic_plist, icon_dir, Path(args.prefs_bundle).resolve()
        )
        code_runtimes = v2.build_code_runtimes(
            base_root, out, Path(args.island_dylib).resolve(), Path(args.island_plist).resolve()
        )
        category_debs = [build_category(out, item) for item in CATEGORIES]

        manifest = out / "NextAura_Category_Packages.txt"
        with manifest.open("w") as f:
            f.write("Aura modular category packages\n")
            f.write(f"Category version: {CATEGORY_VERSION}\n")
            f.write(f"Code runtime version: {RUNTIME_VERSION}\n")
            f.write(f"Preferences runtime version: {PREFS_RUNTIME_VERSION}\n\n")
            f.write("USER-FACING CATEGORIES\n")
            for item, deb in zip(CATEGORIES, category_debs):
                slug, name, _, _, _ = item
                f.write(f"{name}\n  Package: {v2.package_id(slug)}\n  File: {deb.name}\n  Icon: {v2.icon_url(slug)}\n")
            f.write("\nINTERNAL SHARED RUNTIMES\n")
            f.write(f"Preferences\n  Package: {v2.runtime_id('preferences')}\n  File: {pref_runtime.name}\n")
            for key, deb in zip(RUNTIMES.keys(), code_runtimes):
                f.write(f"{key}\n  Package: {v2.runtime_id(key)}\n  File: {deb.name}\n")
        print("Built Aura 1.0.2: 17 category packages with native Preferences routing and compact Settings icons.")
    finally:
        shutil.rmtree(base_root, ignore_errors=True)


if __name__ == "__main__":
    main()
