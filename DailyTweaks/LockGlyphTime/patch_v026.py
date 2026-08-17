#!/usr/bin/env python3
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parent
runtime_path = ROOT / "RuntimeV023.xm"
src = runtime_path.read_text()

# Independent custom-photo frame size. Keep 22pt as the upgrade-safe default,
# while allowing a much larger frame than SF Symbol icons.
icon_size_decl = 'static CGFloat gIconSize = 22.0;'
if icon_size_decl not in src:
    raise SystemExit("icon size declaration not found")
src = src.replace(icon_size_decl, icon_size_decl + '\nstatic CGFloat gPhotoFrameSize = 22.0;', 1)

load_anchor = 'gIconEnabled=B(@"iconEnabled",YES); gIconName=S(@"iconName",@"sparkles"); gIconSize=D(@"iconSize",22.0,10.0,80.0); gIconColor=S(@"iconColor",@"#FFFFFF");'
if load_anchor not in src:
    raise SystemExit("icon prefs load anchor not found")
src = src.replace(load_anchor, load_anchor + '\n    gPhotoFrameSize=D(@"photoFrameSize",22.0,20.0,180.0);', 1)

custom_anchor = 'BOOL custom=[gIconName isEqualToString:@"custom.photo"]&&gCustomPhotoImage;\n    BOOL sticker=custom&&LGTImageHasVisibleTransparency(gCustomPhotoImage);'
if custom_anchor not in src:
    raise SystemExit("custom photo anchor not found")
src = src.replace(custom_anchor, custom_anchor + '\n    CGFloat displaySize=custom?gPhotoFrameSize:gIconSize;', 1)

radius_old = 'icon.layer.cornerRadius=MAX(4.0,gIconSize*0.22);'
if radius_old not in src:
    raise SystemExit("photo corner radius anchor not found")
src = src.replace(radius_old, 'icon.layer.cornerRadius=MAX(4.0,displaySize*0.22);', 1)

frame_old = 'host.frame=LGTIconFrame(frame,gIconSize,gIconPosition);'
if frame_old not in src:
    raise SystemExit("icon frame anchor not found")
src = src.replace(frame_old, 'host.frame=LGTIconFrame(frame,displaySize,gIconPosition);', 1)
runtime_path.write_text(src)

# Add the user-facing Custom Photo frame-size control.
photo_path = ROOT / "prefs" / "Resources" / "Photo.plist"
photo = plistlib.loads(photo_path.read_bytes())
items = photo.get("items", [])
frame_group = {
    "cell": "PSGroupCell",
    "label": "FRAME SIZE",
    "footerText": "Controls only Custom Photo / sticker size. SF Symbol Icon Size remains separate."
}
frame_slider = {
    "cell": "PSSliderCell",
    "label": "Photo Frame Size",
    "defaults": "com.nextsolution.lockglyphtime",
    "key": "photoFrameSize",
    "default": 22,
    "min": 20,
    "max": 180,
    "showValue": True,
    "PostNotification": "com.nextsolution.lockglyphtime/ReloadPrefs"
}
# Insert before the TIP group if present.
insert_at = len(items)
for i, item in enumerate(items):
    if item.get("cell") == "PSGroupCell" and item.get("label") == "TIP":
        insert_at = i
        break
items[insert_at:insert_at] = [frame_group, frame_slider]
photo["items"] = items
photo_path.write_bytes(plistlib.dumps(photo, fmt=plistlib.FMT_XML, sort_keys=False))

# Make reset-icon restore the photo-frame size too and correct the crop hint.
prefs_path = ROOT / "prefs" / "LGTListControllerV023.m"
prefs = prefs_path.read_text()
reset_old = '@"iconEnabled",@"iconName",@"iconSize",@"iconColor"'
if reset_old not in prefs:
    raise SystemExit("resetIcon anchor not found")
prefs = prefs.replace(reset_old, '@"iconEnabled",@"iconName",@"iconSize",@"photoFrameSize",@"iconColor"', 1)
prefs = prefs.replace('Icon Size controls the lock-screen size.', 'Photo Frame Size controls the custom photo / sticker size.', 1)
prefs_path.write_text(prefs)

# Final 1.0.4 metadata.
control_path = ROOT / "control"
control = control_path.read_text()
for old in ("Version: 1.0.2", "Version: 1.0.3"):
    control = control.replace(old, "Version: 1.0.4")
if "Description:" in control:
    lines = control.splitlines()
    for i, line in enumerate(lines):
        if line.startswith("Description:"):
            lines[i] = "Description: Next Solution lock-screen customization suite for time, date, fonts, colors, positioning, shadows, SF Symbols and custom photos with transparent sticker support. Version 1.0.4 adds an independent expandable Custom Photo frame-size control up to 180pt."
            break
    control = "\n".join(lines) + "\n"
control_path.write_text(control)

resources = ROOT / "prefs" / "Resources"
info_path = resources / "Info.plist"
info = plistlib.loads(info_path.read_bytes())
info["CFBundleShortVersionString"] = "1.0.4"
info["CFBundleVersion"] = "104"
info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=False))

about_path = resources / "About.plist"
about = plistlib.loads(about_path.read_bytes())
for item in about.get("items", []):
    footer = item.get("footerText")
    if isinstance(footer, str):
        for old in ("Version 1.0.1", "Version 1.0.2", "Version 1.0.3"):
            footer = footer.replace(old, "Version 1.0.4")
        item["footerText"] = footer
about_path.write_bytes(plistlib.dumps(about, fmt=plistlib.FMT_XML, sort_keys=False))

print("Patched NextLock 1.0.4 with independent Custom Photo frame sizing (20-180pt)")
