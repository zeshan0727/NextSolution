#!/usr/bin/env python3
"""Generate the Next Jailbreak repository icon in standard Sileo sizes."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


SIZE = 1024
GREEN = (108, 245, 140, 255)


def mask() -> Image.Image:
    result = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(result).rounded_rectangle((0, 0, SIZE - 1, SIZE - 1), radius=230, fill=255)
    return result


def build() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (4, 7, 6, 255))
    px = image.load()
    for y in range(SIZE):
        v = y / (SIZE - 1)
        for x in range(SIZE):
            u = x / (SIZE - 1)
            px[x, y] = (
                int(4 + 5 * u),
                int(8 + 15 * (1 - v) + 4 * u),
                int(8 + 20 * u + 9 * v),
                255,
            )

    ambient = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(ambient)
    draw.ellipse((-220, -190, 600, 630), fill=(66, 255, 119, 145))
    draw.ellipse((590, 550, 1240, 1210), fill=(80, 72, 255, 105))
    image.alpha_composite(ambient.filter(ImageFilter.GaussianBlur(180)))

    glass = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glass)
    draw.rounded_rectangle((135, 135, 889, 889), radius=190, fill=(255, 255, 255, 19), outline=(139, 255, 166, 76), width=4)
    draw.rounded_rectangle((155, 155, 869, 430), radius=168, fill=(255, 255, 255, 10))
    image.alpha_composite(glass)

    # A broken halo gives the jailbreak mark movement without using a literal lock.
    halo = Image.new("RGBA", image.size, (0, 0, 0, 0))
    halo_draw = ImageDraw.Draw(halo)
    halo_draw.arc((205, 205, 819, 819), start=205, end=495, fill=(108, 245, 140, 180), width=22)
    image.alpha_composite(halo.filter(ImageFilter.GaussianBlur(22)))
    image.alpha_composite(halo)

    monogram_glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(monogram_glow)
    n = [(292, 681), (292, 350), (515, 681), (515, 350)]
    j = [(705, 350), (705, 615), (660, 684), (570, 684)]
    draw.line(n, fill=(108, 245, 140, 210), width=65, joint="curve")
    draw.line(j, fill=(246, 250, 248, 200), width=65, joint="curve")
    image.alpha_composite(monogram_glow.filter(ImageFilter.GaussianBlur(34)))

    marks = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(marks)
    draw.line(n, fill=GREEN, width=45, joint="curve")
    draw.line(j, fill=(245, 249, 247, 255), width=45, joint="curve")
    for point in (n[0], n[1], n[2], n[3], j[0], j[-1]):
        color = GREEN if point in n else (245, 249, 247, 255)
        draw.ellipse((point[0] - 22, point[1] - 22, point[0] + 22, point[1] + 22), fill=color)
    image.alpha_composite(marks)

    border = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle((17, 17, 1006, 1006), radius=224, outline=(122, 255, 153, 96), width=4)
    image.alpha_composite(border)
    image.putalpha(mask())
    return image


def main() -> None:
    repo = Path(__file__).resolve().parents[1]
    icon = build()
    icon.resize((512, 512), Image.Resampling.LANCZOS).save(repo / "RepoIcon.png", optimize=True)
    icon.convert("RGB").resize((64, 64), Image.Resampling.LANCZOS).save(repo / "CydiaIcon.png", optimize=True)
    print("Generated Next Jailbreak RepoIcon.png and CydiaIcon.png")


if __name__ == "__main__":
    main()
