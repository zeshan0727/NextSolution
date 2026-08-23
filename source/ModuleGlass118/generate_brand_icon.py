#!/usr/bin/env python3
"""Generate the Module Glass icon for the Next Jailbreak visual system."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


SIZE = 1024
GREEN = (108, 245, 140, 255)
CYAN = (76, 213, 255, 255)


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def add_glow(canvas: Image.Image, box: tuple[int, int, int, int], color: tuple[int, int, int, int], blur: int) -> None:
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(box, fill=color)
    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))


def glass_tile(canvas: Image.Image, box: tuple[int, int, int, int], radius: int) -> None:
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    shifted = (box[0], box[1] + 18, box[2], box[3] + 18)
    draw.rounded_rectangle(shifted, radius=radius, fill=(0, 0, 0, 145))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(32)))

    tile = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(tile)
    draw.rounded_rectangle(box, radius=radius, fill=(255, 255, 255, 25), outline=(255, 255, 255, 74), width=3)
    draw.rounded_rectangle(
        (box[0] + 5, box[1] + 5, box[2] - 5, box[1] + max(28, (box[3] - box[1]) // 3)),
        radius=max(12, radius - 8),
        fill=(255, 255, 255, 11),
    )
    canvas.alpha_composite(tile)


def draw_icon() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (5, 8, 12, 255))
    pixels = image.load()
    for y in range(SIZE):
        t = y / (SIZE - 1)
        for x in range(SIZE):
            u = x / (SIZE - 1)
            pixels[x, y] = (
                int(5 + 8 * u + 2 * t),
                int(9 + 12 * (1 - t) + 4 * u),
                int(14 + 24 * u + 12 * t),
                255,
            )

    add_glow(image, (-180, -160, 510, 530), (65, 255, 121, 135), 150)
    add_glow(image, (570, 560, 1210, 1200), (90, 76, 255, 115), 175)
    add_glow(image, (610, -150, 1170, 430), (55, 198, 255, 70), 155)

    glass_tile(image, (112, 128, 584, 600), 112)
    glass_tile(image, (628, 128, 850, 600), 92)
    glass_tile(image, (112, 648, 420, 846), 76)
    glass_tile(image, (466, 648, 850, 846), 76)

    glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    n_points = [(225, 470), (225, 260), (472, 470), (472, 260)]
    glow_draw.line(n_points, fill=(108, 245, 140, 190), width=58, joint="curve")
    image.alpha_composite(glow.filter(ImageFilter.GaussianBlur(28)))

    marks = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(marks)
    draw.line(n_points, fill=GREEN, width=42, joint="curve")
    for point in n_points:
        draw.ellipse((point[0] - 21, point[1] - 21, point[0] + 21, point[1] + 21), fill=GREEN)

    # A compact glass slider with a luminous thumb.
    draw.rounded_rectangle((715, 210, 763, 513), radius=24, fill=(255, 255, 255, 38))
    draw.rounded_rectangle((715, 366, 763, 513), radius=24, fill=(76, 213, 255, 205))
    draw.ellipse((681, 376, 797, 492), fill=(245, 253, 255, 248), outline=(76, 213, 255, 210), width=8)

    # Small Control Center symbols built from clean geometric marks.
    draw.ellipse((190, 699, 268, 777), fill=(108, 245, 140, 228))
    draw.ellipse((284, 699, 362, 777), fill=(76, 213, 255, 220))
    draw.rounded_rectangle((552, 700, 628, 776), radius=25, fill=(255, 255, 255, 220))
    draw.rounded_rectangle((678, 700, 754, 776), radius=25, fill=(142, 116, 255, 225))
    image.alpha_composite(marks)

    # Fine luminous border for the premium product finish.
    border = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle(
        (17, 17, SIZE - 18, SIZE - 18), radius=224, outline=(126, 255, 158, 88), width=4
    )
    image.alpha_composite(border)

    image.putalpha(rounded_mask(SIZE, 230))
    return image


def main() -> None:
    project = Path(__file__).resolve().parent
    repo = project.parents[1]
    icon = draw_icon()
    full = icon.resize((512, 512), Image.Resampling.LANCZOS)
    small = icon.resize((29, 29), Image.Resampling.LANCZOS)

    repo_icon = repo / "icons/nextaura/cc-module-backgrounds.png"
    prefs_icon = project / "layout/Library/PreferenceBundles/ModuleGlassPrefs.bundle/NextAura-cc-module-backgrounds.png"
    repo_icon.parent.mkdir(parents=True, exist_ok=True)
    full.save(repo_icon, optimize=True)
    small.save(prefs_icon, optimize=True)
    print(f"Generated {repo_icon} and {prefs_icon}")


if __name__ == "__main__":
    main()
