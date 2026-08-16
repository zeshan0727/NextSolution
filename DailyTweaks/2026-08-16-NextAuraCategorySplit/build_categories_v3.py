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

CATEGORY_VERSION = "1.0.4"
PREFS_RUNTIME_VERSION = "1.0.4"
RUNTIME_VERSION = v2.RUNTIME_VERSION
RUNTIMES = v2.RUNTIMES

# Keep package IDs and plist names stable so existing modular installs update in-place,
# while user-facing names remain short standalone tweak names.
CATEGORIES = [
    ("feedback", "Pulse", "Feedback", ["feedback"], "Unlock and call-connect vibration feedback."),
    ("thermal-sweat", "Therma", "ThermalSweat", ["thermal"], "Temperature-aware battery visuals, Sweat My Phone effects and battery percentage tools."),
    ("home-screen", "HomeFlow", "HomeScreen", ["springboard", "extended", "safe"], "Home Screen labels, badges, icon sizing, opacity and advanced visual controls."),
    ("dock-folders", "DockCraft", "DockFolders", ["springboard", "safe"], "Dock and folder backgrounds, labels, sizing, opacity and advanced layout controls."),
    ("lock-screen", "LockCraft", "LockScreen", ["springboard", "extended", "safe"], "Lock Screen clock, quick actions, status elements, charging text and notification-list visuals."),
    ("status-bar", "StatusKit", "StatusBar", ["extended", "safe"], "Status Bar visibility, opacity, scale, positioning and individual indicator controls."),
    ("control-center", "ControlKit", "ControlCenter", ["extended", "safe"], "Control Center labels, module sizing, background appearance and advanced stock-layout controls."),
    ("cc-second-page", "Control Deck", "CCSecondPage", ["advanced"], "Second Control Center page with configurable tiles, spacing, information and haptics."),
    ("cc-module-backgrounds", "Module Glass", "CCModuleBackgrounds", ["ccbackgrounds"], "Control Center module backgrounds, blur removal, opacity and control glow effects."),
    ("notification-island", "Notify Island", "DynamicIsland", ["island"], "Notification Island with app icons, privacy, exact-app Open, Dismiss, live preview and layout controls."),
    ("notification-glow", "Notify Glow", "NotificationGlow", ["glow"], "Edge glow, pulse, ripple and lock-screen notification lighting effects."),
    ("now-playing", "NowPlay", "NowPlaying", ["extended", "safe"], "Now Playing artwork, title, artist, controls, opacity, scaling and background appearance."),
    ("notifications", "NotifyKit", "Notifications", ["extended", "safe"], "Stock notification icon, app name, time, buttons, scale, opacity and advanced card appearance."),
    ("app-switcher", "SwitchDeck", "AppSwitcher", ["safe"], "App Switcher card scale, opacity, spacing, labels, icons and background controls."),
    ("system-overlays", "HUDKit", "SystemOverlays", ["safe"], "Screenshot flash/preview controls plus Volume and Ringer HUD visibility options."),
    ("animations", "Motion", "Animations", ["springboard"], "System animation-speed control."),
    ("safety-recovery", "Rescue", "SafetyRecovery", ["safe"], "Crash-guard recovery and reset tools for advanced visual controls."),
]

v2.CATEGORY_VERSION = CATEGORY_VERSION
v2.PREFS_RUNTIME_VERSION = PREFS_RUNTIME_VERSION
v2.CATEGORIES = CATEGORIES


def patch_module_glass_page(path: Path):
    with path.open("rb") as f:
        page = plistlib.load(f)
    items = page.setdefault("items", [])
    # Avoid duplicate buttons when rebuilding locally.
    items = [
        item for item in items
        if item.get("action") not in ("applyCCModuleBackgrounds:", "respringDevice:")
        and item.get("label") != "Apply & Restart"
    ]
    items.extend([
        {
            "cell": "PSGroupCell",
            "label": "Apply & Restart",
            "footerText": "Apply refreshes Module Glass immediately. If Control Center is already cached, use Respring for a complete SpringBoard reload. Choosing a photo automatically enables module backgrounds.",
        },
        {
            "cell": "PSButtonCell",
            "label": "Apply Module Glass",
            "action": "applyCCModuleBackgrounds:",
            "description": "Reloads Module Glass settings and selected images without changing your other tweaks.",
        },
        {
            "cell": "PSButtonCell",
            "label": "Respring",
            "action": "respringDevice:",
            "description": "Restarts SpringBoard so Control Center recreates all module views and reloads their backgrounds.",
        },
    ])
    page["items"] = items
    with path.open("wb") as f:
        plistlib.dump(page, f, sort_keys=False)


def build_preferences_runtime(base_root: Path, out: Path, dynamic_plist: Path, icon_dir: Path, compiled_bundle: Path):
    stage = Path(tempfile.mkdtemp(prefix="aura-prefs-runtime-v104-"))
    try:
        if not compiled_bundle.exists():
            raise FileNotFoundError(compiled_bundle)
        target = stage / "Library" / "PreferenceBundles" / "AuraPrefs.bundle"
        shutil.copytree(compiled_bundle, target, dirs_exist_ok=True)

        original = base_root / "Library" / "PreferenceBundles" / "UnlockVibratePrefs.bundle"
        safe_keys = original / "SafeLabKeys.plist"
        if safe_keys.exists():
            shutil.copy2(safe_keys, target / "SafeLabKeys.plist")

        for slug, _name, plist_name, _runtimes, _description in CATEGORIES:
            src = dynamic_plist if plist_name == "DynamicIsland" else original / f"{plist_name}.plist"
            if not src.exists():
                raise FileNotFoundError(f"Missing Settings page {plist_name}: {src}")
            destination = target / f"{plist_name}.plist"
            shutil.copy2(src, destination)
            if plist_name == "CCModuleBackgrounds":
                patch_module_glass_page(destination)

            source_icon = icon_dir / f"{slug}.png"
            with Image.open(source_icon) as image:
                compact = image.convert("RGBA").resize((29, 29), Image.Resampling.LANCZOS)
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
            "Internal native category Preferences controller shared by modular tweaks.",
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
    stage = Path(tempfile.mkdtemp(prefix=f"aura-category-v104-{slug}-"))
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
    base_root = Path(tempfile.mkdtemp(prefix="aura-base-v104-"))
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
            f.write("Modular tweak category packages\n")
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
        print("Built 1.0.4: 17 standalone category packages with Module Glass storage/apply fixes.")
    finally:
        shutil.rmtree(base_root, ignore_errors=True)


if __name__ == "__main__":
    main()
