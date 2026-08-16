#!/usr/bin/env python3
import argparse
import os
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

VERSION = "1.0.0"
RUNTIME_VERSION = "1.0.0"
DOMAIN = "com.nextsolution.unlockvibrate"
HOMEPAGE = "https://nextsolution.cc/"
ICON = "https://nextsolution.cc/CydiaIcon.png"

CATEGORIES = [
    {
        "slug": "feedback",
        "name": "Vibration Feedback",
        "plist": "Feedback",
        "runtimes": ["feedback"],
        "description": "Unlock and call-connect vibration feedback from NextAura.",
    },
    {
        "slug": "thermal-sweat",
        "name": "Temperature & Sweat",
        "plist": "ThermalSweat",
        "runtimes": ["thermal"],
        "description": "Temperature-aware battery visuals, Sweat My Phone effects and battery percentage tools.",
    },
    {
        "slug": "home-screen",
        "name": "Home Screen & Icons",
        "plist": "HomeScreen",
        "runtimes": ["springboard", "extended", "safe"],
        "description": "Home Screen labels, badges, icon sizing, opacity and advanced visual controls.",
    },
    {
        "slug": "dock-folders",
        "name": "Dock & Folders",
        "plist": "DockFolders",
        "runtimes": ["springboard", "safe"],
        "description": "Dock and folder backgrounds, labels, sizing, opacity and advanced layout controls.",
    },
    {
        "slug": "lock-screen",
        "name": "Lock Screen",
        "plist": "LockScreen",
        "runtimes": ["springboard", "extended", "safe"],
        "description": "Lock Screen clock, quick actions, status elements, charging text and notification-list visuals.",
    },
    {
        "slug": "status-bar",
        "name": "Status Bar",
        "plist": "StatusBar",
        "runtimes": ["extended", "safe"],
        "description": "Status Bar visibility, opacity, scale, positioning and individual indicator controls.",
    },
    {
        "slug": "control-center",
        "name": "Control Center Appearance",
        "plist": "ControlCenter",
        "runtimes": ["extended", "safe"],
        "description": "Control Center labels, module sizing, background appearance and advanced stock-layout controls.",
    },
    {
        "slug": "cc-second-page",
        "name": "Second Page & Controls",
        "plist": "CCSecondPage",
        "runtimes": ["advanced"],
        "description": "NextAura second Control Center page with configurable tiles, spacing, information and haptics.",
    },
    {
        "slug": "cc-module-backgrounds",
        "name": "Module Backgrounds",
        "plist": "CCModuleBackgrounds",
        "runtimes": ["ccbackgrounds"],
        "description": "Control Center module backgrounds, blur removal, opacity and control glow effects.",
    },
    {
        "slug": "notification-island",
        "name": "Notification Island",
        "plist": "DynamicIsland",
        "runtimes": ["island"],
        "description": "NextAura notification island with app icons, privacy, Open/Dismiss actions, live preview and layout controls.",
    },
    {
        "slug": "notification-glow",
        "name": "Notification Glow",
        "plist": "NotificationGlow",
        "runtimes": ["glow"],
        "description": "Edge glow, pulse, ripple and lock-screen notification lighting effects.",
    },
    {
        "slug": "now-playing",
        "name": "Now Playing",
        "plist": "NowPlaying",
        "runtimes": ["extended", "safe"],
        "description": "Now Playing artwork, title, artist, controls, opacity, scaling and background appearance.",
    },
    {
        "slug": "notifications",
        "name": "Notifications",
        "plist": "Notifications",
        "runtimes": ["extended", "safe"],
        "description": "Stock notification icon, app name, time, buttons, scale, opacity and advanced card appearance.",
    },
    {
        "slug": "app-switcher",
        "name": "App Switcher",
        "plist": "AppSwitcher",
        "runtimes": ["safe"],
        "description": "App Switcher card scale, opacity, spacing, labels, icons and background controls.",
    },
    {
        "slug": "system-overlays",
        "name": "Screenshots & HUDs",
        "plist": "SystemOverlays",
        "runtimes": ["safe"],
        "description": "Screenshot flash/preview controls plus Volume and Ringer HUD visibility options.",
    },
    {
        "slug": "animations",
        "name": "Animations",
        "plist": "Animations",
        "runtimes": ["springboard"],
        "description": "System animation-speed control from the NextAura suite.",
    },
    {
        "slug": "safety-recovery",
        "name": "Safety & Recovery",
        "plist": "SafetyRecovery",
        "runtimes": ["safe"],
        "description": "Crash-guard recovery and reset tools for NextAura advanced visual controls.",
    },
]

RUNTIMES = {
    "feedback": {"files": ["UnlockVibrate.dylib", "UnlockVibrate.plist"]},
    "thermal": {"files": ["ThermalBattery.dylib", "ThermalBattery.plist"], "assets": True},
    "springboard": {"files": ["SpringBoardSuite.dylib", "SpringBoardSuite.plist"]},
    "extended": {"files": ["ExtendedSuite.dylib", "ExtendedSuite.plist"]},
    "safe": {"files": ["SafeSuite.dylib", "SafeSuite.plist"]},
    "advanced": {"files": ["AdvancedSuite.dylib", "AdvancedSuite.plist"]},
    "ccbackgrounds": {"files": ["CCModuleBackgrounds.dylib", "CCModuleBackgrounds.plist"]},
    "glow": {"files": ["NotificationGlow.dylib", "NotificationGlow.plist"]},
    "island": {"files": ["NextAuraNotificationIsland.dylib", "NextAuraNotificationIsland.plist"], "replacement": True},
}


def run(*args):
    subprocess.run([str(x) for x in args], check=True)


def write_control(stage: Path, fields: dict):
    debian = stage / "DEBIAN"
    debian.mkdir(parents=True, exist_ok=True)
    ordered = [
        "Package", "Name", "Version", "Architecture", "Description", "Maintainer", "Author",
        "Section", "Depends", "Conflicts", "Replaces", "Breaks", "Priority", "Homepage", "Icon", "Tag"
    ]
    lines = []
    for key in ordered:
        value = fields.get(key)
        if value:
            lines.append(f"{key}: {value}")
    for key, value in fields.items():
        if key not in ordered and value:
            lines.append(f"{key}: {value}")
    (debian / "control").write_text("\n".join(lines) + "\n")


def write_postinst(stage: Path, respring: bool):
    text = "#!/bin/sh\n"
    if respring:
        text += "if command -v sbreload >/dev/null 2>&1; then sbreload || true; fi\n"
    text += "exit 0\n"
    path = stage / "DEBIAN" / "postinst"
    path.write_text(text)
    path.chmod(0o755)


def build_deb(stage: Path, output: Path):
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        run("dpkg-deb", "--root-owner-group", "-Zxz", "-b", stage, output)
    except subprocess.CalledProcessError:
        run("dpkg-deb", "-Zxz", "-b", stage, output)


def runtime_package_id(key: str) -> str:
    return f"com.nextsolution.nextaura.runtime.{key}"


def category_package_id(slug: str) -> str:
    return f"com.nextsolution.nextaura.{slug}"


def copy_runtime_source(base_dylibs: Path, key: str, destination: Path, island_dylib: Path, island_plist: Path):
    cfg = RUNTIMES[key]
    target = destination / "Library" / "MobileSubstrate" / "DynamicLibraries"
    target.mkdir(parents=True, exist_ok=True)
    for name in cfg["files"]:
        if cfg.get("replacement") and name == "NextAuraNotificationIsland.dylib":
            src = island_dylib
        elif cfg.get("replacement") and name == "NextAuraNotificationIsland.plist":
            src = island_plist
        else:
            src = base_dylibs / name
        if not src.exists():
            raise FileNotFoundError(src)
        shutil.copy2(src, target / name)

    if cfg.get("assets"):
        assets = base_dylibs / "NextSolutionAssets"
        if assets.exists():
            shutil.copytree(assets, target / "NextSolutionAssets", dirs_exist_ok=True)


def build_runtime_packages(base_root: Path, output: Path, island_dylib: Path, island_plist: Path):
    dylibs = base_root / "Library" / "MobileSubstrate" / "DynamicLibraries"
    built = []
    for key in RUNTIMES:
        stage = Path(tempfile.mkdtemp(prefix=f"nextaura-runtime-{key}-"))
        try:
            copy_runtime_source(dylibs, key, stage, island_dylib, island_plist)
            fields = {
                "Package": runtime_package_id(key),
                "Name": f"NextAura Runtime ({key})",
                "Version": RUNTIME_VERSION,
                "Architecture": "iphoneos-arm64e",
                "Description": "Internal shared runtime for modular NextAura category packages.",
                "Maintainer": "Next Solution",
                "Author": "Next Solution - zeshan0727",
                "Section": "System",
                "Depends": "firmware (>= 16.0), mobilesubstrate",
                "Conflicts": "com.nextsolution.unlockvibrate",
                "Replaces": "com.nextsolution.unlockvibrate (<= 4.5.3)",
                "Breaks": "com.nextsolution.unlockvibrate (<= 4.5.3)",
                "Priority": "optional",
                "Homepage": HOMEPAGE,
                "Icon": ICON,
                "Tag": "role::cydia",
            }
            write_control(stage, fields)
            write_postinst(stage, False)
            deb = output / f"NextAura_Runtime_{key}_{RUNTIME_VERSION}_RootHide.deb"
            build_deb(stage, deb)
            built.append(deb)
        finally:
            shutil.rmtree(stage, ignore_errors=True)
    return built


def make_category_bundle(base_bundle: Path, category: dict, destination: Path, dynamic_plist: Path):
    bundle_name = "NextAura" + "".join(part.title().replace("-", "") for part in category["slug"].split("-")) + "Prefs.bundle"
    bundle = destination / "Library" / "PreferenceBundles" / bundle_name
    shutil.copytree(base_bundle, bundle, dirs_exist_ok=True)

    # Current Notification Island settings replace the old DynamicIsland page.
    if category["plist"] == "DynamicIsland":
        shutil.copy2(dynamic_plist, bundle / "DynamicIsland.plist")

    info_path = bundle / "Info.plist"
    with info_path.open("rb") as f:
        info = plistlib.load(f)
    info["CFBundleIdentifier"] = f"com.nextsolution.nextaura.{category['slug']}.prefs"
    info["CFBundleName"] = f"NextAura – {category['name']}"
    info["CFBundleShortVersionString"] = VERSION
    info["CFBundleVersion"] = VERSION
    with info_path.open("wb") as f:
        plistlib.dump(info, f, sort_keys=False)

    loader_dir = destination / "Library" / "PreferenceLoader" / "Preferences"
    loader_dir.mkdir(parents=True, exist_ok=True)
    loader = {
        "entry": {
            "bundle": bundle_name[:-7],
            "cell": "PSLinkCell",
            "detail": "UVSubListController",
            "isController": True,
            "icon": "icon.png",
            "label": f"NextAura – {category['name']}",
            "plist": category["plist"],
        }
    }
    loader_path = loader_dir / f"NextAura-{category['slug']}.plist"
    with loader_path.open("wb") as f:
        plistlib.dump(loader, f, sort_keys=False)


def build_category_packages(base_root: Path, output: Path, dynamic_plist: Path):
    base_bundle = base_root / "Library" / "PreferenceBundles" / "UnlockVibratePrefs.bundle"
    if not base_bundle.exists():
        raise FileNotFoundError(base_bundle)
    built = []
    for category in CATEGORIES:
        stage = Path(tempfile.mkdtemp(prefix=f"nextaura-category-{category['slug']}-"))
        try:
            make_category_bundle(base_bundle, category, stage, dynamic_plist)
            runtime_deps = [f"{runtime_package_id(key)} (>= {RUNTIME_VERSION})" for key in category["runtimes"]]
            deps = ["firmware (>= 16.0)", "preferenceloader"] + runtime_deps
            fields = {
                "Package": category_package_id(category["slug"]),
                "Name": f"NextAura – {category['name']}",
                "Version": VERSION,
                "Architecture": "iphoneos-arm64e",
                "Description": category["description"],
                "Maintainer": "Next Solution",
                "Author": "Next Solution - zeshan0727",
                "Section": "Tweaks",
                "Depends": ", ".join(deps),
                "Conflicts": "com.nextsolution.unlockvibrate",
                "Priority": "optional",
                "Homepage": HOMEPAGE,
                "Icon": ICON,
            }
            write_control(stage, fields)
            write_postinst(stage, True)
            filename = "NextAura_" + category["slug"].replace("-", "_") + f"_{VERSION}_RootHide.deb"
            deb = output / filename
            build_deb(stage, deb)
            built.append(deb)
        finally:
            shutil.rmtree(stage, ignore_errors=True)
    return built


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-deb", required=True)
    parser.add_argument("--island-dylib", required=True)
    parser.add_argument("--island-plist", required=True)
    parser.add_argument("--dynamic-plist", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    base_deb = Path(args.base_deb).resolve()
    island_dylib = Path(args.island_dylib).resolve()
    island_plist = Path(args.island_plist).resolve()
    dynamic_plist = Path(args.dynamic_plist).resolve()
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)

    base_root = Path(tempfile.mkdtemp(prefix="nextaura-base-"))
    try:
        run("dpkg-deb", "-x", base_deb, base_root)
        runtimes = build_runtime_packages(base_root, output, island_dylib, island_plist)
        categories = build_category_packages(base_root, output, dynamic_plist)

        manifest = output / "NextAura_Category_Packages.txt"
        with manifest.open("w") as f:
            f.write("NextAura category split\n")
            f.write(f"Category version: {VERSION}\nRuntime version: {RUNTIME_VERSION}\n\n")
            f.write("User-facing categories:\n")
            for category, deb in zip(CATEGORIES, categories):
                f.write(f"- {category['name']}: {category_package_id(category['slug'])} -> {deb.name}\n")
            f.write("\nInternal shared runtimes:\n")
            for key, deb in zip(RUNTIMES, runtimes):
                f.write(f"- {runtime_package_id(key)} -> {deb.name}\n")

        print(f"Built {len(categories)} category packages and {len(runtimes)} internal runtime packages in {output}")
    finally:
        shutil.rmtree(base_root, ignore_errors=True)


if __name__ == "__main__":
    main()
