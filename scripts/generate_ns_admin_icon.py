from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import json
import math

OUT = Path('NextSolutionLicenseAdmin/Resources/Assets.xcassets/AppIcon.appiconset')
RES = Path('NextSolutionLicenseAdmin/Resources')
OUT.mkdir(parents=True, exist_ok=True)
RES.mkdir(parents=True, exist_ok=True)

W = H = 1024
img = Image.new('RGB', (W, H), (10, 15, 34))
p = img.load()

# Deep midnight -> electric indigo gradient with a subtle cyan lift.
for y in range(H):
    ty = y / (H - 1)
    for x in range(W):
        tx = x / (W - 1)
        r = int(10 + 20 * tx + 33 * (1 - ty))
        g = int(15 + 27 * tx + 20 * (1 - ty))
        b = int(34 + 78 * tx + 46 * (1 - ty))
        p[x, y] = (min(r,255), min(g,255), min(b,255))

# Soft glows for depth.
def glow(cx, cy, radius, color, alpha):
    layer = Image.new('RGBA', (W, H), (0,0,0,0))
    d = ImageDraw.Draw(layer)
    d.ellipse((cx-radius, cy-radius, cx+radius, cy+radius), fill=(*color, alpha))
    layer = layer.filter(ImageFilter.GaussianBlur(radius//2))
    return layer

base = img.convert('RGBA')
base = Image.alpha_composite(base, glow(820, 180, 300, (79, 108, 255), 155))
base = Image.alpha_composite(base, glow(190, 850, 330, (0, 210, 255), 80))
base = Image.alpha_composite(base, glow(520, 520, 390, (100, 72, 255), 45))

# Glass plate.
plate = Image.new('RGBA', (W, H), (0,0,0,0))
d = ImageDraw.Draw(plate)
d.rounded_rectangle((146, 146, 878, 878), radius=196, fill=(255,255,255,22), outline=(255,255,255,44), width=3)
plate = plate.filter(ImageFilter.GaussianBlur(0.4))
base = Image.alpha_composite(base, plate)

d = ImageDraw.Draw(base)

# Shield silhouette.
shield = [(512, 220), (744, 304), (730, 560), (676, 704), (512, 814), (348, 704), (294, 560), (280, 304)]
shadow = Image.new('RGBA', (W,H), (0,0,0,0))
sd = ImageDraw.Draw(shadow)
sd.polygon([(x+10,y+18) for x,y in shield], fill=(0,0,0,105))
shadow = shadow.filter(ImageFilter.GaussianBlur(28))
base = Image.alpha_composite(base, shadow)
d = ImageDraw.Draw(base)
d.polygon(shield, fill=(17, 27, 66, 235), outline=(172, 211, 255, 245))
d.line(shield + [shield[0]], fill=(205, 229, 255, 230), width=12, joint='curve')

# Inner electric rim.
inner = [(512, 254), (708, 326), (696, 548), (650, 674), (512, 768), (374, 674), (328, 548), (316, 326)]
d.line(inner + [inner[0]], fill=(88, 129, 255, 145), width=5, joint='curve')

# NS monogram.
font = None
for candidate in [
    '/System/Library/Fonts/SFNSRounded.ttf',
    '/System/Library/Fonts/SFNS.ttf',
    '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
]:
    try:
        font = ImageFont.truetype(candidate, 236)
        break
    except Exception:
        pass
if font is None:
    font = ImageFont.load_default()

text = 'NS'
bbox = d.textbbox((0,0), text, font=font, stroke_width=0)
tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
tx = 512 - tw/2
ty = 480 - th/2
# text glow
text_layer = Image.new('RGBA',(W,H),(0,0,0,0))
td = ImageDraw.Draw(text_layer)
td.text((tx,ty), text, font=font, fill=(112,178,255,210))
text_layer = text_layer.filter(ImageFilter.GaussianBlur(25))
base = Image.alpha_composite(base,text_layer)
d = ImageDraw.Draw(base)
d.text((tx,ty), text, font=font, fill=(245,250,255,255))

# Admin approval badge/check.
badge_center=(680,690)
d.ellipse((612,622,748,758), fill=(19, 214, 148, 255), outline=(218,255,244,255), width=8)
d.line([(644,690),(674,720),(721,663)], fill=(255,255,255,255), width=18, joint='curve')

# Small keyhole dot + stem for licensing cue.
d.ellipse((490,650,534,694), fill=(175,214,255,220))
d.rounded_rectangle((504,685,520,728), radius=8, fill=(175,214,255,220))

master = base.convert('RGB')
master.save(OUT / 'AppIcon-1024.png', quality=100)

slots = [
    ('iphone','20x20','2x',40), ('iphone','20x20','3x',60),
    ('iphone','29x29','2x',58), ('iphone','29x29','3x',87),
    ('iphone','40x40','2x',80), ('iphone','40x40','3x',120),
    ('iphone','60x60','2x',120), ('iphone','60x60','3x',180),
    ('ipad','20x20','1x',20), ('ipad','20x20','2x',40),
    ('ipad','29x29','1x',29), ('ipad','29x29','2x',58),
    ('ipad','40x40','1x',40), ('ipad','40x40','2x',80),
    ('ipad','76x76','1x',76), ('ipad','76x76','2x',152),
    ('ipad','83.5x83.5','2x',167),
    ('ios-marketing','1024x1024','1x',1024),
]

images=[]
written={1024: OUT/'AppIcon-1024.png'}
for idiom,size,scale,px in slots:
    name=f'AppIcon-{px}.png'
    if px not in written:
        resized=master.resize((px,px), Image.Resampling.LANCZOS)
        resized.save(OUT/name, quality=100)
        written[px]=OUT/name
    images.append({'idiom':idiom,'size':size,'scale':scale,'filename':name})

(OUT/'Contents.json').write_text(json.dumps({'images':images,'info':{'author':'xcode','version':1}}, indent=2)+'\n')
assets_root=OUT.parent
(assets_root/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}, indent=2)+'\n')

# Legacy files for TrollStore/SpringBoard compatibility.
master.resize((120,120), Image.Resampling.LANCZOS).save(RES/'AppIcon60x60@2x.png', quality=100)
master.resize((180,180), Image.Resampling.LANCZOS).save(RES/'AppIcon60x60@3x.png', quality=100)

print('Generated NS Admin icon assets')
