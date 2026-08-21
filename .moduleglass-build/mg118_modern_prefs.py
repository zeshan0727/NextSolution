#!/usr/bin/env python3
# Module Glass 1.1.18 modern grouped settings layout.
import plistlib, sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit('usage: mg118_modern_prefs.py <ModuleGlassPrefs.bundle>')
bundle = Path(sys.argv[1])
p = bundle/'CCModuleBackgrounds.plist'
obj = plistlib.load(p.open('rb'))
old = obj['items']
by_key = {x.get('key'): x for x in old if x.get('key')}

def group(label, footer=''):
    d={'cell':'PSGroupCell','label':label}
    if footer: d['footerText']=footer
    return d

def module(label, slot, title, desc):
    return {'cell':'PSButtonCell','label':label,'action':'configureCCModuleBackground:','moduleSlot':slot,'moduleTitle':title,'description':desc}

def button(label, action, desc):
    return {'cell':'PSButtonCell','label':label,'action':action,'description':desc}

items=[]
items += [group('APPEARANCE','Core rendering controls. Module Glass keeps Apple module geometry and expansion behavior native.'),
          by_key['CCModuleRemoveBlur'], by_key['CCModuleBackgroundsEnabled'], by_key['CCModuleBackgroundOpacity'],
          by_key['CCModuleControlGlowEnabled'], by_key['CCModuleControlGlowIntensity'], by_key['CCModuleControlGlowWidth']]
items += [group('MEDIA & SLIDERS','Customize Apple slider and media modules while keeping their expanded states native.'),
          module('Brightness Background','brightness','Brightness','Choose or remove the custom image used behind Brightness.'),
          module('Volume Background','volume','Volume','Choose or remove the custom image used behind Volume.'),
          by_key['CCModuleVolumeIconColorEnabled'],
          button('Volume Icon Color','chooseVolumeIconColor:','Open the native iOS color picker for the Volume speaker glyph.')]
items += [group('CONNECTIVITY & MEDIA','Background images for larger Control Center modules.'),
          module('Connectivity Background','connectivity','Connectivity','Choose or remove the custom image used behind Connectivity.'),
          module('Now Playing Background','media','Now Playing','Choose or remove the custom image used behind Now Playing.'),
          module('Screen Mirroring Background','screenmirroring','Screen Mirroring','Choose or remove the custom image used behind Screen Mirroring.')]
items += [group('UTILITY MODULES','Quick-access Control Center modules.'),
          module('Focus','focus','Focus','Choose or remove the Focus background image.'),
          module('Flashlight','flashlight','Flashlight','Choose or remove the Flashlight background image.'),
          module('Timer','timer','Timer','Choose or remove the Timer background image.'),
          module('Calculator','calculator','Calculator','Choose or remove the Calculator background image.'),
          module('Camera','camera','Camera','Choose or remove the Camera background image.'),
          module('Orientation Lock','orientation','Orientation Lock','Choose or remove the Orientation Lock background image.'),
          module('Screen Recording','screenrecording','Screen Recording','Choose or remove the Screen Recording background image.')]
items += [group('OTHER MODULES','Additional built-in and third-party modules.'),
          module('Low Power Mode','lowpower','Low Power Mode','Choose or remove the Low Power Mode background image.'),
          module('Dark Mode','darkmode','Dark Mode','Choose or remove the Dark Mode background image.'),
          module('Hearing','hearing','Hearing','Choose or remove the Hearing background image.'),
          module('Notes','notes','Notes','Choose or remove the Notes background image.'),
          module('Home','home','Home','Choose or remove the Home background image.'),
          module('Other Modules','other','Other Modules','Choose or remove the fallback image used for other modules.')]
items += [group('MAINTENANCE','Reset only Module Glass images. Your other tweak preferences are not changed.'),
          button('Remove All Module Images','resetAllCCModuleBackgrounds:','Deletes every custom Control Center module background image.')]
items += [group('APPLY & RESTART','Apply refreshes Module Glass immediately. Use Respring if Control Center is already cached.'),
          button('Apply Module Glass','applyCCModuleBackgrounds:','Reload Module Glass preferences and selected images.'),
          button('Respring','respringDevice:','Restart SpringBoard and rebuild all Control Center module views.')]

obj={'title':'Module Glass','items':items}
with p.open('wb') as f: plistlib.dump(obj,f,fmt=plistlib.FMT_XML,sort_keys=False)
info=bundle/'Info.plist'
meta=plistlib.load(info.open('rb'))
meta['CFBundleName']='Module Glass'
meta['CFBundleShortVersionString']='1.1.18'
meta['CFBundleVersion']='1.1.18'
with info.open('wb') as f: plistlib.dump(meta,f,fmt=plistlib.FMT_XML,sort_keys=False)
print(f'Updated {p} with {len(items)} modern grouped specifiers')
