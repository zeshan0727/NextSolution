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

def described_slider(section, description, label, key, default, minimum, maximum):
    group(section, description)
    slider(label, key, default, minimum, maximum)

def edit(label, key, default, placeholder):
    items.append({"cell":"PSEditTextCell","label":label,"defaults":DOMAIN,"key":key,
                  "default":default,"placeholder":placeholder,"PostNotification":NOTIFY})

def choice(label, key, default, titles, values):
    items.append({"cell":"PSLinkListCell","detail":"PSListItemsController","label":label,
                  "defaults":DOMAIN,"key":key,"default":default,
                  "validTitles":titles,"validValues":values,"PostNotification":NOTIFY})

def color_button(label, action):
    items.append({"cell":"PSButtonCell","label":label,"action":action})

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

group("LockGlyphTime 0.2.1",
      "Time/date appearance is independent from the icon system. Selection rows now open dedicated lists, "
      "colors use the native iOS color picker, and position sliders use non-cumulative native label movement.")
switch("Enable LockGlyphTime", "enabled", True)

# TIME
group("Time Appearance",
      "Customize only the lock-screen clock. Tap Font, Weight, Style or Alignment to open a selection list. "
      "Tap Time Color to open Apple's native color picker.")
switch("Enable Time Customization", "customTimeEnabled", True)
color_button("Time Color", "openTimeColorPicker")
choice("Time Font", "timeFont", "Original", font_titles, font_values)
choice("Time Font Weight", "timeFontWeight", 3, weight_titles, weight_values)
choice("Time Style", "timeStyle", 0,
       ["Default","Normal","Bold","Italic","Bold Italic","Outline","Shadow","Glow"], list(range(8)))
choice("Time Alignment", "timeAlignment", 0, alignment_titles, alignment_values)

described_slider("Time Size",
                 "Changes only the clock size. 1.00 is the native size; values below 1.00 make it smaller and values above 1.00 make it larger.",
                 "Size", "timeScale", 1.0, 0.5, 2.5)
described_slider("Time Horizontal Position",
                 "Moves the clock left or right without moving the date. Negative values move LEFT; positive values move RIGHT; 0 keeps Apple's original horizontal position.",
                 "Left / Right", "timeOffsetX", 0.0, -150.0, 150.0)
described_slider("Time Vertical Position",
                 "Moves the clock up or down without moving the date. Negative values move UP; positive values move DOWN; 0 keeps Apple's original vertical position.",
                 "Up / Down", "timeOffsetY", 0.0, -150.0, 150.0)

group("Time Shadow",
      "Time shadow is independent from date and icon shadows. Tap Shadow Color to open the native color picker.")
switch("Enable Time Shadow", "timeShadowEnabled", False)
color_button("Time Shadow Color", "openTimeShadowColorPicker")
described_slider("Time Shadow Opacity",
                 "Controls shadow visibility. 0 is invisible and 1 is fully opaque.",
                 "Opacity", "timeShadowOpacity", 0.45, 0.0, 1.0)
described_slider("Time Shadow Blur",
                 "Controls the shadow blur/softness. Higher values create a wider, softer shadow.",
                 "Radius", "timeShadowRadius", 2.0, 0.0, 20.0)
described_slider("Time Shadow Horizontal Offset",
                 "Moves only the clock shadow left/right. Negative is left; positive is right.",
                 "Shadow Left / Right", "timeShadowOffsetX", 0.0, -20.0, 20.0)
described_slider("Time Shadow Vertical Offset",
                 "Moves only the clock shadow up/down. Negative is up; positive is down.",
                 "Shadow Up / Down", "timeShadowOffsetY", 1.0, -20.0, 20.0)

# DATE
group("Date Appearance",
      "The date has its own appearance and position. Tap selection rows to open their option lists, and tap Date Color for the native iOS color picker.")
switch("Enable Date Customization", "customDateEnabled", True)
color_button("Date Color", "openDateColorPicker")
choice("Date Font", "dateFont", "Original", font_titles, font_values)
choice("Date Font Weight", "dateFontWeight", 3, weight_titles, weight_values)
choice("Date Style", "dateStyle", 0,
       ["Default","Normal","Bold","Italic","Bold Italic","Uppercase","Lowercase","Outline","Shadow","Glow"],
       list(range(10)))
choice("Date Alignment", "dateAlignment", 0, alignment_titles, alignment_values)

described_slider("Date Size",
                 "Changes only the date size. 1.00 is Apple's native size; lower values reduce it and higher values enlarge it.",
                 "Size", "dateScale", 1.0, 0.5, 2.5)
described_slider("Date Horizontal Position",
                 "Moves only the date left/right. Negative values move LEFT; positive values move RIGHT.",
                 "Left / Right", "dateOffsetX", 0.0, -150.0, 150.0)
described_slider("Date Vertical Position",
                 "Moves only the date up/down. Negative values move UP; positive values move DOWN.",
                 "Up / Down", "dateOffsetY", 0.0, -150.0, 150.0)

group("Date Format",
      "Choose a ready-made date format or select Custom and enter an NSDateFormatter pattern below. This changes only the displayed lock-screen date.")
choice("Date Format", "dateFormat", "system",
       ["System Default","EEE, MMM d","EEEE, MMMM d","dd MMMM","MMM d",
        "dd/MM/yyyy","MM/dd/yyyy","yyyy-MM-dd","Custom"],
       ["system","EEE, MMM d","EEEE, MMMM d","dd MMMM","MMM d",
        "dd/MM/yyyy","MM/dd/yyyy","yyyy-MM-dd","custom"])
edit("Custom Date Format", "customDateFormat", "EEEE, MMMM d", "NSDateFormatter pattern")

group("Date Shadow",
      "Date shadow is fully independent from time and icon shadows. Tap Shadow Color for the native picker.")
switch("Enable Date Shadow", "dateShadowEnabled", False)
color_button("Date Shadow Color", "openDateShadowColorPicker")
described_slider("Date Shadow Opacity",
                 "Controls date-shadow visibility from invisible (0) to fully opaque (1).",
                 "Opacity", "dateShadowOpacity", 0.45, 0.0, 1.0)
described_slider("Date Shadow Blur",
                 "Controls date-shadow softness. Higher values make the shadow wider and softer.",
                 "Radius", "dateShadowRadius", 2.0, 0.0, 20.0)
described_slider("Date Shadow Horizontal Offset",
                 "Moves only the date shadow left/right. Negative is left; positive is right.",
                 "Shadow Left / Right", "dateShadowOffsetX", 0.0, -20.0, 20.0)
described_slider("Date Shadow Vertical Offset",
                 "Moves only the date shadow up/down. Negative is up; positive is down.",
                 "Shadow Up / Down", "dateShadowOffsetY", 1.0, -20.0, 20.0)

# ICON - preserved
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
      "All previous icon features are retained. Selection rows open real option lists. The icon is positioned after the final time/date position so its anchor follows the customized clock/date.")
switch("Show Icon", "iconEnabled", True)
choice("Icon", "iconName", "sparkles", icon_titles, icon_values)
color_button("Icon Color", "openIconColorPicker")
choice("Anchor To", "anchorTarget", 0, ["Time","Date"], [0,1])
choice("Position", "iconPosition", 1, ["Left","Right","Above","Below"], [0,1,2,3])
described_slider("Icon Size",
                 "Changes only the icon size in points. It does not change the clock or date size.",
                 "Size", "iconSize", 22.0, 10.0, 80.0)
described_slider("Icon Horizontal Offset",
                 "Fine-tunes the icon left/right after its selected anchor and position are calculated. Negative is left; positive is right.",
                 "Left / Right", "iconOffsetX", 0.0, -120.0, 120.0)
described_slider("Icon Vertical Offset",
                 "Fine-tunes the icon up/down after its selected anchor and position are calculated. Negative is up; positive is down.",
                 "Up / Down", "iconOffsetY", 0.0, -120.0, 120.0)

group("Icon Shadow",
      "Existing icon-shadow controls are preserved and remain independent from time/date shadows. Tap Shadow Color to use the native color picker.")
switch("Enable Icon Shadow", "shadowEnabled", True)
color_button("Icon Shadow Color", "openIconShadowColorPicker")
described_slider("Icon Shadow Opacity",
                 "Controls icon-shadow visibility from invisible (0) to fully opaque (1).",
                 "Opacity", "shadowOpacity", 0.45, 0.0, 1.0)
described_slider("Icon Shadow Blur",
                 "Controls icon-shadow softness. Higher values make the shadow wider and softer.",
                 "Radius", "shadowRadius", 2.0, 0.0, 20.0)
described_slider("Icon Shadow Horizontal Offset",
                 "Moves only the icon shadow left/right. Negative is left; positive is right.",
                 "Shadow Left / Right", "shadowOffsetX", 0.0, -20.0, 20.0)
described_slider("Icon Shadow Vertical Offset",
                 "Moves only the icon shadow up/down. Negative is up; positive is down.",
                 "Shadow Up / Down", "shadowOffsetY", 1.0, -20.0, 20.0)

group("Compatibility",
      "Built separately for standard rootless and RootHide. Missing private lock-screen classes or fonts fail safely. "
      "Version 0.2.1 moves time/date through their native centers instead of transform translation to improve iOS 16 lock-screen compatibility.")

output = Path(__file__).resolve().parent / "Resources" / "Root.plist"
output.write_bytes(plistlib.dumps({"title":"LockGlyphTime","items":items}, fmt=plistlib.FMT_XML, sort_keys=False))
print(f"Generated {output} with {len(items)} preference specifiers")
