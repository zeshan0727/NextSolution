#!/usr/bin/env python3
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parent
runtime_path = ROOT / 'RuntimeV023.xm'
runtime = runtime_path.read_text()

# ---------------------------------------------------------------------------
# NextLock 1.1.5 CPU fix
#
# 1.1.4 classified every custom photo as "sticker vs opaque photo" from
# LGTApplyPhotoFrames(). That method runs from the lock-screen layout/geometry
# path. LGTImageHasVisibleTransparency() draws the image into a temporary
# bitmap and scans its alpha bytes, which sends SpringBoard through
# CoreGraphics/vImage on every layout pass (up to four times per pass).
#
# Preserve the exact visual behavior, but classify each decoded image ONCE
# when preferences/photo data are loaded. Runtime layout then performs only a
# cached boolean lookup and reuses a cached AlwaysOriginal UIImage.
#
# Keep this patch idempotent because CI may generate sources once for static
# validation and Makefile's before-all target generates them again.
# ---------------------------------------------------------------------------

if 'static BOOL gPhotoSlotIsSticker[4]' not in runtime:
    globals_anchor = 'static UIImage *gPhotoSlotImage[4] = {nil,nil,nil,nil};'
    globals_new = globals_anchor + r'''
static UIImage *gPhotoSlotDisplayImage[4] = {nil,nil,nil,nil};
static BOOL gPhotoSlotIsSticker[4] = {NO,NO,NO,NO};'''
    if globals_anchor not in runtime:
        raise SystemExit('1.1.4 photo slot globals anchor not found')
    runtime = runtime.replace(globals_anchor, globals_new, 1)

    load_anchor = r'''    for(NSInteger i=1;i<4;i++) {
        NSString *dataKey=[NSString stringWithFormat:@"customPhotoData%ld",(long)(i+1)];
        id slotData=[prefs objectForKey:dataKey];
        gPhotoSlotData[i]=[slotData isKindOfClass:NSData.class]?slotData:nil;
        gPhotoSlotImage[i]=gPhotoSlotData[i].length?[UIImage imageWithData:gPhotoSlotData[i]]:nil;
    }'''
    load_new = load_anchor + r'''

    // EXPENSIVE IMAGE CLASSIFICATION MUST NEVER RUN FROM layoutSubviews.
    // A 32x32 alpha probe still uses CoreGraphics/vImage internally, so do it
    // once per preference/photo reload and cache the answer for each frame.
    for(NSInteger i=0;i<4;i++) {
        UIImage *decoded=gPhotoSlotImage[i];
        if(decoded) {
            gPhotoSlotIsSticker[i]=LGTImageHasVisibleTransparency(decoded);
            gPhotoSlotDisplayImage[i]=[decoded imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        } else {
            gPhotoSlotIsSticker[i]=NO;
            gPhotoSlotDisplayImage[i]=nil;
        }
    }'''
    if load_anchor not in runtime:
        raise SystemExit('1.1.4 photo decode block not found')
    runtime = runtime.replace(load_anchor, load_new, 1)

    hot_old = r'''        UIImageView *photoView=host.imageView;
        BOOL sticker=LGTImageHasVisibleTransparency(image);
        photoView.image=[image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];'''
    hot_new = r'''        UIImageView *photoView=host.imageView;
        BOOL sticker=gPhotoSlotIsSticker[i];
        UIImage *displayImage=gPhotoSlotDisplayImage[i]?:image;
        if(photoView.image != displayImage) photoView.image=displayImage;'''
    if hot_old not in runtime:
        raise SystemExit('1.1.4 per-layout transparency probe not found')
    runtime = runtime.replace(hot_old, hot_new, 1)

    runtime_path.write_text(runtime)
else:
    print('NextLock 1.1.5 runtime CPU fix already applied; skipping duplicate runtime patch')

# ---------------------------------------------------------------------------
# Metadata: 1.1.5 is a feature-preserving performance/stability release.
# ---------------------------------------------------------------------------
control_path = ROOT / 'control'
control = control_path.read_text()
if 'Version: 1.1.4' in control:
    control = control.replace('Version: 1.1.4', 'Version: 1.1.5', 1)
elif 'Version: 1.1.5' not in control:
    raise SystemExit('expected 1.1.4 or 1.1.5 control version not found')

lines = control.splitlines()
for i, line in enumerate(lines):
    if line.startswith('Description:'):
        lines[i] = ('Description: Next Solution lock-screen customization suite. '
                    'Version 1.1.5 keeps all four independent custom-photo/sticker frames '
                    'while eliminating repeated CoreGraphics/vImage transparency scans from '
                    'SpringBoard layout passes.')
        break
control_path.write_text('\n'.join(lines) + '\n')

resources = ROOT / 'prefs' / 'Resources'
info_path = resources / 'Info.plist'
info = plistlib.loads(info_path.read_bytes())
info['CFBundleShortVersionString'] = '1.1.5'
info['CFBundleVersion'] = '115'
info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=False))

about_path = resources / 'About.plist'
about = plistlib.loads(about_path.read_bytes())
for item in about.get('items', []):
    footer = item.get('footerText')
    if isinstance(footer, str):
        item['footerText'] = footer.replace('Version 1.1.4', 'Version 1.1.5')
about_path.write_bytes(plistlib.dumps(about, fmt=plistlib.FMT_XML, sort_keys=False))

print('Patched NextLock 1.1.5: cached photo transparency classification; no vImage work in layoutSubviews')
