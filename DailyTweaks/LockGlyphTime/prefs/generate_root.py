#!/usr/bin/env python3
from pathlib import Path
import plistlib

DOMAIN="com.nextsolution.lockglyphtime"
NOTIFY="com.nextsolution.lockglyphtime/ReloadPrefs"
OUT=Path(__file__).resolve().parent/"Resources"
OUT.mkdir(parents=True,exist_ok=True)

font_titles=["Original / Apple","System","System Rounded","System Serif / New York","System Monospaced","Helvetica Neue","Avenir Next","Gill Sans","Futura","Georgia","Courier","Menlo","Times New Roman","Trebuchet MS","Verdana","Arial Rounded","Marker Felt","Chalkboard SE","Noteworthy","Hoefler Text","Optima","Palatino","American Typewriter","Academy Engraved","Copperplate","Party LET","Snell Roundhand"]
font_values=["Original","System","System Rounded","System Serif / New York","System Monospaced","HelveticaNeue","AvenirNext-Regular","GillSans","Futura-Medium","Georgia","Courier","Menlo-Regular","TimesNewRomanPSMT","TrebuchetMS","Verdana","ArialRoundedMTBold","MarkerFelt-Wide","ChalkboardSE-Regular","Noteworthy-Light","HoeflerText-Regular","Optima-Regular","Palatino-Roman","AmericanTypewriter","AcademyEngravedLetPlain","Copperplate","PartyLetPlain","SnellRoundhand"]
weights=["Ultra Light","Thin","Light","Regular","Medium","Semibold","Bold","Heavy","Black"]
aligns=["Automatic","Left","Center","Right"]


def group(label,footer=None):
 d={"cell":"PSGroupCell","label":label}
 if footer:d["footerText"]=footer
 return d

def switch(label,key,default):return {"cell":"PSSwitchCell","label":label,"defaults":DOMAIN,"key":key,"default":default,"PostNotification":NOTIFY}
def slider(label,key,default,mn,mx):return {"cell":"PSSliderCell","label":label,"defaults":DOMAIN,"key":key,"default":default,"min":mn,"max":mx,"showValue":True,"PostNotification":NOTIFY}
def choice(label,key,default,titles,values):return {"cell":"PSLinkListCell","detail":"PSListItemsController","label":label,"defaults":DOMAIN,"key":key,"default":default,"validTitles":titles,"validValues":values,"PostNotification":NOTIFY}
def edit(label,key,default,placeholder):return {"cell":"PSEditTextCell","label":label,"defaults":DOMAIN,"key":key,"default":default,"placeholder":placeholder,"PostNotification":NOTIFY}
def button(label,action):return {"cell":"PSButtonCell","label":label,"action":action}
def link(label,detail):return {"cell":"PSLinkCell","label":label,"detail":detail}
def save(name,title,items):
 (OUT/f"{name}.plist").write_bytes(plistlib.dumps({"title":title,"items":items},fmt=plistlib.FMT_XML,sort_keys=False))

root=[
 group("GENERAL","NextStyle gives you precise control over your Lock Screen while keeping Apple's native layout as the safe baseline."),
 switch("Enable NextStyle","enabled",True),
 button("Apply Changes","applyNow"),
 group("CUSTOMIZE"),
 link("Time","LGTTimeController"),link("Date","LGTDateController"),link("Icon","LGTIconController"),link("Custom Photo","LGTPhotoController"),
 group("MORE"),link("Advanced","LGTAdvancedController"),link("About NextStyle","LGTAboutController"),
 group("","Crafted with care by Next Solution • nextsolution.cc")
]
save("Root","NextStyle",root)

time=[
 group("APPEARANCE","Style the Lock Screen clock independently."),switch("Enable Time Customization","customTimeEnabled",True),button("Color","openTimeColorPicker"),choice("Font","timeFont","Original",font_titles,font_values),choice("Font Weight","timeFontWeight",3,weights,list(range(9))),choice("Style","timeStyle",0,["Default","Normal","Bold","Italic","Bold Italic","Outline","Shadow","Glow"],list(range(8))),choice("Alignment","timeAlignment",0,aligns,[0,1,2,3]),slider("Size","timeScale",1.0,0.5,2.5),
 group("POSITION","Negative values move left/up; positive values move right/down."),slider("Horizontal Offset","timeOffsetX",0.0,-150.0,150.0),slider("Vertical Offset","timeOffsetY",0.0,-150.0,150.0),
 group("SHADOW","Give the clock depth without changing the date or icon."),switch("Enable Shadow","timeShadowEnabled",False),button("Shadow Color","openTimeShadowColorPicker"),slider("Opacity","timeShadowOpacity",0.45,0,1),slider("Blur","timeShadowRadius",2,0,20),slider("X Offset","timeShadowOffsetX",0,-20,20),slider("Y Offset","timeShadowOffsetY",1,-20,20),
 group(""),button("Reset Time Settings","resetTime")
]
save("Time","Time",time)

date=[
 group("APPEARANCE","Customize the date independently from the clock."),switch("Enable Date Customization","customDateEnabled",True),button("Color","openDateColorPicker"),choice("Font","dateFont","Original",font_titles,font_values),choice("Font Weight","dateFontWeight",3,weights,list(range(9))),choice("Style","dateStyle",0,["Default","Normal","Bold","Italic","Bold Italic","Uppercase","Lowercase","Outline","Shadow","Glow"],list(range(10))),choice("Alignment","dateAlignment",0,aligns,[0,1,2,3]),slider("Size","dateScale",1.0,0.5,2.5),
 group("FORMAT","Use System Default or choose a formatter. Custom accepts NSDateFormatter patterns."),choice("Date Format","dateFormat","system",["System Default","EEE, MMM d","EEEE, MMMM d","dd MMMM","MMM d","dd/MM/yyyy","MM/dd/yyyy","yyyy-MM-dd","Custom"],["system","EEE, MMM d","EEEE, MMMM d","dd MMMM","MMM d","dd/MM/yyyy","MM/dd/yyyy","yyyy-MM-dd","custom"]),edit("Custom Format","customDateFormat","EEEE, MMMM d","NSDateFormatter pattern"),
 group("POSITION","Negative values move left/up; positive values move right/down."),slider("Horizontal Offset","dateOffsetX",0,-150,150),slider("Vertical Offset","dateOffsetY",0,-150,150),
 group("SHADOW"),switch("Enable Shadow","dateShadowEnabled",False),button("Shadow Color","openDateShadowColorPicker"),slider("Opacity","dateShadowOpacity",0.45,0,1),slider("Blur","dateShadowRadius",2,0,20),slider("X Offset","dateShadowOffsetX",0,-20,20),slider("Y Offset","dateShadowOffsetY",1,-20,20),
 group(""),button("Reset Date Settings","resetDate")
]
save("Date","Date",date)

icon_titles=["Sparkles","Star","Heart","Bolt","Moon","Sun","Cloud","Flame","Drop","Leaf","Bell","Lock","Key","Shield","Person","House","Location","Paper Plane","Envelope","Phone","Camera","Photo (Custom)","Photo Symbol","Music","Headphones","Game Controller","Clock","Calendar","Alarm","Gift","Crown","Globe","Wi-Fi"]
icon_values=["sparkles","star.fill","heart.fill","bolt.fill","moon.fill","sun.max.fill","cloud.fill","flame.fill","drop.fill","leaf.fill","bell.fill","lock.fill","key.fill","shield.fill","person.fill","house.fill","location.fill","paperplane.fill","envelope.fill","phone.fill","camera.fill","custom.photo","photo.fill","music.note","headphones","gamecontroller.fill","clock.fill","calendar","alarm.fill","gift.fill","crown.fill","globe","wifi"]
icon=[
 group("APPEARANCE","Use an SF Symbol or choose Custom Photo for your own image."),switch("Show Icon","iconEnabled",True),choice("Icon Type","iconName","sparkles",icon_titles,icon_values),button("Icon Color","openIconColorPicker"),slider("Icon Size","iconSize",22,10,80),choice("Anchor To","anchorTarget",0,["Time","Date"],[0,1]),
 group("POSITION"),choice("Placement","iconPosition",1,["Left","Right","Above","Below"],[0,1,2,3]),slider("Horizontal Offset","iconOffsetX",0,-120,120),slider("Vertical Offset","iconOffsetY",0,-120,120),
 group("SHADOW","Shadow works with symbols, rounded photos and transparent sticker images."),switch("Enable Shadow","shadowEnabled",True),button("Shadow Color","openIconShadowColorPicker"),slider("Opacity","shadowOpacity",0.45,0,1),slider("Blur","shadowRadius",2,0,20),slider("X Offset","shadowOffsetX",0,-20,20),slider("Y Offset","shadowOffsetY",1,-20,20),
 group(""),button("Reset Icon Settings","resetIcon")
]
save("Icon","Icon",icon)

photo=[
 group("CUSTOM PHOTO","Choose an image from Photos and crop/zoom it. Transparent PNG or sticker-style images preserve transparency; normal photos appear as rounded squares."),button("Choose / Edit Photo","openCustomPhotoPicker"),button("Remove Custom Photo","removeCustomPhoto"),
 group("TIP","For a sticker look, select a PNG with transparent pixels. NextStyle automatically detects transparency and removes the square crop at runtime.")
]
save("Photo","Custom Photo",photo)

advanced=[
 group("TOOLS","Changes reload live. Use Apply Changes if SpringBoard needs an immediate refresh."),button("Apply Changes","applyNow"),
 group("RESET"),button("Reset Time Settings","resetTime"),button("Reset Date Settings","resetDate"),button("Reset Icon Settings","resetIcon"),button("Reset All Settings","resetAll"),
 group("COMPATIBILITY","Built for iOS 15+ jailbreak environments with separate Rootless and RootHide packages. Positioning is applied after Apple's lock-screen layout to avoid cumulative movement.")
]
save("Advanced","Advanced",advanced)

about=[
 group("NEXTSTYLE","Lock Screen, your way.\nVersion 1.0.0 • by Next Solution"),
 button("Website — nextsolution.cc","openWebsite"),button("YouTube — Next Solution","openYouTube"),
 group("FEATURES","Independent time/date styling • 27 fonts • colors • alignment • position • shadows • date formats • 30+ symbols • transparent sticker photos • rounded photo icons."),
 group("","© 2026 Next Solution")
]
save("About","About",about)
print("Generated NextStyle preference pages")
