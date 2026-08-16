#!/usr/bin/env python3
from pathlib import Path
import plistlib

DOMAIN = "com.nextsolution.lockglyphtime"
NOTIFY = "com.nextsolution.lockglyphtime/ReloadPrefs"
items = []

def group(label, footer=None):
    d = {"cell": "PSGroupCell", "label": label}
    if footer:
        d["footerText"] = footer
    items.append(d)

def switch(label, key, default):
    items.append({"cell":"PSSwitchCell","label":label,"defaults":DOMAIN,"key":key,
                  "default":default,"PostNotification":NOTIFY})

def slider(label, key, default, minimum, maximum):
    items.append({"cell":"PSSliderCell","label":label,"defaults":DOMAIN,"key":key,
                  "default":default,"min":minimum,"max":maximum,"showValue":True,
                  "PostNotification":NOTIFY})

def edit(label, key, default, placeholder):
    items.append({"cell":"PSEditTextCell","label":label,"defaults":DOMAIN,"key":key,
                  "default":default,"placeholder":placeholder,"PostNotification":NOTIFY})

def multi(label, key, default, titles, values):
    items.append({"cell":"PSMultiValueCell","label":label,"defaults":DOMAIN,"key":key,
                  "default":default,"validTitles":titles,"validValues":values,
                  "PostNotification":NOTIFY})

font_titles = [
    "Original / Apple","System","System Rounded","System Serif / New York","System Monospaced",
    "Helvetica Neue","Avenir Next","Gill Sans","Futura","Georgia","Courier","Menlo",
    "Times New Roman","Trebuchet MS","Verdana","Arial Rounded","Marker Felt","Chalkboard SE",
    "Noteworthy","Hoefler Text","Optima","Palatino","American Typewriter","Academy Engraved",
    "Copperplate","Party LET","Snell Roundhand"
]
font_values = [
    "Original","System","System Rounded","System Serif / New York","System Monospaced",
    "HelveticaNeue","AvenirNext-Regular","GillSans","Futura-Medium","Georgia","Courier",
    "Menlo-Regular","TimesNewRomanPSMT","TrebuchetMS","Verdana","ArialRoundedMTBold",
    "MarkerFelt-Wide","ChalkboardSE-Regular","Noteworthy-Light","HoeflerText-Regular",
    "Optima-Regular","Palatino-Roman","AmericanTypewriter","AcademyEngravedLetPlain",
    "Copperplate","PartyLetPlain","SnellRoundhand"
]
weight_titles = ["Ultra Light","Thin","Light","Regular","Medium","Semibold","Bold","Heavy","Black"]
weight_values = list(range(9))
alignment_titles = ["Automatic","Left","Center","Right"]
alignment_values = [0,1,2,3]

group("Lock Screen",
      "LockGlyphTime 0.2 adds independent time/date appearance while keeping all existing icon settings. "
      "Changes reload live when the lock-screen date view is active.")
switch("Enable LockGlyphTime", "enabled", True)

group("Time",
      "Customize the clock independently from the date. Original / Apple preserves the native lock-screen font family.")
switch("Enable Time Customization", "customTimeEnabled", True)
slider("Time Size", "timeScale", 1.0, 0.5, 2.5)
edit("Time Color", "timeColor", "#FFFFFF", "#FFFFFF or #RRGGBBAA")
multi("Time Font", "timeFont", "Original", font_titles, font_values)
multi("Time Font Weight", "timeFontWeight", 3, weight_titles, weight_values)
multi("Time Style", "timeStyle", 0,
      ["Default","Normal","Bold","Italic","Bold Italic","Outline","Shadow","Glow"], list(range(8)))
multi("Time Alignment", "timeAlignment", 0, alignment_titles, alignment_values)
slider("Time Horizontal Position", "timeOffsetX", 0.0, -150.0, 150.0)
slider("Time Vertical Position", "timeOffsetY", 0.0, -150.0, 150.0)

group("Time Shadow",
      "Independent from the icon shadow. Shadow/Glow styles can provide a preset effect when this switch is off.")
switch("Enable Time Shadow", "timeShadowEnabled", False)
edit("Time Shadow Color", "timeShadowColor", "#000000", "#000000")
slider("Time Shadow Opacity", "timeShadowOpacity", 0.45, 0.0, 1.0)
slider("Time Shadow Radius", "timeShadowRadius", 2.0, 0.0, 20.0)
slider("Time Shadow X Offset", "timeShadowOffsetX", 0.0, -20.0, 20.0)
slider("Time Shadow Y Offset", "timeShadowOffsetY", 1.0, -20.0, 20.0)

group("Date", "The date has its own size, position, color, font, style and formatting controls.")
switch("Enable Date Customization", "customDateEnabled", True)
slider("Date Size", "dateScale", 1.0, 0.5, 2.5)
edit("Date Color", "dateColor", "#FFFFFF", "#FFFFFF or #RRGGBBAA")
multi("Date Font", "dateFont", "Original", font_titles, font_values)
multi("Date Font Weight", "dateFontWeight", 3, weight_titles, weight_values)
multi("Date Style", "dateStyle", 0,
      ["Default","Normal","Bold","Italic","Bold Italic","Uppercase","Lowercase","Outline","Shadow","Glow"],
      list(range(10)))
multi("Date Alignment", "dateAlignment", 0, alignment_titles, alignment_values)
slider("Date Horizontal Position", "dateOffsetX", 0.0, -150.0, 150.0)
slider("Date Vertical Position", "dateOffsetY", 0.0, -150.0, 150.0)
multi("Date Format", "dateFormat", "system",
      ["System Default","EEE, MMM d","EEEE, MMMM d","dd MMMM","MMM d",
       "dd/MM/yyyy","MM/dd/yyyy","yyyy-MM-dd","Custom"],
      ["system","EEE, MMM d","EEEE, MMMM d","dd MMMM","MMM d",
       "dd/MM/yyyy","MM/dd/yyyy","yyyy-MM-dd","custom"])
edit("Custom Date Format", "customDateFormat", "EEEE, MMMM d", "NSDateFormatter pattern")

group("Date Shadow", "Independent from time and icon shadows.")
switch("Enable Date Shadow", "dateShadowEnabled", False)
edit("Date Shadow Color", "dateShadowColor", "#000000", "#000000")
slider("Date Shadow Opacity", "dateShadowOpacity", 0.45, 0.0, 1.0)
slider("Date Shadow Radius", "dateShadowRadius", 2.0, 0.0, 20.0)
slider("Date Shadow X Offset", "dateShadowOffsetX", 0.0, -20.0, 20.0)
slider("Date Shadow Y Offset", "dateShadowOffsetY", 1.0, -20.0, 20.0)

icon_titles = [
    "Sparkles","Star","Heart","Bolt","Moon","Sun","Cloud","Flame","Drop","Leaf","Bell","Lock","Key","Shield",
    "Person","House","Location","Paper Plane","Envelope","Phone","Camera","Photo","Music","Headphones",
    "Game Controller","Clock","Calendar","Alarm","Gift","Crown","Globe","Wi-Fi"
]
icon_values = [
    "sparkles","star.fill","heart.fill","bolt.fill","moon.fill","sun.max.fill","cloud.fill","flame.fill",
    "drop.fill","leaf.fill","bell.fill","lock.fill","key.fill","shield.fill","person.fill","house.fill",
    "location.fill","paperplane.fill","envelope.fill","phone.fill","camera.fill","photo.fill","music.note",
    "headphones","gamecontroller.fill","clock.fill","calendar","alarm.fill","gift.fill","crown.fill","globe","wifi"
]

group("Icon",
      "Existing icon controls are preserved. Icon placement is calculated after time/date customization "
      "so anchors follow the final clock/date geometry.")
switch("Show Icon", "iconEnabled", True)
multi("Icon", "iconName", "sparkles", icon_titles, icon_values)
slider("Icon Size", "iconSize", 22.0, 10.0, 80.0)
edit("Icon Color", "iconColor", "#FFFFFF", "#FFFFFF")
multi("Anchor To", "anchorTarget", 0, ["Time","Date"], [0,1])
multi("Position", "iconPosition", 1, ["Left","Right","Above","Below"], [0,1,2,3])
slider("Icon Horizontal Offset", "iconOffsetX", 0.0, -120.0, 120.0)
slider("Icon Vertical Offset", "iconOffsetY", 0.0, -120.0, 120.0)

group("Icon Shadow")
switch("Enable Icon Shadow", "shadowEnabled", True)
edit("Icon Shadow Color", "shadowColor", "#000000", "#000000")
slider("Icon Shadow Opacity", "shadowOpacity", 0.45, 0.0, 1.0)
slider("Icon Shadow Radius", "shadowRadius", 2.0, 0.0, 20.0)
slider("Icon Shadow X Offset", "shadowOffsetX", 0.0, -20.0, 20.0)
slider("Icon Shadow Y Offset", "shadowOffsetY", 1.0, -20.0, 20.0)

group("Compatibility",
      "Built separately for standard rootless and RootHide. Runtime class/label detection fails safely if "
      "the supported lock-screen date hierarchy is not found. Missing fonts fall back to the native font.")

output = Path(__file__).resolve().parent / "Resources" / "Root.plist"
output.write_bytes(plistlib.dumps({"title":"LockGlyphTime","items":items},
                                  fmt=plistlib.FMT_XML, sort_keys=False))
print(f"Generated {output} with {len(items)} preference specifiers")
