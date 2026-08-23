#!/usr/bin/env python3
"""Generate the native, categorized Module Glass preference hierarchy."""

from pathlib import Path
import plistlib


DOMAIN = "com.nextsolution.unlockvibrate"
NOTIFICATION = "com.nextsolution.unlockvibrate/preferences.changed"


def group(label: str, footer: str | None = None) -> dict:
    item = {"cell": "PSGroupCell", "label": label}
    if footer:
        item["footerText"] = footer
    return item


def switch(label: str, key: str, default: bool, description: str) -> dict:
    return {
        "cell": "PSSwitchCell",
        "label": label,
        "defaults": DOMAIN,
        "key": key,
        "default": default,
        "PostNotification": NOTIFICATION,
        "description": description,
    }


def slider(
    label: str,
    key: str,
    default: float,
    minimum: float,
    maximum: float,
    description: str,
) -> dict:
    return {
        "cell": "PSSliderCell",
        "label": label,
        "defaults": DOMAIN,
        "key": key,
        "default": default,
        "min": minimum,
        "max": maximum,
        "showValue": True,
        "PostNotification": NOTIFICATION,
        "description": description,
    }


def button(label: str, action: str, description: str | None = None, **values) -> dict:
    item = {"cell": "PSButtonCell", "label": label, "action": action, **values}
    if description:
        item["description"] = description
    return item


def module_button(title: str, slot: str) -> dict:
    return button(
        title,
        "configureCCModuleBackground:",
        f"Choose or remove the image used behind the {title.lower()} module.",
        moduleSlot=slot,
        moduleTitle=title,
    )


def category_link(label: str, plist: str) -> dict:
    return {
        "cell": "PSLinkCell",
        "label": label,
        "detail": "AuraCategoryListController",
        "isController": True,
        "plist": plist,
    }


CATEGORIES = {
    "ModuleGlassCoreModules.plist": {
        "title": "Core Modules",
        "items": [
            group(
                "CORE MODULES",
                "Tap a module to choose or remove its background image.",
            ),
            module_button("Connectivity", "connectivity"),
            module_button("Now Playing", "media"),
            module_button("Brightness", "brightness"),
            module_button("Volume", "volume"),
            group(
                "VOLUME APPEARANCE",
                "Optionally recolor the native speaker glyph without changing the Volume background.",
            ),
            switch(
                "Custom Volume Glyph Color",
                "CCModuleVolumeIconColorEnabled",
                False,
                "Keeps the selected Volume background and recolors only the native speaker glyph.",
            ),
            button(
                "Choose Volume Glyph Color",
                "chooseVolumeIconColor:",
                "Open the native iOS color picker. Selecting a color enables this option automatically.",
            ),
        ],
    },
    "ModuleGlassQuickControls.plist": {
        "title": "Quick Controls",
        "items": [
            group(
                "QUICK CONTROLS",
                "Personalize the compact controls you use most often.",
            ),
            module_button("Flashlight", "flashlight"),
            module_button("Timer", "timer"),
            module_button("Calculator", "calculator"),
            module_button("Camera", "camera"),
        ],
    },
    "ModuleGlassDisplaySystem.plist": {
        "title": "Display & System",
        "items": [
            group(
                "DISPLAY & SYSTEM",
                "Backgrounds for display, recording, focus, and system-state controls.",
            ),
            module_button("Screen Mirroring", "screenmirroring"),
            module_button("Focus", "focus"),
            module_button("Orientation Lock", "orientation"),
            module_button("Screen Recording", "screenrecording"),
            module_button("Low Power Mode", "lowpower"),
            module_button("Dark Mode", "darkmode"),
        ],
    },
    "ModuleGlassAccessoriesApps.plist": {
        "title": "Accessories & Apps",
        "items": [
            group(
                "ACCESSORIES & APPS",
                "Backgrounds for accessibility, Home, and app-based controls.",
            ),
            module_button("Hearing", "hearing"),
            module_button("Notes", "notes"),
            module_button("Home", "home"),
        ],
    },
    "ModuleGlassOtherReset.plist": {
        "title": "Other & Reset",
        "items": [
            group(
                "OTHER MODULES",
                "Use one fallback image for compatible modules that do not have a dedicated category.",
            ),
            module_button("Other Modules", "other"),
            group(
                "RESET",
                "Remove every saved module image while keeping your other appearance settings.",
            ),
            button(
                "Remove All Module Images",
                "resetAllCCModuleBackgrounds:",
                "Delete all selected module background images.",
            ),
        ],
    },
}


ROOT = {
    "title": "Module Glass",
    "items": [
        group(
            "APPEARANCE",
            "Premium Control Center styling by Next Jailbreak. Existing module behavior and gestures remain native.",
        ),
        switch(
            "Enable Module Backgrounds",
            "CCModuleBackgroundsEnabled",
            False,
            "Show the selected image behind each matching Control Center module.",
        ),
        switch(
            "Remove Stock Module Blur",
            "CCModuleRemoveBlur",
            True,
            "Remove Apple's stock blur only from modules that use a custom image.",
        ),
        slider(
            "Image Opacity",
            "CCModuleBackgroundOpacity",
            1.0,
            0.25,
            1.0,
            "Adjust the visibility of all selected module background images.",
        ),
        switch(
            "Glow Icons & Labels",
            "CCModuleControlGlowEnabled",
            True,
            "Add safe illumination to module icons and text without changing their layout.",
        ),
        slider(
            "Glow Brightness",
            "CCModuleControlGlowIntensity",
            0.8,
            0.1,
            1.0,
            "Adjust how prominently module icons and labels glow.",
        ),
        slider(
            "Glow Spread",
            "CCModuleControlGlowWidth",
            1.5,
            0.5,
            4.0,
            "Adjust the soft glow radius around module icons and labels.",
        ),
        group(
            "MODULE IMAGES",
            "Open a category, then tap any module to choose or remove its image.",
        ),
        category_link("Core Modules", "ModuleGlassCoreModules"),
        category_link("Quick Controls", "ModuleGlassQuickControls"),
        category_link("Display & System", "ModuleGlassDisplaySystem"),
        category_link("Accessories & Apps", "ModuleGlassAccessoriesApps"),
        category_link("Other & Reset", "ModuleGlassOtherReset"),
        group(
            "APPLY CHANGES",
            "Apply your saved settings immediately, or respring if another tweak has cached Control Center.",
        ),
        button(
            "Apply Module Glass",
            "applyCCModuleBackgrounds:",
            "Reload Module Glass settings without a full respring.",
        ),
        button("Respring", "respringDevice:", "Restart SpringBoard and reload every module."),
    ],
}


EXPECTED_SLOTS = {
    "connectivity",
    "media",
    "brightness",
    "volume",
    "screenmirroring",
    "focus",
    "flashlight",
    "timer",
    "calculator",
    "camera",
    "orientation",
    "screenrecording",
    "lowpower",
    "darkmode",
    "hearing",
    "notes",
    "home",
    "other",
}


def write_plist(path: Path, data: dict) -> None:
    with path.open("wb") as stream:
        plistlib.dump(data, stream, fmt=plistlib.FMT_XML, sort_keys=False)


def build_preferences(bundle: Path) -> None:
    bundle.mkdir(parents=True, exist_ok=True)
    write_plist(bundle / "CCModuleBackgrounds.plist", ROOT)
    for filename, data in CATEGORIES.items():
        write_plist(bundle / filename, data)

    slots = [
        item["moduleSlot"]
        for data in CATEGORIES.values()
        for item in data["items"]
        if "moduleSlot" in item
    ]
    if len(slots) != len(set(slots)):
        raise SystemExit("duplicate Module Glass module slot")
    if set(slots) != EXPECTED_SLOTS:
        raise SystemExit(
            f"module slot mismatch: missing={sorted(EXPECTED_SLOTS - set(slots))} "
            f"extra={sorted(set(slots) - EXPECTED_SLOTS)}"
        )


if __name__ == "__main__":
    project = Path(__file__).resolve().parent
    target = project / "layout/Library/PreferenceBundles/ModuleGlassPrefs.bundle"
    build_preferences(target)
    print(f"Generated categorized Module Glass preferences with {len(EXPECTED_SLOTS)} module slots")
