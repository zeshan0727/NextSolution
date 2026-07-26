from PIL import Image, ImageDraw

size = 1024
image = Image.new('RGB', (size, size), '#111827')
draw = ImageDraw.Draw(image)
for inset in range(0, 220):
    shade = int(25 + inset * 0.35)
    draw.rounded_rectangle((inset, inset, size-inset, size-inset), radius=220-inset//2, outline=(30, 120+shade//4, 255), width=3)
# shield
draw.rounded_rectangle((250, 220, 774, 804), radius=150, fill='#2563EB')
draw.ellipse((410, 350, 614, 554), fill='white')
draw.rounded_rectangle((470, 500, 554, 680), radius=40, fill='white')
# small key accents
draw.ellipse((170, 760, 270, 860), outline='#60A5FA', width=26)
draw.line((255, 810, 380, 810), fill='#60A5FA', width=26)
draw.line((330, 810, 330, 870), fill='#60A5FA', width=26)
image.save('NextPassword/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png')
