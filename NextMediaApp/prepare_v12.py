from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path("projects/NextMedia")


def fix_swift_error_bridge() -> None:
    path = ROOT / "NextMedia/Services/ConversionManager.swift"
    source = path.read_text()
    old = """                var encoderError: NSError?\n                let succeeded = MP3Encoder.encodeSource(m4aURL, destination: mp3URL, bitrate: 192, error: &encoderError)\n                try? FileManager.default.removeItem(at: m4aURL)\n                DispatchQueue.main.async {\n                    if succeeded {\n                        self.addCompletedFile(mp3URL, title: \"\\(item.title) – MP3\", jobID: job.id)\n                    } else {\n                        self.fail(jobID: job.id, message: encoderError?.localizedDescription ?? \"MP3 encoding failed.\")\n                    }\n                }\n"""
    new = """                do {\n                    try MP3Encoder.encodeSource(m4aURL, destination: mp3URL, bitrate: 192)\n                    try? FileManager.default.removeItem(at: m4aURL)\n                    DispatchQueue.main.async {\n                        self.addCompletedFile(mp3URL, title: \"\\(item.title) – MP3\", jobID: job.id)\n                    }\n                } catch {\n                    try? FileManager.default.removeItem(at: m4aURL)\n                    DispatchQueue.main.async {\n                        self.fail(jobID: job.id, message: error.localizedDescription)\n                    }\n                }\n"""
    if old not in source:
        raise RuntimeError("Expected MP3 encoder call block was not found")
    path.write_text(source.replace(old, new))


def icon_master(dark: bool) -> Image.Image:
    size = 1024
    image = Image.new("RGB", (size, size), (7, 10, 22) if dark else (247, 249, 255))
    draw = ImageDraw.Draw(image)

    if dark:
        for y in range(size):
            t = y / (size - 1)
            draw.line((0, y, size, y), fill=(int(8 + 15 * t), int(12 + 18 * t), int(30 + 45 * t)))
        card, ink, accent = (30, 37, 66), (242, 246, 255), (83, 161, 255)
    else:
        for y in range(size):
            t = y / (size - 1)
            draw.line((0, y, size, y), fill=(int(252 - 18 * t), int(253 - 19 * t), 255))
        card, ink, accent = (255, 255, 255), (18, 26, 48), (35, 112, 246)

    draw.rounded_rectangle((128, 128, 896, 896), radius=190, fill=card)
    draw.rounded_rectangle((385, 285, 470, 665), radius=42, fill=accent)
    draw.rounded_rectangle((445, 275, 695, 355), radius=38, fill=accent)
    draw.ellipse((275, 585, 475, 785), fill=accent)
    draw.ellipse((535, 525, 735, 725), fill=accent)
    draw.polygon([(520, 405), (520, 565), (650, 485)], fill=ink)
    return image


def generate_icons() -> None:
    assets = ROOT / "NextMedia/Resources/Assets.xcassets"
    light_dir = assets / "AppIcon.appiconset"
    dark_dir = assets / "AppIconDark.appiconset"
    dark_dir.mkdir(parents=True, exist_ok=True)

    contents = json.loads((light_dir / "Contents.json").read_text())
    (dark_dir / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    light, dark = icon_master(False), icon_master(True)

    for entry in contents["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        points = float(entry["size"].split("x")[0])
        scale = float(entry["scale"].replace("x", ""))
        pixels = int(round(points * scale))
        light.resize((pixels, pixels), Image.Resampling.LANCZOS).save(light_dir / filename, format="PNG")
        dark.resize((pixels, pixels), Image.Resampling.LANCZOS).save(dark_dir / filename, format="PNG")


if __name__ == "__main__":
    fix_swift_error_bridge()
    generate_icons()
