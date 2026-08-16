#!/usr/bin/env python3
import argparse
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

CATEGORY_VERSION = "1.0.1"
RUNTIME_VERSION = "1.0.0"
PREFS_RUNTIME_VERSION = "1.0.1"
HOMEPAGE = "https://nextsolution.cc/"
OLD_PACKAGE = "com.nextsolution.unlockvibrate"
ICON_BASE_URL = "https://nextsolution.cc/icons/nextaura"

# Package IDs/slugs stay unchanged so existing modular installations update in-place.
CATEGORIES = [
    ("feedback", "Aura Haptics", "Feedback", ["feedback"], "Unlock and call-connect vibration feedback from NextAura."),
    ("thermal-sweat", "Aura Thermal", "ThermalSweat", ["thermal"], "Temperature-aware battery visuals, Sweat My Phone effects and battery percentage tools."),
    ("home-screen", "Aura Home", "HomeScreen", ["springboard", "extended", "safe"], "Home Screen labels, badges, icon sizing, opacity and advanced visual controls."),
    ("dock-folders", "Aura Dock", "DockFolders", ["springboard", "safe"], "Dock and folder backgrounds, labels, sizing, opacity and advanced layout controls."),
    ("lock-screen", "Aura Lock", "LockScreen", ["springboard", "extended", "safe"], "Lock Screen clock, quick actions, status elements, charging text and notification-list visuals."),
    ("status-bar", "Aura Status", "StatusBar", ["extended", "safe"], "Status Bar visibility, opacity, scale, positioning and individual indicator controls."),
    ("control-center", "Aura Control", "ControlCenter", ["extended", "safe"], "Control Center labels, module sizing, background appearance and advanced stock-layout controls."),
    ("cc-second-page", "Aura Panel", "CCSecondPage", ["advanced"], "Second Control Center page with configurable tiles, spacing, information and haptics."),
    ("cc-module-backgrounds", "Aura Modules", "CCModuleBackgrounds", ["ccbackgrounds"], "Control Center module backgrounds, blur removal, opacity and control glow effects."),
    ("notification-island", "Aura Island", "DynamicIsland", ["island"], "Notification Island with app icons, privacy, exact-app Open, Dismiss, live preview and layout controls."),
    ("notification-glow", "Aura Glow", "NotificationGlow", ["glow"], "Edge glow, pulse, ripple and lock-screen notification lighting effects."),
    ("now-playing", "Aura Player", "NowPlaying", ["extended", "safe"], "Now Playing artwork, title, artist, controls, opacity, scaling and background appearance."),
    ("notifications", "Aura Alerts", "Notifications", ["extended", "safe"], "Stock notification icon, app name, time, buttons, scale, opacity and advanced card appearance."),
    ("app-switcher", "Aura Switcher", "AppSwitcher", ["safe"], "App Switcher card scale, opacity, spacing, labels, icons and background controls."),
    ("system-overlays", "Aura HUD", "SystemOverlays", ["safe"], "Screenshot flash/preview controls plus Volume and Ringer HUD visibility options."),
    ("animations", "Aura Motion", "Animations", ["springboard"], "System animation-speed control from the NextAura suite."),
    ("safety-recovery", "Aura Safe", "SafetyRecovery", ["safe"], "Crash-guard recovery and reset tools for NextAura advanced visual controls."),
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

ACCENTS = {
    "feedback": ((98, 76, 255), (190, 95, 255)),
    "thermal-sweat": ((255, 89, 65), (255, 170, 45)),
    "home-screen": ((46, 147, 255), (77, 211, 255)),
    "dock-folders": ((63, 190, 155), (42, 226, 196)),
    "lock-screen": ((74, 89, 255), (113, 128, 255)),
    "status-bar": ((47, 202, 110), (108, 236, 145)),
    "control-center": ((35, 176, 255), (73, 110, 255)),
    "cc-second-page": ((130, 86, 255), (225, 80, 255)),
    "cc-module-backgrounds": ((52, 196, 224), (65, 132, 255)),
    "notification-island": ((15, 15, 18), (70, 70, 76)),
    "notification-glow": ((255, 52, 147), (255, 126, 61)),
    "now-playing": ((255, 55, 95), (255, 110, 150)),
    "notifications": ((255, 148, 28), (255, 206, 70)),
    "app-switcher": ((74, 118, 255), (123, 89, 255)),
    "system-overlays": ((90, 200, 255), (111, 242, 220)),
    "animations": ((255, 93, 72), (255, 190, 65)),
    "safety-recovery": ((35, 193, 108), (40, 137, 255)),
}


def run(*args):
    subprocess.run([str(x) for x in args], check=True)


def package_id(slug):
    return f"com.nextsolution.nextaura.{slug}"


def runtime_id(name):
    return f"com.nextsolution.nextaura.runtime.{name}"


def icon_url(slug):
    return f"{ICON_BASE_URL}/{slug}.png"


def _gradient(size, a, b):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    for y in range(size):
        t = y / max(1, size - 1)
        for x in range(size):
            tt = min(1.0, max(0.0, (t * 0.72) + (x / max(1, size - 1)) * 0.28))
            px[x, y] = tuple(int(a[i] * (1 - tt) + b[i] * tt) for i in range(3)) + (255,)
    return img


def _line(draw, points, fill=(255, 255, 255, 245), width=30, joint="curve"):
    draw.line(points, fill=fill, width=width, joint=joint)


def draw_icon(slug: str, path: Path, size=512):
    a, b = ACCENTS[slug]
    img = _gradient(size, a, b)
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, size - 1, size - 1), radius=116, fill=255)
    img.putalpha(mask)
    d = ImageDraw.Draw(img)
    white = (255, 255, 255, 245)
    soft = (255, 255, 255, 120)
    c = size // 2

    if slug == "feedback":
        d.ellipse((c-43, c-43, c+43, c+43), fill=white)
        for r in (92, 142):
            d.arc((c-r, c-r, c+r, c+r), 305, 55, fill=white, width=27)
            d.arc((c-r, c-r, c+r, c+r), 125, 235, fill=white, width=27)
    elif slug == "thermal-sweat":
        d.rounded_rectangle((205, 105, 307, 350), radius=50, outline=white, width=28)
        d.ellipse((178, 295, 334, 451), fill=white)
        d.rounded_rectangle((239, 175, 273, 357), radius=17, fill=white)
        d.ellipse((222, 337, 290, 405), fill=a + (255,))
    elif slug == "home-screen":
        d.polygon([(92, 250), (256, 105), (420, 250)], fill=white)
        d.rounded_rectangle((125, 232, 387, 420), radius=32, fill=white)
        d.rounded_rectangle((222, 305, 290, 420), radius=18, fill=a + (255,))
    elif slug == "dock-folders":
        d.rounded_rectangle((84, 130, 428, 332), radius=56, outline=white, width=28)
        d.rounded_rectangle((92, 355, 420, 416), radius=30, fill=white)
        for x in (142, 223, 304):
            d.rounded_rectangle((x, 188, x+55, 243), radius=14, fill=white)
    elif slug == "lock-screen":
        d.rounded_rectangle((125, 220, 387, 420), radius=48, fill=white)
        d.arc((165, 90, 347, 300), 185, 355, fill=white, width=34)
        d.ellipse((234, 288, 278, 332), fill=a + (255,))
        d.rounded_rectangle((246, 321, 266, 367), radius=10, fill=a + (255,))
    elif slug == "status-bar":
        for i, h in enumerate((70, 112, 154, 198)):
            x = 96 + i*72
            d.rounded_rectangle((x, 390-h, x+42, 390), radius=15, fill=white)
        d.arc((104, 88, 408, 330), 215, 325, fill=white, width=24)
    elif slug == "control-center":
        tiles = [(88, 88, 238, 238), (274, 88, 424, 238), (88, 274, 238, 424), (274, 274, 424, 424)]
        for box in tiles:
            d.rounded_rectangle(box, radius=45, fill=white)
        d.ellipse((133, 133, 193, 193), fill=a + (255,))
        _line(d, [(318, 163), (380, 163)], fill=a + (255,), width=22)
        _line(d, [(163, 318), (163, 380)], fill=a + (255,), width=22)
    elif slug == "cc-second-page":
        for row in range(3):
            for col in range(3):
                x = 92 + col*118
                y = 92 + row*118
                d.rounded_rectangle((x, y, x+84, y+84), radius=24, outline=white, width=18)
        _line(d, [(256, 158), (256, 318)], fill=white, width=28)
        _line(d, [(176, 238), (336, 238)], fill=white, width=28)
    elif slug == "cc-module-backgrounds":
        d.rounded_rectangle((105, 105, 350, 350), radius=52, fill=soft)
        d.rounded_rectangle((162, 162, 407, 407), radius=52, outline=white, width=30)
        d.rounded_rectangle((216, 216, 353, 353), radius=32, fill=white)
    elif slug == "notification-island":
        d.rounded_rectangle((88, 186, 424, 326), radius=70, fill=white)
        d.rounded_rectangle((134, 220, 378, 292), radius=36, fill=(12, 12, 15, 255))
    elif slug == "notification-glow":
        d.ellipse((176, 176, 336, 336), fill=white)
        for r, alpha in ((120, 180), (168, 100), (208, 55)):
            d.ellipse((c-r, c-r, c+r, c+r), outline=(255,255,255,alpha), width=18)
    elif slug == "now-playing":
        _line(d, [(244, 135), (244, 334)], fill=white, width=34)
        _line(d, [(244, 150), (374, 120)], fill=white, width=34)
        d.ellipse((130, 300, 254, 416), fill=white)
        d.ellipse((296, 270, 416, 384), fill=white)
        _line(d, [(374, 120), (374, 300)], fill=white, width=34)
    elif slug == "notifications":
        d.rounded_rectangle((90, 104, 422, 350), radius=70, fill=white)
        d.polygon([(170, 335), (126, 420), (244, 350)], fill=white)
        for y in (178, 238):
            d.rounded_rectangle((150, y, 360, y+24), radius=12, fill=a + (255,))
    elif slug == "app-switcher":
        d.rounded_rectangle((98, 142, 310, 392), radius=40, fill=soft)
        d.rounded_rectangle((150, 112, 362, 362), radius=40, fill=(255,255,255,185))
        d.rounded_rectangle((202, 82, 414, 332), radius=40, outline=white, width=28)
    elif slug == "system-overlays":
        _line(d, [(125, 180), (125, 115), (190, 115)], width=25)
        _line(d, [(387, 180), (387, 115), (322, 115)], width=25)
        _line(d, [(125, 332), (125, 397), (190, 397)], width=25)
        _line(d, [(387, 332), (387, 397), (322, 397)], width=25)
        d.rounded_rectangle((192, 202, 320, 310), radius=28, fill=white)
    elif slug == "animations":
        d.rounded_rectangle((155, 130, 357, 382), radius=52, outline=white, width=28)
        for y, length in ((182, 148), (252, 190), (322, 120)):
            d.rounded_rectangle((65, y, 65+length, y+24), radius=12, fill=white)
    elif slug == "safety-recovery":
        d.polygon([(256, 76), (408, 132), (390, 306), (256, 432), (122, 306), (104, 132)], fill=white)
        _line(d, [(184, 260), (236, 315), (338, 202)], fill=a + (255,), width=32)

    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG", optimize=True)


def generate_icons(out: Path):
    icon_dir = out / "icons" / "nextaura"
    icon_dir.mkdir(parents=True, exist_ok=True)
    for slug, *_ in CATEGORIES:
        draw_icon(slug, icon_dir / f"{slug}.png")
    return icon_dir


def control(stage: Path, fields: dict):
    d = stage / "DEBIAN"
    d.mkdir(parents=True, exist_ok=True)
    order = ["Package", "Name", "Version", "Architecture", "Description", "Maintainer", "Author", "Section", "Depends", "Conflicts", "Replaces", "Breaks", "Priority", "Homepage", "Icon", "Tag"]
    lines = []
    for k in order:
        if fields.get(k):
            lines.append(f"{k}: {fields[k]}")
    (d / "control").write_text("\n".join(lines) + "\n")


def postinst(stage: Path, respring=False, kill_settings=False):
    p = stage / "DEBIAN" / "postinst"
    text = "#!/bin/sh\n"
    if kill_settings:
        text += "killall -9 Preferences 2>/dev/null || true\n"
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


def internal_fields(pkg, name, description, version=RUNTIME_VERSION):
    return {
        "Package": pkg,
        "Name": name,
        "Version": version,
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
        "Tag": "role::cydia",
    }


def build_preferences_runtime(base_root: Path, out: Path, dynamic_plist: Path, icon_dir: Path):
    """Build one complete Preferences bundle containing every category resource.

    Keeping executable + all .plist pages + all Settings icons in one DEB prevents
    NSBundle resource-cache misses that produced blank modular pages on-device.
    """
    source = base_root / "Library" / "PreferenceBundles" / "UnlockVibratePrefs.bundle"
    stage = Path(tempfile.mkdtemp(prefix="nextaura-prefs-runtime-"))
    try:
        target = stage / "Library" / "PreferenceBundles" / "UnlockVibratePrefs.bundle"
        target.mkdir(parents=True, exist_ok=True)
        for name in ["UnlockVibratePrefs", "Info.plist", "icon.png"]:
            shutil.copy2(source / name, target / name)
        if (source / "SafeLabKeys.plist").exists():
            shutil.copy2(source / "SafeLabKeys.plist", target / "SafeLabKeys.plist")

        # Bundle all 17 category pages alongside the controller binary.
        for slug, _name, plist_name, _runtimes, _description in CATEGORIES:
            src = dynamic_plist if plist_name == "DynamicIsland" else source / f"{plist_name}.plist"
            if not src.exists():
                raise FileNotFoundError(f"Missing Settings page {plist_name}: {src}")
            shutil.copy2(src, target / f"{plist_name}.plist")
            shutil.copy2(icon_dir / f"{slug}.png", target / f"NextAura-{slug}.png")

        info_path = target / "Info.plist"
        with info_path.open("rb") as f:
            info = plistlib.load(f)
        info["CFBundleShortVersionString"] = PREFS_RUNTIME_VERSION
        info["CFBundleVersion"] = PREFS_RUNTIME_VERSION
        with info_path.open("wb") as f:
            plistlib.dump(info, f, sort_keys=False)

        fields = internal_fields(
            runtime_id("preferences"),
            "NextAura Preferences Runtime",
            "Internal Preferences controller and category resources shared by modular NextAura packages.",
            PREFS_RUNTIME_VERSION,
        )
        fields["Depends"] = "firmware (>= 16.0), preferenceloader"
        control(stage, fields)
        postinst(stage, False, True)
        deb = out / f"NextAura_Runtime_preferences_{PREFS_RUNTIME_VERSION}_RootHide.deb"
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


def build_category(out: Path, item):
    """Visible category DEBs only register a PreferenceLoader entry.

    All actual page resources live in the single shared Preferences runtime bundle.
    """
    slug, name, plist_name, runtimes, description = item
    stage = Path(tempfile.mkdtemp(prefix=f"nextaura-category-{slug}-"))
    try:
        loader_dir = stage / "Library" / "PreferenceLoader" / "Preferences"
        loader_dir.mkdir(parents=True, exist_ok=True)
        loader = {
            "entry": {
                "bundle": "UnlockVibratePrefs",
                "cell": "PSLinkCell",
                "detail": "UVSubListController",
                "isController": True,
                "icon": f"NextAura-{slug}.png",
                "label": name,
                "plist": plist_name,
            }
        }
        with (loader_dir / f"NextAura-{slug}.plist").open("wb") as f:
            plistlib.dump(loader, f, sort_keys=False)

        deps = ["firmware (>= 16.0)", "preferenceloader", f"{runtime_id('preferences')} (>= {PREFS_RUNTIME_VERSION})"]
        deps.extend(f"{runtime_id(r)} (>= {RUNTIME_VERSION})" for r in runtimes)
        fields = {
            "Package": package_id(slug),
            "Name": name,
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
            "Icon": icon_url(slug),
        }
        control(stage, fields)
        postinst(stage, True, True)
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
    icon_dir = generate_icons(out)
    base_root = Path(tempfile.mkdtemp(prefix="nextaura-base-"))
    try:
        run("dpkg-deb", "-x", Path(args.base_deb).resolve(), base_root)
        dynamic_plist = Path(args.dynamic_plist).resolve()
        pref_runtime = build_preferences_runtime(base_root, out, dynamic_plist, icon_dir)
        code_runtimes = build_code_runtimes(base_root, out, Path(args.island_dylib).resolve(), Path(args.island_plist).resolve())
        category_debs = [build_category(out, item) for item in CATEGORIES]

        manifest = out / "NextAura_Category_Packages.txt"
        with manifest.open("w") as f:
            f.write("NextAura modular category packages\n")
            f.write(f"Category version: {CATEGORY_VERSION}\nCode runtime version: {RUNTIME_VERSION}\nPreferences runtime version: {PREFS_RUNTIME_VERSION}\n\n")
            f.write("USER-FACING CATEGORIES\n")
            for item, deb in zip(CATEGORIES, category_debs):
                slug, name, _, _, _ = item
                f.write(f"{name}\n  Package: {package_id(slug)}\n  File: {deb.name}\n  Icon: {icon_url(slug)}\n")
            f.write("\nINTERNAL SHARED RUNTIMES\n")
            f.write(f"Preferences\n  Package: {runtime_id('preferences')}\n  File: {pref_runtime.name}\n")
            for key, deb in zip(RUNTIMES.keys(), code_runtimes):
                f.write(f"{key}\n  Package: {runtime_id(key)}\n  File: {deb.name}\n")
        print(f"Built {len(category_debs)} visible category DEBs and {1 + len(code_runtimes)} hidden runtime DEBs with bundled Settings resources")
    finally:
        shutil.rmtree(base_root, ignore_errors=True)


if __name__ == "__main__":
    main()
