#!/usr/bin/env python3
"""Generate the Next Signer AppIcon asset catalog with no third-party dependencies."""

from __future__ import annotations

import json
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent / "NextSigner" / "Assets.xcassets" / "AppIcon.appiconset"


def clamp(value: float) -> int:
    return max(0, min(255, int(round(value))))


def inside_polygon(x: float, y: float, points: list[tuple[float, float]]) -> bool:
    inside = False
    j = len(points) - 1
    for i, (xi, yi) in enumerate(points):
        xj, yj = points[j]
        if (yi > y) != (yj > y):
            denom = (yj - yi) or 1e-9
            cross = (xj - xi) * (y - yi) / denom + xi
            if x < cross:
                inside = not inside
        j = i
    return inside


def background(x: float, y: float) -> tuple[int, int, int]:
    # Deep blue -> indigo -> magenta with two restrained radial glows.
    t = max(0.0, min(1.0, (x * 0.58 + y * 0.82)))
    r = 13 + 45 * t
    g = 72 + 34 * (1.0 - t)
    b = 176 + 70 * (1.0 - abs(t - 0.42))

    glow1 = max(0.0, 1.0 - math.hypot(x - 0.18, y - 0.12) / 0.72)
    glow2 = max(0.0, 1.0 - math.hypot(x - 0.88, y - 0.86) / 0.62)
    r += 8 * glow1 + 48 * glow2
    g += 68 * glow1 + 8 * glow2
    b += 42 * glow1 + 24 * glow2

    vignette = min(1.0, math.hypot(x - 0.5, y - 0.5) / 0.72)
    r *= 1.0 - 0.28 * vignette
    g *= 1.0 - 0.22 * vignette
    b *= 1.0 - 0.12 * vignette
    return clamp(r), clamp(g), clamp(b)


def render(size: int) -> bytes:
    # A sharp signature-like N plus a pen-nib accent. Coordinates are normalized.
    n_left = [(0.19, 0.72), (0.31, 0.72), (0.46, 0.31), (0.38, 0.22)]
    n_diag = [(0.34, 0.29), (0.45, 0.25), (0.65, 0.63), (0.55, 0.72)]
    n_right = [(0.54, 0.70), (0.66, 0.70), (0.78, 0.31), (0.70, 0.25)]
    nib = [(0.67, 0.25), (0.83, 0.13), (0.88, 0.19), (0.76, 0.36)]
    nib_cut = (0.787, 0.235, 0.035)

    rows = []
    for py in range(size):
        row = bytearray()
        for px in range(size):
            # Four-sample antialiasing for the white mark.
            coverage = 0
            cut_coverage = 0
            for ox, oy in ((0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)):
                x = (px + ox) / size
                y = (py + oy) / size
                if any(inside_polygon(x, y, p) for p in (n_left, n_diag, n_right, nib)):
                    coverage += 1
                cx, cy, radius = nib_cut
                if (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2:
                    cut_coverage += 1

            br, bg, bb = background((px + 0.5) / size, (py + 0.5) / size)
            alpha = coverage / 4.0
            # The nib hole cuts the white mark back to the background.
            alpha *= 1.0 - (cut_coverage / 4.0)
            wr, wg, wb = 247, 250, 255
            r = clamp(br * (1.0 - alpha) + wr * alpha)
            g = clamp(bg * (1.0 - alpha) + wg * alpha)
            b = clamp(bb * (1.0 - alpha) + wb * alpha)
            row.extend((r, g, b))
        rows.append(bytes(row))

    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    slots = [
        ("iphone", "20x20", "2x", 40, "icon-20@2x.png"),
        ("iphone", "20x20", "3x", 60, "icon-20@3x.png"),
        ("iphone", "29x29", "2x", 58, "icon-29@2x.png"),
        ("iphone", "29x29", "3x", 87, "icon-29@3x.png"),
        ("iphone", "40x40", "2x", 80, "icon-40@2x.png"),
        ("iphone", "40x40", "3x", 120, "icon-40@3x.png"),
        ("iphone", "60x60", "2x", 120, "icon-60@2x.png"),
        ("iphone", "60x60", "3x", 180, "icon-60@3x.png"),
        ("ios-marketing", "1024x1024", "1x", 1024, "icon-1024.png"),
    ]

    images = []
    cache: dict[int, bytes] = {}
    for idiom, point_size, scale, pixels, filename in slots:
        if pixels not in cache:
            cache[pixels] = render(pixels)
        (ROOT / filename).write_bytes(cache[pixels])
        images.append({"idiom": idiom, "size": point_size, "scale": scale, "filename": filename})

    contents = {
        "images": images,
        "info": {"author": "xcode", "version": 1},
    }
    (ROOT / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print(f"Generated Next Signer AppIcon assets in {ROOT}")


if __name__ == "__main__":
    main()
