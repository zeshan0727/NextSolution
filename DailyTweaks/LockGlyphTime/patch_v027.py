#!/usr/bin/env python3
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parent
runtime_path = ROOT / "RuntimeV023.xm"
src = runtime_path.read_text()

# Replace the single square-only photo size with independent width/height.
decl_old = 'static CGFloat gPhotoFrameSize = 22.0;'
decl_new = 'static CGFloat gPhotoFrameWidth = 22.0;\nstatic CGFloat gPhotoFrameHeight = 22.0;'
if decl_old not in src:
    raise SystemExit("1.0.4 photo frame declaration not found")
src = src.replace(decl_old, decl_new, 1)

load_old = '    gPhotoFrameSize=D(@"photoFrameSize",22.0,20.0,180.0);'
load_new = '''    CGFloat legacyPhotoFrameSize=D(@"photoFrameSize",22.0,20.0,600.0);
    gPhotoFrameWidth=D(@"photoFrameWidth",legacyPhotoFrameSize,20.0,600.0);
    gPhotoFrameHeight=D(@"photoFrameHeight",legacyPhotoFrameSize,20.0,600.0);'''
if load_old not in src:
    raise SystemExit("1.0.4 photo frame load line not found")
src = src.replace(load_old, load_new, 1)

size_old = '    CGFloat displaySize=custom?gPhotoFrameSize:gIconSize;'
size_new = '    CGFloat photoCornerBasis=MIN(gPhotoFrameWidth,gPhotoFrameHeight);'
if size_old not in src:
    raise SystemExit("1.0.4 display size line not found")
src = src.replace(size_old, size_new, 1)

radius_old = 'icon.layer.cornerRadius=MAX(4.0,displaySize*0.22);'
radius_new = 'icon.layer.cornerRadius=MAX(4.0,photoCornerBasis*0.22);'
if radius_old not in src:
    raise SystemExit("1.0.4 corner radius line not found")
src = src.replace(radius_old, radius_new, 1)

# Rectangular anchor-aware frame calculation for custom photos.
apply_anchor = 'static void LGTApplyIcon(UIView *container,UILabel *time,UILabel *date) {'
if apply_anchor not in src:
    raise SystemExit("LGTApplyIcon anchor not found")
rect_helper = r'''static CGRect LGTPhotoFrame(CGRect anchor,CGFloat width,CGFloat height,NSInteger position) {
    CGFloat spacing=8.0;
    CGFloat x=CGRectGetMaxX(anchor)+spacing;
    CGFloat y=CGRectGetMidY(anchor)-height/2.0;
    if(position==0){
        x=CGRectGetMinX(anchor)-width-spacing;
        y=CGRectGetMidY(anchor)-height/2.0;
    } else if(position==2){
        x=CGRectGetMidX(anchor)-width/2.0;
        y=CGRectGetMinY(anchor)-height-spacing;
    } else if(position==3){
        x=CGRectGetMidX(anchor)-width/2.0;
        y=CGRectGetMaxY(anchor)+spacing;
    }
    return CGRectMake(x+gIconOffsetX,y+gIconOffsetY,width,height);
}

'''
src = src.replace(apply_anchor, rect_helper + apply_anchor, 1)

frame_old = 'host.frame=LGTIconFrame(frame,displaySize,gIconPosition);'
frame_new = 'host.frame=custom?LGTPhotoFrame(frame,gPhotoFrameWidth,gPhotoFrameHeight,gIconPosition):LGTIconFrame(frame,gIconSize,gIconPosition);'
if frame_old not in src:
    raise SystemExit("1.0.4 host frame line not found")
src = src.replace(frame_old, frame_new, 1)
runtime_path.write_text(src)

# Replace the single Photo Frame Size slider with independent Width/Height sliders.
photo_path = ROOT / "prefs" / "Resources" / "Photo.plist"
photo = plistlib.loads(photo_path.read_bytes())
items = photo.get("items", [])
filtered = []
for item in items:
    if item.get("cell") == "PSGroupCell" and item.get("label") == "FRAME SIZE":
        continue
    if item.get("key") == "photoFrameSize":
        continue
    filtered.append(item)
items = filtered

dim_group = {
    "cell": "PSGroupCell",
    "label": "PHOTO DIMENSIONS",
    "footerText": "Width and height are independent. Increase either dimension up to 600pt for wide banners, tall portraits, large photos or transparent stickers."
}
width_slider = {
    "cell": "PSSliderCell",
    "label": "Photo Width",
    "defaults": "com.nextsolution.lockglyphtime",
    "key": "photoFrameWidth",
    "default": 22,
    "min": 20,
    "max": 600,
    "showValue": True,
    "PostNotification": "com.nextsolution.lockglyphtime/ReloadPrefs"
}
height_slider = {
    "cell": "PSSliderCell",
    "label": "Photo Height",
    "defaults": "com.nextsolution.lockglyphtime",
    "key": "photoFrameHeight",
    "default": 22,
    "min": 20,
    "max": 600,
    "showValue": True,
    "PostNotification": "com.nextsolution.lockglyphtime/ReloadPrefs"
}
insert_at = len(items)
for i, item in enumerate(items):
    if item.get("cell") == "PSGroupCell" and item.get("label") == "TIP":
        insert_at = i
        break
items[insert_at:insert_at] = [dim_group, width_slider, height_slider]
photo["items"] = items
photo_path.write_bytes(plistlib.dumps(photo, fmt=plistlib.FMT_XML, sort_keys=False))

# Reset and help text.
prefs_path = ROOT / "prefs" / "LGTListControllerV023.m"
prefs = prefs_path.read_text()
reset_old = '@"iconEnabled",@"iconName",@"iconSize",@"photoFrameSize",@"iconColor"'
reset_new = '@"iconEnabled",@"iconName",@"iconSize",@"photoFrameSize",@"photoFrameWidth",@"photoFrameHeight",@"iconColor"'
if reset_old not in prefs:
    raise SystemExit("1.0.4 resetIcon keys not found")
prefs = prefs.replace(reset_old, reset_new, 1)
prefs = prefs.replace('Photo Frame Size controls the custom photo / sticker size.', 'Photo Width and Photo Height independently control the custom photo / sticker frame.', 1)
prefs_path.write_text(prefs)

# Final 1.0.5 package metadata.
control_path = ROOT / "control"
control = control_path.read_text()
control = control.replace('Version: 1.0.4', 'Version: 1.0.5', 1)
lines = control.splitlines()
for i, line in enumerate(lines):
    if line.startswith('Description:'):
        lines[i] = 'Description: Next Solution lock-screen customization suite for time, date, fonts, colors, positioning, shadows, SF Symbols and custom photos with transparent sticker support. Version 1.0.5 adds independent Custom Photo width and height controls up to 600pt.'
        break
control_path.write_text('\n'.join(lines) + '\n')

resources = ROOT / "prefs" / "Resources"
info_path = resources / "Info.plist"
info = plistlib.loads(info_path.read_bytes())
info["CFBundleShortVersionString"] = "1.0.5"
info["CFBundleVersion"] = "105"
info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=False))

about_path = resources / "About.plist"
about = plistlib.loads(about_path.read_bytes())
for item in about.get("items", []):
    footer = item.get("footerText")
    if isinstance(footer, str):
        for old in ("Version 1.0.1", "Version 1.0.2", "Version 1.0.3", "Version 1.0.4"):
            footer = footer.replace(old, "Version 1.0.5")
        item["footerText"] = footer
about_path.write_bytes(plistlib.dumps(about, fmt=plistlib.FMT_XML, sort_keys=False))

print("Patched NextLock 1.0.5 with independent Custom Photo width/height controls (20-600pt)")
