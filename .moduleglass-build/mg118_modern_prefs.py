#!/usr/bin/env python3
import plistlib, sys
from pathlib import Path

bundle=Path(sys.argv[1])
p=bundle/'CCModuleBackgrounds.plist'
old=plistlib.load(open(p,'rb'))
old_items=old.get('items',[])
by_slot={i.get('moduleSlot'):i for i in old_items if i.get('moduleSlot')}
by_label={i.get('label'):i for i in old_items if i.get('label')}

def group(label, footer=None):
    d={'cell':'PSGroupCell','label':label}
    if footer: d['footerText']=footer
    return d

def sw(label,key,default,desc):
    return {'cell':'PSSwitchCell','label':label,'key':key,'default':default,'defaults':'com.nextsolution.unlockvibrate','description':desc,'PostNotification':'com.nextsolution.unlockvibrate/preferences.changed'}

def slider(label,key,default,minv,maxv,desc):
    return {'cell':'PSSliderCell','label':label,'key':key,'default':default,'min':minv,'max':maxv,'showValue':True,'defaults':'com.nextsolution.unlockvibrate','description':desc,'PostNotification':'com.nextsolution.unlockvibrate/preferences.changed'}

def module(label,slot,title):
    d=dict(by_slot.get(slot,{'cell':'PSButtonCell','action':'configureCCModuleBackground:','moduleSlot':slot,'moduleTitle':title}))
    d['cell']='PSButtonCell'; d['action']='configureCCModuleBackground:'; d['label']=label; d['moduleSlot']=slot; d['moduleTitle']=title
    return d

def button(label,action,desc=''):
    d=dict(by_label.get(label,{})); d.update({'cell':'PSButtonCell','label':label,'action':action})
    if desc: d['description']=desc
    return d

items=[]
items += [group('APPEARANCE'),
          sw('Remove Module Blur','CCModuleRemoveBlur',True,'Disable the blur behind modules.'),
          sw('Enable Module Background Images','CCModuleBackgroundsEnabled',False,'Use background images for modules.'),
          sw('Glow Module Icons & Labels','CCModuleControlGlowEnabled',True,'Add a subtle glow to icons and labels.'),
          slider('Icon & Label Glow Intensity','CCModuleControlGlowIntensity',0.8,0.1,1.0,'Adjust glow intensity.'),
          slider('Background Image Opacity','CCModuleBackgroundOpacity',1.0,0.25,1.0,'Adjust background image opacity.'),
          slider('Background Image Scale','CCModuleBackgroundScale',1.0,0.5,4.0,'Background image scale control for the redesigned UI.')]
items += [group('MEDIA & SLIDERS'),
          module('Brightness Background','brightness','Brightness'),
          module('Volume Background','volume','Volume'),
          sw('Custom Volume Icon Color','CCModuleVolumeIconColorEnabled',False,'Apply a custom native speaker glyph color.'),
          button('Volume Icon Color','chooseVolumeIconColor:','Choose the Volume glyph color.')]
items += [group('CONNECTIVITY & MEDIA'),
          module('Connectivity Background','connectivity','Connectivity'),
          module('Now Playing Background','media','Now Playing'),
          module('Screen Mirroring Background','screenmirroring','Screen Mirroring')]
items += [group('UTILITY MODULES')]
for label,slot in [('Focus','focus'),('Flashlight','flashlight'),('Timer','timer'),('Calculator','calculator'),('Camera','camera'),('Orientation Lock','orientation'),('Screen Recording','screenrecording')]:
    items.append(module(label+' Background',slot,label))
items += [group('OTHER MODULES')]
for label,slot in [('Low Power Mode','lowpower'),('Dark Mode','darkmode'),('Hearing','hearing'),('Notes','notes'),('Home','home'),('Other Modules','other')]:
    items.append(module(label+' Background',slot,label))
items += [group('MAINTENANCE'),button('Remove All Module Images','resetAllCCModuleBackgrounds:','Deletes every custom module background image.')]
items += [group('APPLY & RESTART'),button('Apply Module Glass','applyCCModuleBackgrounds:'),button('Respring','respringDevice:')]

plistlib.dump({'title':'Module Glass','items':items},open(p,'wb'),fmt=plistlib.FMT_XML,sort_keys=False)
info=bundle/'Info.plist'
if info.exists():
    x=plistlib.load(open(info,'rb'))
    x['CFBundleShortVersionString']='1.1.18'
    x['CFBundleVersion']='118'
    plistlib.dump(x,open(info,'wb'),fmt=plistlib.FMT_XML,sort_keys=False)
