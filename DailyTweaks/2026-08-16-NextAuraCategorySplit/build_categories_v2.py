#!/usr/bin/env python3
import argparse
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

CATEGORY_VERSION = "1.0.0"
RUNTIME_VERSION = "1.0.0"
HOMEPAGE = "https://nextsolution.cc/"
ICON = "https://nextsolution.cc/CydiaIcon.png"
OLD_PACKAGE = "com.nextsolution.unlockvibrate"

CATEGORIES = [
    ("feedback", "Vibration Feedback", "Feedback", ["feedback"], "Unlock and call-connect vibration feedback from NextAura."),
    ("thermal-sweat", "Temperature & Sweat", "ThermalSweat", ["thermal"], "Temperature-aware battery visuals, Sweat My Phone effects and battery percentage tools."),
    ("home-screen", "Home Screen & Icons", "HomeScreen", ["springboard", "extended", "safe"], "Home Screen labels, badges, icon sizing, opacity and advanced visual controls."),
    ("dock-folders", "Dock & Folders", "DockFolders", ["springboard", "safe"], "Dock and folder backgrounds, labels, sizing, opacity and advanced layout controls."),
    ("lock-screen", "Lock Screen", "LockScreen", ["springboard", "extended", "safe"], "Lock Screen clock, quick actions, status elements, charging text and notification-list visuals."),
    ("status-bar", "Status Bar", "StatusBar", ["extended", "safe"], "Status Bar visibility, opacity, scale, positioning and individual indicator controls."),
    ("control-center", "Control Center Appearance", "ControlCenter", ["extended", "safe"], "Control Center labels, module sizing, background appearance and advanced stock-layout controls."),
    ("cc-second-page", "Second Page & Controls", "CCSecondPage", ["advanced"], "NextAura second Control Center page with configurable tiles, spacing, information and haptics."),
    ("cc-module-backgrounds", "Module Backgrounds", "CCModuleBackgrounds", ["ccbackgrounds"], "Control Center module backgrounds, blur removal, opacity and control glow effects."),
    ("notification-island", "Notification Island", "DynamicIsland", ["island"], "Notification Island with app icons, privacy, exact-app Open, Dismiss, live preview and layout controls."),
    ("notification-glow", "Notification Glow", "NotificationGlow", ["glow"], "Edge glow, pulse, ripple and lock-screen notification lighting effects."),
    ("now-playing", "Now Playing", "NowPlaying", ["extended", "safe"], "Now Playing artwork, title, artist, controls, opacity, scaling and background appearance."),
    ("notifications", "Notifications", "Notifications", ["extended", "safe"], "Stock notification icon, app name, time, buttons, scale, opacity and advanced card appearance."),
    ("app-switcher", "App Switcher", "AppSwitcher", ["safe"], "App Switcher card scale, opacity, spacing, labels, icons and background controls."),
    ("system-overlays", "Screenshots & HUDs", "SystemOverlays", ["safe"], "Screenshot flash/preview controls plus Volume and Ringer HUD visibility options."),
    ("animations", "Animations", "Animations", ["springboard"], "System animation-speed control from the NextAura suite."),
    ("safety-recovery", "Safety & Recovery", "SafetyRecovery", ["safe"], "Crash-guard recovery and reset tools for NextAura advanced visual controls."),
]

RUNTIMES = {
    "feedback": ["UnlockVibrate.dylib", "UnlockVibrate.plist"],
    "thermal": ["ThermalBattery.dylib", "ThermalBattery.plist"],
    "springboard": ["SpringBoardSuite.dylib", "SpringBoardSuite.plist"],
    "extended": ["ExtendedSuite.dylib", "ExtendedSuite.plist"],
    "safe": ["SafeSuite.dylib", "SafeSuite.plist"],
    "advanced": ["AdvancedSuite.dylib", "AdvancedSuite.plist"],
    "ccbackgrounds": ["CCModuleBackgrounds.dylib", "CCModuleBackgrounds.plist"],
    "glow": ["NotificationGlow.dylib", "NotificationGlow.plist"],
    "island": ["NextAuraNotificationIsland.dylib", "NextAuraNotificationIsland.plist"],
}


def run(*args):
    subprocess.run([str(x) for x in args], check=True)


def package_id(slug):
    return f"com.nextsolution.nextaura.{slug}"


def runtime_id(name):
    return f"com.nextsolution.nextaura.runtime.{name}"


def control(stage: Path, fields: dict):
    d = stage / "DEBIAN"
    d.mkdir(parents=True, exist_ok=True)
    order = ["Package", "Name", "Version", "Architecture", "Description", "Maintainer", "Author", "Section", "Depends", "Conflicts", "Replaces", "Breaks", "Priority", "Homepage", "Icon", "Tag"]
    lines = []
    for k in order:
        if fields.get(k):
            lines.append(f"{k}: {fields[k]}")
    (d / "control").write_text("\n".join(lines) + "\n")


def postinst(stage: Path, respring=False):
    p = stage / "DEBIAN" / "postinst"
    text = "#!/bin/sh\n"
    if respring:
        text += "if command -v sbreload >/dev/null 2>&1; then sbreload || true; fi\n"
    text += "exit 0\n"
    p.write_text(text)
    p.chmod(0o755)


def build(stage: Path, output: Path):
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        run("dpkg-deb", "--root-owner-group", "-Zxz", "-b", stage, output)
    except subprocess.CalledProcessError:
        run("dpkg-deb", "-Zxz", "-b", stage, output)


def internal_fields(pkg, name, description):
    return {
        "Package": pkg,
        "Name": name,
        "Version": RUNTIME_VERSION,
        "Architecture": "iphoneos-arm64e",
        "Description": description,
        "Maintainer": "Next Solution",
        "Author": "Next Solution - zeshan0727",
        "Section": "System",
        "Depends": "firmware (>= 16.0)",
        "Conflicts": OLD_PACKAGE,
        "Replaces": f"{OLD_PACKAGE} (<= 4.5.3)",
        "Breaks": f"{OLD_PACKAGE} (<= 4.5.3)",
        "Priority": "optional",
        "Homepage": HOMEPAGE,
        "Icon": ICON,
        "Tag": "role::cydia",
    }


def build_preferences_runtime(base_root: Path, out: Path):
    source = base_root / "Library" / "PreferenceBundles" / "UnlockVibratePrefs.bundle"
    stage = Path(tempfile.mkdtemp(prefix="nextaura-prefs-runtime-"))
    try:
        target = stage / "Library" / "PreferenceBundles" / "UnlockVibratePrefs.bundle"
        target.mkdir(parents=True, exist_ok=True)
        for name in ["UnlockVibratePrefs", "Info.plist", "icon.png"]:
            shutil.copy2(source / name, target / name)
        # The recovery controller reads this key list by resource name.
        if (source / "SafeLabKeys.plist").exists():
            shutil.copy2(source / "SafeLabKeys.plist", target / "SafeLabKeys.plist")
        info_path = target / "Info.plist"
        with info_path.open("rb") as f:
            info = plistlib.load(f)
        info["CFBundleShortVersionString"] = RUNTIME_VERSION
        info["CFBundleVersion"] = RUNTIME_VERSION
        with info_path.open("wb") as f:
            plistlib.dump(info, f, sort_keys=False)
        fields = internal_fields(runtime_id("preferences"), "NextAura Preferences Runtime", "Internal Preferences controller shared by modular NextAura category packages.")
        fields["Depends"] = "firmware (>= 16.0), preferenceloader"
        control(stage, fields)
        postinst(stage, False)
        deb = out / f"NextAura_Runtime_preferences_{RUNTIME_VERSION}_RootHide.deb"
        build(stage, deb)
        return deb
    finally:
        shutil.rmtree(stage, ignore_errors=True)


def build_code_runtimes(base_root: Path, out: Path, island_dylib: Path, island_plist: Path):
    source = base_root / "Library" / "MobileSubstrate" / "DynamicLibraries"
    result = []
    for key, files in RUNTIMES.items():
        stage = Path(tempfile.mkdtemp(prefix=f"nextaura-runtime-{key}-"))
        try:
            target = stage / "Library" / "MobileSubstrate" / "DynamicLibraries"
            target.mkdir(parents=True, exist_ok=True)
            for name in files:
                if key == "island" and name.endswith(".dylib"):
                    src = island_dylib
                elif key == "island" and name.endswith(".plist"):
                    src = island_plist
                else:
                    src = source / name
                if not src.exists():
                    raise FileNotFoundError(src)
                shutil.copy2(src, target / name)
            if key == "thermal" and (source / "NextSolutionAssets").exists():
                shutil.copytree(source / "NextSolutionAssets", target / "NextSolutionAssets", dirs_exist_ok=True)
            fields = internal_fields(runtime_id(key), f"NextAura Runtime ({key})", f"Internal {key} runtime shared by modular NextAura categories.")
            fields["Depends"] = "firmware (>= 16.0), mobilesubstrate"
            control(stage, fields)
            postinst(stage, False)
            deb = out / f"NextAura_Runtime_{key}_{RUNTIME_VERSION}_RootHide.deb"
            build(stage, deb)
            result.append(deb)
        finally:
            shutil.rmtree(stage, ignore_errors=True)
    return result


def build_category(base_root: Path, out: Path, dynamic_plist: Path, item):
    slug, name, plist_name, runtimes, description = item
    stage = Path(tempfile.mkdtemp(prefix=f"nextaura-category-{slug}-"))
    try:
        source_bundle = base_root / "Library" / "PreferenceBundles" / "UnlockVibratePrefs.bundle"
        pref_target = stage / "Library" / "PreferenceBundles" / "UnlockVibratePrefs.bundle"
        pref_target.mkdir(parents=True, exist_ok=True)
        source_plist = source_bundle / f"{plist_name}.plist"
        if plist_name == "DynamicIsland":
            source_plist = dynamic_plist
        if not source_plist.exists():
            raise FileNotFoundError(source_plist)
        shutil.copy2(source_plist, pref_target / f"{plist_name}.plist")

        loader_dir = stage / "Library" / "PreferenceLoader" / "Preferences"
        loader_dir.mkdir(parents=True, exist_ok=True)
        loader = {
            "entry": {
                "bundle": "UnlockVibratePrefs",
                "cell": "PSLinkCell",
                "detail": "UVSubListController",
                "isController": True,
                "icon": "icon.png",
                "label": f"NextAura – {name}",
                "plist": plist_name,
            }
        }
        with (loader_dir / f"NextAura-{slug}.plist").open("wb") as f:
            plistlib.dump(loader, f, sort_keys=False)

        deps = ["firmware (>= 16.0)", "preferenceloader", f"{runtime_id('preferences')} (>= {RUNTIME_VERSION})"]
        deps.extend(f"{runtime_id(r)} (>= {RUNTIME_VERSION})" for r in runtimes)
        fields = {
            "Package": package_id(slug),
            "Name": f"NextAura – {name}",
            "Version": CATEGORY_VERSION,
            "Architecture": "iphoneos-arm64e",
            "Description": description,
            "Maintainer": "Next Solution",
            "Author": "Next Solution - zeshan0727",
            "Section": "Tweaks",
            "Depends": ", ".join(deps),
            "Conflicts": OLD_PACKAGE,
            "Priority": "optional",
            "Homepage": HOMEPAGE,
            "Icon": ICON,
        }
        control(stage, fields)
        postinst(stage, True)
        deb = out / f"NextAura_{slug.replace('-', '_')}_{CATEGORY_VERSION}_RootHide.deb"
        build(stage, deb)
        return deb
    finally:
        shutil.rmtree(stage, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-deb", required=True)
    ap.add_argument("--island-dylib", required=True)
    ap.add_argument("--island-plist", required=True)
    ap.add_argument("--dynamic-plist", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    base_root = Path(tempfile.mkdtemp(prefix="nextaura-base-"))
    try:
        run("dpkg-deb", "-x", Path(args.base_deb).resolve(), base_root)
        pref_runtime = build_preferences_runtime(base_root, out)
        code_runtimes = build_code_runtimes(base_root, out, Path(args.island_dylib).resolve(), Path(args.island_plist).resolve())
        category_debs = [build_category(base_root, out, Path(args.dynamic_plist).resolve(), item) for item in CATEGORIES]

        manifest = out / "NextAura_Category_Packages.txt"
        with manifest.open("w") as f:
            f.write("NextAura modular category packages\n")
            f.write(f"Category version: {CATEGORY_VERSION}\nRuntime version: {RUNTIME_VERSION}\n\n")
            f.write("USER-FACING CATEGORIES\n")
            for item, deb in zip(CATEGORIES, category_debs):
                slug, name, _, _, _ = item
                f.write(f"{name}\n  Package: {package_id(slug)}\n  File: {deb.name}\n")
            f.write("\nINTERNAL SHARED RUNTIMES\n")
            f.write(f"Preferences\n  Package: {runtime_id('preferences')}\n  File: {pref_runtime.name}\n")
            for key, deb in zip(RUNTIMES.keys(), code_runtimes):
                f.write(f"{key}\n  Package: {runtime_id(key)}\n  File: {deb.name}\n")
        print(f"Built {len(category_debs)} visible category DEBs and {1 + len(code_runtimes)} hidden runtime DEBs")
    finally:
        shutil.rmtree(base_root, ignore_errors=True)


if __name__ == "__main__":
    main()
