#!/usr/bin/env python3
from pathlib import Path
import plistlib

DOMAIN = "com.nextsolution.lockglyphtime"
NOTIFY = "com.nextsolution.lockglyphtime/ReloadPrefs"
items = []

def group(label, footer=None):
    d={"cell":"PSGroupCell","label":label}
    if footer:d["footerText"]=footer
    items.append(d)

def switch(label,key,default):
    items.append({"cell":"PSSwitchCell","label":label,"defaults":DOMAIN,"key":key,"default":default,"PostNotification":NOTIFY})

def slider(label,key,default,minimum,maximum):
    items.append({"cell":"PSSliderCell","label":label,"defaults":DOMAIN,"key":key,"default":default,"min":minimum,"max":maximum,"showValue":True,"PostNotification":NOTIFY})

def described_slider(section,description,label,key,default,minimum,maximum):
    group(section,description);slider(label,key,default,minimum,maximum)

def edit(label,key,default,placeholder):
    items.append({"cell":"PSEditTextCell","label":label,"defaults":DOMAIN,"key":key,"default":default,"placeholder":placeholder,"PostNotification":NOTIFY})

def choice(label,key,default,titles,values):
    items.append({"cell":"PSLinkListCell","detail":"PSListItemsController","label":label,"defaults":DOMAIN,"key":key,"default":default,"validTitles":titles,"validValues":values,"PostNotification":NOTIFY})

def button(label,action):items.append({"cell":"PSButtonCell","label":label,"action":action})

font_titles=["Original / Apple","System","System Rounded","System Serif / New York","System Monospaced","Helvetica Neue","Avenir Next","Gill Sans","Futura","Georgia","Courier","Menlo","Times New Roman","Trebuchet MS","Verdana","Arial Rounded","Marker Felt","Chalkboard SE","Noteworthy","Hoefler Text","Optima","Palatino","American Typewriter","Academy Engraved","Copperplate","Party LET","Snell Roundhand"]
font_values=["Original","System","System Rounded","System Serif / New York","System Monospaced","HelveticaNeue","AvenirNext-Regular","GillSans","Futura-Medium","Georgia","Courier","Menlo-Regular","TimesNewRomanPSMT","TrebuchetMS","Verdana","ArialRoundedMTBold","MarkerFelt-Wide","ChalkboardSE-Regular","Noteworthy-Light","HoeflerText-Regular","Optima-Regular","Palatino-Roman","AmericanTypewriter","AcademyEngravedLetPlain","Copperplate","PartyLetPlain","SnellRoundhand"]
weight_titles=["Ultra Light","Thin","Light","Regular","Medium","Semibold","Bold","Heavy","Black"]
alignment_titles=["Automatic","Left","Center","Right"]

group("LockGlyphTime 0.2.2","Alignment remains the main left/center/right control. Position offsets are now applied after SpringBoard finishes its layout, with a second next-runloop pass so vertical movement is not overwritten by the clock/date relayout.")
switch("Enable LockGlyphTime","enabled",True)

group("Time Appearance","Use Alignment for the main horizontal placement. Font, Weight, Style and Alignment open selection pages; Time Color opens the native iOS picker.")
switch("Enable Time Customization","customTimeEnabled",True)
button("Time Color","openTimeColorPicker")
choice("Time Font","timeFont","Original",font_titles,font_values)
choice("Time Font Weight","timeFontWeight",3,weight_titles,list(range(9)))
choice("Time Style","timeStyle",0,["Default","Normal","Bold","Italic","Bold Italic","Outline","Shadow","Glow"],list(range(8)))
choice("Time Alignment","timeAlignment",0,alignment_titles,[0,1,2,3])
described_slider("Time Size","1.00 is Apple's native clock size. Lower values shrink the clock and higher values enlarge it.","Size","timeScale",1.0,0.5,2.5)
described_slider("Time Fine Horizontal Offset","Alignment controls the main Left/Center/Right position. Use this only for fine adjustment after alignment. Negative moves LEFT; positive moves RIGHT.","Fine Left / Right","timeOffsetX",0.0,-150.0,150.0)
described_slider("Time Vertical Position","Moves the clock vertically after SpringBoard finishes layout. Negative values move UP; positive values move DOWN.","Up / Down","timeOffsetY",0.0,-150.0,150.0)

group("Time Shadow","Independent clock shadow. Tap Shadow Color to use the native color picker.")
switch("Enable Time Shadow","timeShadowEnabled",False);button("Time Shadow Color","openTimeShadowColorPicker")
described_slider("Time Shadow Opacity","0 is invisible; 1 is fully opaque.","Opacity","timeShadowOpacity",0.45,0.0,1.0)
described_slider("Time Shadow Blur","Higher values make the shadow wider and softer.","Radius","timeShadowRadius",2.0,0.0,20.0)
described_slider("Time Shadow Horizontal Offset","Negative moves the shadow left; positive moves it right.","Shadow Left / Right","timeShadowOffsetX",0.0,-20.0,20.0)
described_slider("Time Shadow Vertical Offset","Negative moves the shadow up; positive moves it down.","Shadow Up / Down","timeShadowOffsetY",1.0,-20.0,20.0)

group("Date Appearance","Date Alignment controls the main horizontal placement. Date vertical position is applied after SpringBoard layout just like Time.")
switch("Enable Date Customization","customDateEnabled",True);button("Date Color","openDateColorPicker")
choice("Date Font","dateFont","Original",font_titles,font_values)
choice("Date Font Weight","dateFontWeight",3,weight_titles,list(range(9)))
choice("Date Style","dateStyle",0,["Default","Normal","Bold","Italic","Bold Italic","Uppercase","Lowercase","Outline","Shadow","Glow"],list(range(10)))
choice("Date Alignment","dateAlignment",0,alignment_titles,[0,1,2,3])
described_slider("Date Size","1.00 is Apple's native date size. Lower values shrink it and higher values enlarge it.","Size","dateScale",1.0,0.5,2.5)
described_slider("Date Fine Horizontal Offset","Alignment is the main Left/Center/Right control. This slider performs only fine X adjustment.","Fine Left / Right","dateOffsetX",0.0,-150.0,150.0)
described_slider("Date Vertical Position","Negative values move the date UP; positive values move it DOWN after Apple's layout is complete.","Up / Down","dateOffsetY",0.0,-150.0,150.0)

group("Date Format","Select Custom to use the NSDateFormatter pattern below.")
choice("Date Format","dateFormat","system",["System Default","EEE, MMM d","EEEE, MMMM d","dd MMMM","MMM d","dd/MM/yyyy","MM/dd/yyyy","yyyy-MM-dd","Custom"],["system","EEE, MMM d","EEEE, MMMM d","dd MMMM","MMM d","dd/MM/yyyy","MM/dd/yyyy","yyyy-MM-dd","custom"])
edit("Custom Date Format","customDateFormat","EEEE, MMMM d","NSDateFormatter pattern")

group("Date Shadow","Independent date shadow.")
switch("Enable Date Shadow","dateShadowEnabled",False);button("Date Shadow Color","openDateShadowColorPicker")
described_slider("Date Shadow Opacity","0 is invisible; 1 is fully opaque.","Opacity","dateShadowOpacity",0.45,0.0,1.0)
described_slider("Date Shadow Blur","Higher values make the shadow wider and softer.","Radius","dateShadowRadius",2.0,0.0,20.0)
described_slider("Date Shadow Horizontal Offset","Negative is left; positive is right.","Shadow Left / Right","dateShadowOffsetX",0.0,-20.0,20.0)
described_slider("Date Shadow Vertical Offset","Negative is up; positive is down.","Shadow Up / Down","dateShadowOffsetY",1.0,-20.0,20.0)

icon_titles=["Sparkles","Star","Heart","Bolt","Moon","Sun","Cloud","Flame","Drop","Leaf","Bell","Lock","Key","Shield","Person","House","Location","Paper Plane","Envelope","Phone","Camera","Photo (Custom)","Photo Symbol","Music","Headphones","Game Controller","Clock","Calendar","Alarm","Gift","Crown","Globe","Wi-Fi"]
icon_values=["sparkles","star.fill","heart.fill","bolt.fill","moon.fill","sun.max.fill","cloud.fill","flame.fill","drop.fill","leaf.fill","bell.fill","lock.fill","key.fill","shield.fill","person.fill","house.fill","location.fill","paperplane.fill","envelope.fill","phone.fill","camera.fill","custom.photo","photo.fill","music.note","headphones","gamecontroller.fill","clock.fill","calendar","alarm.fill","gift.fill","crown.fill","globe","wifi"]

group("Icon","All existing icon controls remain. Select Photo (Custom) to use the cropped photo saved below.")
switch("Show Icon","iconEnabled",True);choice("Icon","iconName","sparkles",icon_titles,icon_values);button("Icon Color","openIconColorPicker")
choice("Anchor To","anchorTarget",0,["Time","Date"],[0,1]);choice("Position","iconPosition",1,["Left","Right","Above","Below"],[0,1,2,3])
described_slider("Icon Size","Controls the final on-screen icon frame in points. For a custom photo, this changes the icon frame—not the original photo dimensions.","Size","iconSize",22.0,10.0,80.0)
described_slider("Icon Horizontal Offset","Fine-tunes the icon after anchor placement. Negative is left; positive is right.","Left / Right","iconOffsetX",0.0,-120.0,120.0)
described_slider("Icon Vertical Offset","Fine-tunes the icon after anchor placement. Negative is up; positive is down.","Up / Down","iconOffsetY",0.0,-120.0,120.0)

group("Custom Photo Icon","Choose / Edit Photo opens the system photo selector and then a square crop/zoom editor. The saved photo is resized to 512×512 so it fits the exact icon frame cleanly. Choosing a photo automatically selects Photo (Custom).")
button("Choose / Edit Photo","openCustomPhotoPicker");button("Remove Custom Photo","removeCustomPhoto")

group("Icon Shadow","Works for SF Symbols and Custom Photo.")
switch("Enable Icon Shadow","shadowEnabled",True);button("Icon Shadow Color","openIconShadowColorPicker")
described_slider("Icon Shadow Opacity","0 is invisible; 1 is fully opaque.","Opacity","shadowOpacity",0.45,0.0,1.0)
described_slider("Icon Shadow Blur","Higher values make the shadow wider and softer.","Radius","shadowRadius",2.0,0.0,20.0)
described_slider("Icon Shadow Horizontal Offset","Negative is left; positive is right.","Shadow Left / Right","shadowOffsetX",0.0,-20.0,20.0)
described_slider("Icon Shadow Vertical Offset","Negative is up; positive is down.","Shadow Up / Down","shadowOffsetY",1.0,-20.0,20.0)

group("Compatibility","Version 0.2.2 keeps Alignment as the primary horizontal control and reapplies X/Y offsets after text styling and after the current SpringBoard layout pass. Custom photos are stored in preferences as a resized image, avoiding jailbreak-specific file paths.")

output=Path(__file__).resolve().parent/"Resources"/"Root.plist"
output.write_bytes(plistlib.dumps({"title":"LockGlyphTime","items":items},fmt=plistlib.FMT_XML,sort_keys=False))
print(f"Generated {output} with {len(items)} preference specifiers")
