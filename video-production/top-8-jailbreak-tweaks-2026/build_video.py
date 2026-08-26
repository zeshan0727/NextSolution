#!/usr/bin/env python3
"""Build the first Next Jailbreak YouTube package from original source material."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps
except ImportError as exc:  # pragma: no cover - dependency is installed in CI
    raise SystemExit("Pillow is required: python3 -m pip install Pillow") from exc


WIDTH = 1920
HEIGHT = 1080
THUMB_WIDTH = 1280
THUMB_HEIGHT = 720
SHORT_WIDTH = 1080
SHORT_HEIGHT = 1920
SPEECH_ENDPOINT = "https://api.openai.com/v1/audio/speech"
MODEL = "gpt-4o-mini-tts"
VOICE = "cedar"
REGULAR_FONT = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
BOLD_FONT = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")


@dataclass(frozen=True)
class SceneTiming:
    index: int
    title: str
    start: float
    duration: float


def run(command: list[str], *, capture: bool = False) -> str:
    result = subprocess.run(
        command,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )
    return result.stdout.strip() if capture else ""


def font(size: int, *, bold: bool = False) -> ImageFont.FreeTypeFont:
    path = BOLD_FONT if bold else REGULAR_FONT
    if not path.exists():
        raise RuntimeError(f"required font is unavailable: {path}")
    return ImageFont.truetype(str(path), size)


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    if not re.fullmatch(r"[0-9a-fA-F]{6}", value):
        raise ValueError(f"invalid colour: {value}")
    return tuple(int(value[index : index + 2], 16) for index in (0, 2, 4))


def mix(left: tuple[int, int, int], right: tuple[int, int, int], amount: float) -> tuple[int, int, int]:
    return tuple(round(a + (b - a) * amount) for a, b in zip(left, right))


def gradient(size: tuple[int, int], accent: str) -> Image.Image:
    width, height = size
    top = (244, 247, 255)
    bottom = mix((232, 238, 250), hex_rgb(accent), 0.12)
    image = Image.new("RGB", size)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        amount = y / max(1, height - 1)
        draw.line((0, y, width, y), fill=mix(top, bottom, amount))
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    colour = (*hex_rgb(accent), 52)
    glow_draw.ellipse((width * 0.58, -height * 0.3, width * 1.15, height * 0.65), fill=colour)
    glow_draw.ellipse((-width * 0.2, height * 0.65, width * 0.42, height * 1.3), fill=(*hex_rgb(accent), 24))
    glow = glow.filter(ImageFilter.GaussianBlur(max(24, width // 28)))
    image = Image.alpha_composite(image.convert("RGBA"), glow)
    return image


def rounded_panel(image: Image.Image, box: tuple[int, int, int, int], radius: int, fill: tuple[int, ...], *, shadow: bool = True) -> None:
    if shadow:
        layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        x1, y1, x2, y2 = box
        ld.rounded_rectangle((x1 + 12, y1 + 18, x2 + 12, y2 + 18), radius=radius, fill=(25, 35, 70, 32))
        layer = layer.filter(ImageFilter.GaussianBlur(20))
        image.alpha_composite(layer)
    ImageDraw.Draw(image).rounded_rectangle(box, radius=radius, fill=fill)


def fit_lines(draw: ImageDraw.ImageDraw, text: str, face: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if current and draw.textlength(candidate, font=face) > max_width:
            lines.append(current)
            current = word
        else:
            current = candidate
    if current:
        lines.append(current)
    return lines


def draw_multiline(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    text: str,
    face: ImageFont.FreeTypeFont,
    fill: tuple[int, ...],
    max_width: int,
    spacing: int,
) -> int:
    x, y = xy
    lines = fit_lines(draw, text, face, max_width)
    line_height = face.size + spacing
    for line in lines:
        draw.text((x, y), line, font=face, fill=fill)
        y += line_height
    return y


def draw_brand(image: Image.Image, logo_path: Path, *, small: bool = False) -> None:
    draw = ImageDraw.Draw(image)
    size = 62 if small else 74
    x, y = (58, 48) if small else (84, 70)
    if logo_path.exists():
        logo = Image.open(logo_path).convert("RGBA")
        logo.thumbnail((size, size), Image.Resampling.LANCZOS)
        image.alpha_composite(logo, (x, y))
    else:
        draw.rounded_rectangle((x, y, x + size, y + size), radius=size // 4, fill=(91, 92, 226, 255))
        draw.text((x + size * 0.27, y + size * 0.08), "N", font=font(round(size * 0.62), bold=True), fill="white")
    wordmark_size = 34 if small else 40
    next_face = font(wordmark_size, bold=True)
    solution_face = font(wordmark_size)
    next_x = x + size + 20
    next_width = math.ceil(draw.textlength("Next", font=next_face))
    word_gap = max(10, round(wordmark_size * 0.27))
    solution_x = next_x + next_width + word_gap
    if solution_x - (next_x + next_width) < 10:
        raise RuntimeError("Next Jailbreak wordmark spacing is below the safe minimum")
    draw.text((next_x, y + 5), "Next", font=next_face, fill=(22, 29, 52, 255))
    draw.text((solution_x, y + 5), "Solution", font=solution_face, fill=(48, 60, 91, 255))


def draw_phone(image: Image.Image, accent: str, scene_index: int, *, thumb: bool = False) -> None:
    draw = ImageDraw.Draw(image)
    scale = 0.73 if thumb else 1.0
    left = 925 if thumb else 1390
    top = 88 if thumb else 165
    width = round(280 * scale) if thumb else 365
    height = round(600 * scale) if thumb else 755
    radius = round(55 * scale) if thumb else 72
    rounded_panel(image, (left, top, left + width, top + height), radius, (18, 24, 43, 255), shadow=True)
    inset = round(13 * scale) if thumb else 16
    rounded_panel(
        image,
        (left + inset, top + inset, left + width - inset, top + height - inset),
        radius - 10,
        (246, 248, 255, 255),
        shadow=False,
    )
    notch_w = round(92 * scale) if thumb else 122
    notch_h = round(24 * scale) if thumb else 32
    draw.rounded_rectangle(
        (left + (width - notch_w) // 2, top + inset + 8, left + (width + notch_w) // 2, top + inset + 8 + notch_h),
        radius=notch_h // 2,
        fill=(18, 24, 43, 255),
    )
    icon_size = round(43 * scale) if thumb else 58
    gap_x = round(16 * scale) if thumb else 22
    gap_y = round(20 * scale) if thumb else 28
    grid_left = left + inset + round(25 * scale)
    grid_top = top + inset + round(70 * scale)
    palette = [accent, "#20a4a0", "#f08c3b", "#e0568a", "#6d5dfc", "#2578f5"]
    for row in range(5):
        for col in range(4):
            x = grid_left + col * (icon_size + gap_x)
            y = grid_top + row * (icon_size + gap_y)
            colour = hex_rgb(palette[(row * 4 + col + scene_index) % len(palette)])
            draw.rounded_rectangle((x, y, x + icon_size, y + icon_size), radius=max(9, icon_size // 4), fill=(*colour, 238))
            if (row + col + scene_index) % 3 == 0:
                draw.ellipse((x + icon_size * 0.34, y + icon_size * 0.34, x + icon_size * 0.66, y + icon_size * 0.66), fill=(255, 255, 255, 215))
    dock_h = round(88 * scale) if thumb else 116
    dock_y = top + height - inset - dock_h - round(18 * scale)
    draw.rounded_rectangle((left + inset + 16, dock_y, left + width - inset - 16, dock_y + dock_h), radius=dock_h // 3, fill=(217, 224, 242, 220))
    dock_icon = round(37 * scale) if thumb else 48
    dock_gap = round(7 * scale) if thumb else 9
    dock_total = dock_icon * 5 + dock_gap * 4
    dock_x = left + (width - dock_total) // 2
    for index in range(5):
        colour = hex_rgb(palette[(index + 2) % len(palette)])
        draw.rounded_rectangle((dock_x, dock_y + (dock_h - dock_icon) // 2, dock_x + dock_icon, dock_y + (dock_h + dock_icon) // 2), radius=max(8, dock_icon // 4), fill=(*colour, 255))
        dock_x += dock_icon + dock_gap


def load_visual_asset(assets_root: Path, relative_path: str) -> Image.Image:
    root = assets_root.resolve()
    candidate = (assets_root / relative_path).resolve()
    if root != candidate and root not in candidate.parents:
        raise ValueError(f"visual asset escapes the production directory: {relative_path}")
    if not candidate.is_file():
        raise FileNotFoundError(f"visual asset is unavailable: {relative_path}")
    return Image.open(candidate).convert("RGBA")


def draw_media_tile(
    image: Image.Image,
    source: Image.Image,
    box: tuple[int, int, int, int],
    *,
    radius: int,
) -> None:
    x1, y1, x2, y2 = box
    width = max(1, x2 - x1)
    height = max(1, y2 - y1)
    tile = Image.new("RGBA", (width, height), (13, 19, 34, 255))
    blurred = ImageOps.fit(source, (width, height), method=Image.Resampling.LANCZOS)
    blurred = blurred.filter(ImageFilter.GaussianBlur(max(12, min(width, height) // 22)))
    darkener = Image.new("RGBA", (width, height), (10, 15, 29, 150))
    tile = Image.alpha_composite(blurred, darkener)
    contained = ImageOps.contain(
        source,
        (max(1, width - 12), max(1, height - 12)),
        method=Image.Resampling.LANCZOS,
    )
    paste_x = (width - contained.width) // 2
    paste_y = (height - contained.height) // 2
    tile.alpha_composite(contained, (paste_x, paste_y))
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), radius=radius, fill=255)
    rounded = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    rounded.paste(tile, (0, 0), mask)
    image.alpha_composite(rounded, (x1, y1))
    ImageDraw.Draw(image).rounded_rectangle(box, radius=radius, outline=(255, 255, 255, 72), width=2)


def draw_media_gallery(
    image: Image.Image,
    visual: dict[str, Any],
    assets_root: Path,
    box: tuple[int, int, int, int],
    accent: str,
    *,
    show_credit: bool = True,
    show_header: bool = True,
) -> None:
    paths = [str(item) for item in visual.get("assets", [])]
    if not paths:
        raise ValueError("every scene must provide at least one authentic visual asset")
    if len(paths) > 4:
        raise ValueError("a media gallery supports at most four assets")
    sources = [load_visual_asset(assets_root, item) for item in paths]
    x1, y1, x2, y2 = box
    draw = ImageDraw.Draw(image)
    rounded_panel(image, box, 34, (12, 18, 33, 246), shadow=True)
    margin = 18
    header_height = 44 if show_header else 0
    credit_height = 48 if show_credit else 0
    if show_header:
        badge = "REAL TWEAK VISUAL"
        badge_face = font(16, bold=True)
        badge_width = math.ceil(draw.textlength(badge, font=badge_face)) + 38
        draw.rounded_rectangle(
            (x1 + margin, y1 + 12, x1 + margin + badge_width, y1 + 43),
            radius=15,
            fill=(*hex_rgb(accent), 235),
        )
        draw.text((x1 + margin + 19, y1 + 18), badge, font=badge_face, fill=(255, 255, 255, 255))
    content_top = y1 + margin + header_height
    content_bottom = y2 - margin - credit_height
    content_left = x1 + margin
    content_right = x2 - margin
    gap = 14
    boxes: list[tuple[int, int, int, int]] = []
    if len(sources) == 1:
        boxes = [(content_left, content_top, content_right, content_bottom)]
    elif len(sources) == 2:
        column_width = (content_right - content_left - gap) // 2
        boxes = [
            (content_left, content_top, content_left + column_width, content_bottom),
            (content_left + column_width + gap, content_top, content_right, content_bottom),
        ]
    else:
        column_width = (content_right - content_left - gap) // 2
        row_height = (content_bottom - content_top - gap) // 2
        grid = [
            (content_left, content_top, content_left + column_width, content_top + row_height),
            (content_left + column_width + gap, content_top, content_right, content_top + row_height),
            (content_left, content_top + row_height + gap, content_left + column_width, content_bottom),
            (content_left + column_width + gap, content_top + row_height + gap, content_right, content_bottom),
        ]
        boxes = grid[: len(sources)]
    for source, tile_box in zip(sources, boxes):
        draw_media_tile(image, source, tile_box, radius=18)
    if show_credit:
        credit = str(visual.get("credit", "Source screenshots credited in description"))
        dot_x = x1 + margin + 3
        credit_y = y2 - margin - 28
        credit_size = 17
        credit_face = font(credit_size, bold=True)
        max_credit_width = x2 - margin - (dot_x + 23)
        while draw.textlength(credit, font=credit_face) > max_credit_width and credit_size > 13:
            credit_size -= 1
            credit_face = font(credit_size, bold=True)
        draw.ellipse((dot_x, credit_y + 4, dot_x + 12, credit_y + 16), fill=(*hex_rgb(accent), 255))
        draw.text((dot_x + 23, credit_y), credit, font=credit_face, fill=(223, 229, 244, 255))


def render_slide(
    scene: dict[str, Any],
    index: int,
    count: int,
    logo_path: Path,
    assets_root: Path,
    target: Path,
) -> None:
    image = gradient((WIDTH, HEIGHT), str(scene["accent"]))
    draw = ImageDraw.Draw(image)
    draw_brand(image, logo_path)
    accent = (*hex_rgb(str(scene["accent"])), 255)
    draw.rounded_rectangle((86, 190, 570, 247), radius=28, fill=accent)
    draw.text((112, 202), str(scene["kicker"]), font=font(25, bold=True), fill=(255, 255, 255, 255))
    title_y = draw_multiline(draw, (86, 294), str(scene["title"]), font(78, bold=True), (20, 28, 53, 255), 1130, 10)
    subtitle_y = draw_multiline(draw, (88, title_y + 28), str(scene["subtitle"]), font(38), (73, 84, 113, 255), 1050, 9)
    fact_y = max(subtitle_y + 42, 565)
    for fact in scene["facts"]:
        draw.rounded_rectangle((86, fact_y, 1190, fact_y + 72), radius=24, fill=(255, 255, 255, 205), outline=(208, 216, 235, 255), width=2)
        draw.ellipse((112, fact_y + 24, 136, fact_y + 48), fill=accent)
        draw.text((158, fact_y + 16), str(fact), font=font(30, bold=True), fill=(42, 51, 78, 255))
        fact_y += 91
    draw_media_gallery(
        image,
        dict(scene["visual"]),
        assets_root,
        (1288, 166, 1848, 948),
        str(scene["accent"]),
    )
    draw.text((86, 1012), "nextjailbreak.com", font=font(24, bold=True), fill=(87, 98, 127, 255))
    progress_left, progress_right = 530, 1240
    draw.rounded_rectangle((progress_left, 1022, progress_right, 1030), radius=4, fill=(204, 211, 230, 255))
    progress = progress_left + round((progress_right - progress_left) * ((index + 1) / count))
    draw.rounded_rectangle((progress_left, 1022, progress, 1030), radius=4, fill=accent)
    draw.text((1280, 1009), f"{index + 1:02d} / {count:02d}", font=font(24, bold=True), fill=(87, 98, 127, 255))
    target.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(target, quality=95)


def render_thumbnail(content: dict[str, Any], logo_path: Path, assets_root: Path, target: Path) -> None:
    accent = "#5b5ce2"
    image = gradient((THUMB_WIDTH, THUMB_HEIGHT), accent)
    draw = ImageDraw.Draw(image)
    draw_brand(image, logo_path, small=True)
    badge = str(content["thumbnail_badge"])
    badge_face = font(25, bold=True)
    badge_width = math.ceil(draw.textlength(badge, font=badge_face)) + 56
    draw.rounded_rectangle((58, 150, 58 + badge_width, 204), radius=27, fill=(*hex_rgb(accent), 255))
    draw.text((86, 160), badge, font=badge_face, fill="white")
    lines = [str(line) for line in content["thumbnail_lines"]]
    y = 244
    for position, line in enumerate(lines):
        face = font(92 if position == 0 else 70, bold=True)
        colour = (*hex_rgb(accent), 255) if position == 0 else (20, 28, 53, 255)
        draw.text((58, y), line, font=face, fill=colour, stroke_width=1)
        y += 102 if position == 0 else 86
    draw.rounded_rectangle((59, 598, 803, 662), radius=25, fill=(255, 255, 255, 220), outline=(205, 213, 232, 255), width=2)
    draw.text((87, 612), str(content["thumbnail_footer"]), font=font(27, bold=True), fill=(58, 68, 96, 255))
    draw_media_gallery(
        image,
        dict(content["thumbnail_visual"]),
        assets_root,
        (855, 126, 1234, 676),
        accent,
        show_credit=False,
        show_header=False,
    )
    target.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(target, quality=96)


def render_short_slide(
    scene: dict[str, Any],
    short_index: int,
    short_count: int,
    logo_path: Path,
    assets_root: Path,
    target: Path,
) -> None:
    accent_value = str(scene["accent"])
    accent = (*hex_rgb(accent_value), 255)
    image = gradient((SHORT_WIDTH, SHORT_HEIGHT), accent_value)
    draw = ImageDraw.Draw(image)
    draw_brand(image, logo_path, small=True)
    counter = f"SHORT {short_index:02d} / {short_count:02d}"
    counter_face = font(21, bold=True)
    counter_width = math.ceil(draw.textlength(counter, font=counter_face)) + 38
    draw.rounded_rectangle(
        (SHORT_WIDTH - counter_width - 56, 54, SHORT_WIDTH - 56, 96),
        radius=21,
        fill=(255, 255, 255, 218),
        outline=(205, 213, 232, 255),
        width=2,
    )
    draw.text((SHORT_WIDTH - counter_width - 37, 64), counter, font=counter_face, fill=(57, 68, 98, 255))
    kicker = str(scene["kicker"])
    kicker_face = font(22, bold=True)
    kicker_width = min(940, math.ceil(draw.textlength(kicker, font=kicker_face)) + 52)
    draw.rounded_rectangle((60, 145, 60 + kicker_width, 197), radius=26, fill=accent)
    draw.text((86, 158), kicker, font=kicker_face, fill=(255, 255, 255, 255))
    title_y = draw_multiline(draw, (60, 229), str(scene["title"]), font(66, bold=True), (20, 28, 53, 255), 960, 7)
    draw_multiline(draw, (62, title_y + 10), str(scene["subtitle"]), font(32), (73, 84, 113, 255), 946, 6)
    draw_media_gallery(
        image,
        dict(scene["visual"]),
        assets_root,
        (60, 470, 1020, 1375),
        accent_value,
    )
    fact_y = 1402
    for fact in scene["facts"]:
        draw.rounded_rectangle(
            (60, fact_y, 1020, fact_y + 72),
            radius=24,
            fill=(255, 255, 255, 220),
            outline=(205, 213, 232, 255),
            width=2,
        )
        draw.ellipse((84, fact_y + 24, 108, fact_y + 48), fill=accent)
        draw.text((132, fact_y + 17), str(fact), font=font(25, bold=True), fill=(42, 51, 78, 255))
        fact_y += 86
    draw.rounded_rectangle((60, 1670, 1020, 1752), radius=28, fill=(18, 25, 45, 242))
    draw.text((96, 1694), "FULL TOP 8 GUIDE  •  nextjailbreak.com", font=font(25, bold=True), fill=(255, 255, 255, 255))
    target.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(target, quality=95)


def generate_speech(text: str, target: Path, *, api_key: str, voice: str) -> None:
    payload = json.dumps(
        {
            "model": MODEL,
            "voice": voice,
            "input": text,
            "instructions": "Speak as a clear, calm technology presenter in neutral international English. Use natural pacing, confident but not promotional. Pronounce iOS as eye-oh-ess and dot c c as separate letters.",
            "response_format": "aac",
            "speed": 0.98,
        }
    ).encode("utf-8")
    last_error = "unknown speech error"
    for attempt in range(3):
        request = Request(
            SPEECH_ENDPOINT,
            data=payload,
            method="POST",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
                "User-Agent": "NextSolutionVideoBuilder/1.0",
            },
        )
        try:
            with urlopen(request, timeout=120) as response:
                audio = response.read()
            if len(audio) < 2048:
                raise RuntimeError("speech response was unexpectedly small")
            target.write_bytes(audio)
            return
        except HTTPError as exc:
            detail = exc.read(1200).decode("utf-8", errors="replace")
            last_error = f"HTTP {exc.code}: {detail}"
            if exc.code not in {408, 409, 429, 500, 502, 503, 504}:
                break
        except (URLError, TimeoutError, RuntimeError) as exc:
            last_error = str(exc)
        if attempt < 2:
            time.sleep(2**attempt)
    raise RuntimeError(last_error)


def media_duration(path: Path) -> float:
    value = run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        capture=True,
    )
    return float(value)


def speech_duration_bounds(text: str) -> tuple[float, float]:
    """Return conservative duration limits for intelligible English narration."""
    words = len(re.findall(r"[A-Za-z0-9][A-Za-z0-9'-]*", text))
    if words < 1:
        raise ValueError("narration must contain at least one word")
    # Reject partial/truncated speech and accidental extreme pacing. The range
    # deliberately allows natural pauses and presenter-style emphasis.
    return words / 230 * 60, words / 85 * 60


def validated_speech(
    text: str,
    target: Path,
    *,
    api_key: str,
    voice: str,
    attempts: int = 3,
) -> float:
    minimum, maximum = speech_duration_bounds(text)
    observed = 0.0
    for attempt in range(attempts):
        generate_speech(text, target, api_key=api_key, voice=voice)
        observed = media_duration(target)
        if minimum <= observed <= maximum:
            return observed
        target.unlink(missing_ok=True)
        if attempt < attempts - 1:
            time.sleep(2**attempt)
    raise RuntimeError(
        "speech duration failed validation after regeneration: "
        f"observed={observed:.3f}s expected={minimum:.3f}-{maximum:.3f}s"
    )


def caption_chunks(text: str, max_chars: int = 52) -> list[str]:
    chunks: list[str] = []
    for sentence in re.split(r"(?<=[.!?])\s+", text.strip()):
        words = sentence.split()
        current = ""
        for word in words:
            candidate = f"{current} {word}".strip()
            if current and len(candidate) > max_chars:
                chunks.append(current)
                current = word
            else:
                current = candidate
        if current:
            chunks.append(current)
    return chunks


def srt_timestamp(seconds: float) -> str:
    milliseconds = max(0, round(seconds * 1000))
    hours, milliseconds = divmod(milliseconds, 3_600_000)
    minutes, milliseconds = divmod(milliseconds, 60_000)
    whole_seconds, milliseconds = divmod(milliseconds, 1000)
    return f"{hours:02d}:{minutes:02d}:{whole_seconds:02d},{milliseconds:03d}"


def write_subtitles(scenes: list[dict[str, Any]], timings: list[SceneTiming], target: Path) -> None:
    entries: list[str] = []
    sequence = 1
    for scene, timing in zip(scenes, timings):
        chunks = caption_chunks(str(scene["narration"]))
        weights = [max(8, len(chunk)) for chunk in chunks]
        usable = max(1.0, timing.duration - 0.15)
        cursor = timing.start
        total_weight = sum(weights)
        for chunk, weight in zip(chunks, weights):
            duration = usable * weight / total_weight
            end = min(timing.start + usable, cursor + duration)
            entries.append(f"{sequence}\n{srt_timestamp(cursor)} --> {srt_timestamp(end)}\n{chunk}\n")
            sequence += 1
            cursor = end
    target.write_text("\n".join(entries), encoding="utf-8")


def chapter_timestamp(seconds: float) -> str:
    total = max(0, math.floor(seconds))
    hours, remainder = divmod(total, 3600)
    minutes, secs = divmod(remainder, 60)
    return f"{hours}:{minutes:02d}:{secs:02d}" if hours else f"{minutes:02d}:{secs:02d}"


def visual_source_index(content: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(item["id"]): dict(item) for item in content["visual_sources"]}


def visual_source_lines(content: dict[str, Any]) -> list[str]:
    return [
        f"{item['tweak']} — {item['credit']}: {item['source_url']}"
        for item in content["visual_sources"]
    ]


def write_metadata(content: dict[str, Any], timings: list[SceneTiming], output: Path) -> None:
    chapter_lines = [f"{chapter_timestamp(item.start)} {item.title}" for item in timings]
    description = (
        str(content["description_intro"]).strip()
        + "\n\n"
        f"Read the full comparison: {content['article_url']}\n\n"
        "CHAPTERS\n"
        + "\n".join(chapter_lines)
        + "\n\n"
        + "FEATURE VISUAL SOURCES\n"
        + "\n".join(visual_source_lines(content))
        + "\n\n"
        + str(content["voice_disclosure"])
        + " Original research, script, editing and visual composition by Next Jailbreak. Feature screenshots are reproduced for editorial commentary and remain the property of their respective owners.\n\n"
        + str(content["hashtags"])
    )
    metadata = {
        "title": content["video_title"],
        "description": description,
        "tags": content["tags"],
        "category": "Science & Technology",
        "language": "English",
        "license": "Standard YouTube License",
        "made_for_kids": False,
        "article_url": content["article_url"],
        "voice_disclosure": content["voice_disclosure"],
        "visual_sources": content["visual_sources"],
    }
    (output / "youtube-metadata.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (output / "youtube-description.txt").write_text(description + "\n", encoding="utf-8")


def write_shorts_metadata(content: dict[str, Any], output: Path) -> list[dict[str, Any]]:
    source_by_id = visual_source_index(content)
    short_entries: list[dict[str, Any]] = []
    for short_index, scene in enumerate(content["scenes"][1:9], start=1):
        source_ids = [str(item) for item in scene["visual"].get("source_ids", [])]
        sources = [source_by_id[item] for item in source_ids]
        source_text = "\n".join(f"{item['tweak']}: {item['source_url']}" for item in sources)
        description = (
            f"Tweak {short_index} of 8: {scene['title']} — {scene['subtitle']}.\n\n"
            f"Watch the full comparison: {content['article_url']}\n"
            f"Feature source: {source_text}\n\n"
            "This is an editorial overview, not a hands-on compatibility test. Verify your exact iOS version, jailbreak, bootstrap, architecture, dependencies and current package details before installing.\n\n"
            f"{content['voice_disclosure']} Feature screenshots are credited to their source owners.\n\n"
            + str(content["short_hashtags"])
        )
        slug = str(scene["slug"])
        short_entries.append(
            {
                "index": short_index,
                "slug": slug,
                "title": scene["short_title"],
                "description": description,
                "tags": list(dict.fromkeys([*content["tags"], str(scene["title"]), "YouTube Shorts"])),
                "category": "Science & Technology",
                "language": "English",
                "made_for_kids": False,
                "video": f"shorts/{short_index:02d}-{slug}.mp4",
                "cover": f"shorts/covers/{short_index:02d}-{slug}.png",
                "visual_sources": sources,
                "voice_disclosure": content["voice_disclosure"],
            }
        )
    shorts_root = output / "shorts"
    shorts_root.mkdir(parents=True, exist_ok=True)
    (shorts_root / "youtube-shorts-metadata.json").write_text(
        json.dumps(short_entries, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return short_entries


def render_video(content: dict[str, Any], output: Path, *, api_key: str, voice: str) -> list[SceneTiming]:
    scenes = content["scenes"]
    scene_videos: list[Path] = []
    timings: list[SceneTiming] = []
    cursor = 0.0
    for index, scene in enumerate(scenes):
        audio = output / f"scene-{index + 1:02d}.aac"
        video = output / f"scene-{index + 1:02d}.mp4"
        slide = output / "slides" / f"scene-{index + 1:02d}.png"
        duration = validated_speech(
            str(scene["narration"]), audio, api_key=api_key, voice=voice
        )
        fade_out = max(0.0, duration - 0.3)
        zoom_direction = 0.00008 if index % 2 == 0 else 0.00006
        filter_graph = (
            "scale=2112:1188,"
            f"zoompan=z='min(zoom+{zoom_direction},1.045)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1920x1080:fps=30,"
            f"fade=t=in:st=0:d=0.25,fade=t=out:st={fade_out:.3f}:d=0.30,format=yuv420p"
        )
        run(
            [
                "ffmpeg",
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-loop",
                "1",
                "-framerate",
                "30",
                "-i",
                str(slide),
                "-i",
                str(audio),
                "-vf",
                filter_graph,
                "-t",
                f"{duration:.3f}",
                "-c:v",
                "libx264",
                "-preset",
                "veryfast",
                "-crf",
                "25",
                "-c:a",
                "aac",
                "-b:a",
                "160k",
                "-pix_fmt",
                "yuv420p",
                str(video),
            ]
        )
        scene_videos.append(video)
        timings.append(SceneTiming(index=index, title=str(scene["title"]), start=cursor, duration=duration))
        cursor += duration

    concat_file = output / "concat.txt"
    concat_file.write_text("\n".join(f"file '{item.name}'" for item in scene_videos) + "\n", encoding="utf-8")
    joined = output / "joined.mp4"
    run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(concat_file),
            "-c",
            "copy",
            str(joined),
        ]
    )
    subtitles = output / "captions.srt"
    write_subtitles(scenes, timings, subtitles)
    final_video = output / str(content["video_filename"])
    subtitle_filter = (
        f"subtitles={subtitles}:force_style='FontName=DejaVu Sans,FontSize=12,"
        "PrimaryColour=&H00FFFFFF,OutlineColour=&H40000000,BorderStyle=3,"
        "BackColour=&H900C1429,Outline=1,Shadow=0,MarginV=38,Alignment=2'"
    )
    run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(joined),
            "-vf",
            subtitle_filter,
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-crf",
            "24",
            "-c:a",
            "copy",
            "-movflags",
            "+faststart",
            "-metadata",
            f"title={content['video_title']}",
            str(final_video),
        ],
    )
    return timings


def render_shorts(
    content: dict[str, Any],
    output: Path,
    timings: list[SceneTiming],
) -> list[dict[str, Any]]:
    rendered: list[dict[str, Any]] = []
    shorts_root = output / "shorts"
    captions_root = shorts_root / "captions"
    captions_root.mkdir(parents=True, exist_ok=True)
    for short_index, scene in enumerate(content["scenes"][1:9], start=1):
        scene_timing = timings[short_index]
        duration = scene_timing.duration
        if duration > 90:
            raise RuntimeError(f"short {short_index} is unexpectedly long: {duration:.3f}s")
        slug = str(scene["slug"])
        audio = output / f"scene-{short_index + 1:02d}.aac"
        slide = shorts_root / "covers" / f"{short_index:02d}-{slug}.png"
        captions = captions_root / f"{short_index:02d}-{slug}.srt"
        target = shorts_root / f"{short_index:02d}-{slug}.mp4"
        write_subtitles(
            [scene],
            [SceneTiming(index=0, title=str(scene["title"]), start=0.0, duration=duration)],
            captions,
        )
        fade_out = max(0.0, duration - 0.3)
        subtitle_filter = (
            f"subtitles={captions}:force_style='FontName=DejaVu Sans,FontSize=11,"
            "PrimaryColour=&H00FFFFFF,OutlineColour=&H40000000,BorderStyle=3,"
            "BackColour=&H900C1429,Outline=1,Shadow=0,MarginV=76,Alignment=2'"
        )
        filter_graph = (
            "scale=1188:2112,"
            "zoompan=z='min(zoom+0.00007,1.04)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1080x1920:fps=30,"
            f"fade=t=in:st=0:d=0.25,fade=t=out:st={fade_out:.3f}:d=0.30,"
            f"{subtitle_filter},format=yuv420p"
        )
        run(
            [
                "ffmpeg",
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-loop",
                "1",
                "-framerate",
                "30",
                "-i",
                str(slide),
                "-i",
                str(audio),
                "-vf",
                filter_graph,
                "-t",
                f"{duration:.3f}",
                "-c:v",
                "libx264",
                "-preset",
                "veryfast",
                "-crf",
                "24",
                "-c:a",
                "aac",
                "-b:a",
                "160k",
                "-pix_fmt",
                "yuv420p",
                "-movflags",
                "+faststart",
                "-metadata",
                f"title={scene['short_title']}",
                str(target),
            ]
        )
        rendered.append(
            {
                "index": short_index,
                "slug": slug,
                "title": scene["short_title"],
                "duration_seconds": round(duration, 3),
                "video": str(target.relative_to(output)),
                "cover": str(slide.relative_to(output)),
                "captions": str(captions.relative_to(output)),
            }
        )
    return rendered


def validate_content(content: dict[str, Any]) -> None:
    required = {
        "video_title",
        "video_filename",
        "thumbnail_title",
        "thumbnail_badge",
        "thumbnail_lines",
        "thumbnail_footer",
        "thumbnail_visual",
        "article_url",
        "channel_url",
        "voice_disclosure",
        "description_intro",
        "hashtags",
        "short_hashtags",
        "tags",
        "visual_sources",
        "scenes",
    }
    missing = sorted(required - content.keys())
    if missing:
        raise ValueError(f"missing content keys: {', '.join(missing)}")
    if not 8 <= len(content["scenes"]) <= 15:
        raise ValueError("expected 8-15 scenes")
    total_words = 0
    for index, scene in enumerate(content["scenes"], start=1):
        scene_required = {"kicker", "title", "subtitle", "facts", "accent", "visual", "narration"}
        scene_missing = sorted(scene_required - scene.keys())
        if scene_missing:
            raise ValueError(f"scene {index} missing keys: {', '.join(scene_missing)}")
        if not 2 <= len(scene["facts"]) <= 4:
            raise ValueError(f"scene {index} must contain 2-4 facts")
        narration = str(scene["narration"])
        if len(narration) > 4096:
            raise ValueError(f"scene {index} exceeds the Speech API input limit")
        total_words += len(re.findall(r"[A-Za-z0-9][A-Za-z0-9'-]*", narration))
    if not 1200 <= total_words <= 1800:
        raise ValueError(f"narration must contain 1,200-1,800 words; found {total_words}")
    if "AI-generated voice" not in str(content["voice_disclosure"]):
        raise ValueError("voice disclosure must clearly identify the AI-generated voice")
    if len(content["visual_sources"]) != 8:
        raise ValueError("expected one credited visual source record for each of the eight tweaks")
    source_ids = [str(item["id"]) for item in content["visual_sources"]]
    if len(set(source_ids)) != len(source_ids):
        raise ValueError("visual source IDs must be unique")
    short_slugs: list[str] = []
    for scene_index, scene in enumerate(content["scenes"][1:9], start=1):
        for key in ("slug", "short_title"):
            if not scene.get(key):
                raise ValueError(f"short scene {scene_index} is missing {key}")
        short_slugs.append(str(scene["slug"]))
        for source_id in scene["visual"].get("source_ids", []):
            if str(source_id) not in source_ids:
                raise ValueError(f"short scene {scene_index} references an unknown visual source: {source_id}")
    if len(set(short_slugs)) != 8:
        raise ValueError("short slugs must be unique")


def validate_visual_assets(content: dict[str, Any], assets_root: Path) -> None:
    visuals = [content["thumbnail_visual"], *(scene["visual"] for scene in content["scenes"])]
    for visual_index, visual in enumerate(visuals, start=1):
        paths = visual.get("assets", [])
        if not 1 <= len(paths) <= 4:
            raise ValueError(f"visual {visual_index} must contain one to four assets")
        for relative_path in paths:
            load_visual_asset(assets_root, str(relative_path))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--content", type=Path, default=Path(__file__).with_name("content.json"))
    parser.add_argument("--output", type=Path, default=Path("video-output"))
    parser.add_argument("--render", action="store_true", help="Generate speech and the final MP4")
    parser.add_argument("--voice", default=VOICE)
    args = parser.parse_args()

    content = json.loads(args.content.read_text(encoding="utf-8"))
    validate_content(content)
    args.output.mkdir(parents=True, exist_ok=True)
    repository_root = Path(__file__).resolve().parents[2]
    assets_root = Path(__file__).resolve().parent
    validate_visual_assets(content, assets_root)
    logo_path = repository_root / "NextSolutionRepoIcon.png"
    for index, scene in enumerate(content["scenes"]):
        render_slide(
            scene,
            index,
            len(content["scenes"]),
            logo_path,
            assets_root,
            args.output / "slides" / f"scene-{index + 1:02d}.png",
        )
    render_thumbnail(content, logo_path, assets_root, args.output / "thumbnail.png")
    for short_index, scene in enumerate(content["scenes"][1:9], start=1):
        render_short_slide(
            scene,
            short_index,
            8,
            logo_path,
            assets_root,
            args.output / "shorts" / "covers" / f"{short_index:02d}-{scene['slug']}.png",
        )
    write_shorts_metadata(content, args.output)

    timings: list[SceneTiming] = []
    shorts: list[dict[str, Any]] = []
    if args.render:
        for executable in ("ffmpeg", "ffprobe"):
            run([executable, "-version"], capture=True)
        api_key = os.environ.get("OPENAI_API_KEY", "")
        if not api_key:
            raise SystemExit("OPENAI_API_KEY is required when --render is used")
        timings = render_video(content, args.output, api_key=api_key, voice=args.voice)
        shorts = render_shorts(content, args.output, timings)
    else:
        # Approximate chapter starts are useful in a design-only preview.
        cursor = 0.0
        for index, scene in enumerate(content["scenes"]):
            word_count = len(str(scene["narration"]).split())
            duration = word_count / 140 * 60
            timings.append(SceneTiming(index=index, title=str(scene["title"]), start=cursor, duration=duration))
            cursor += duration
        shorts = [
            {
                "index": short_index,
                "slug": scene["slug"],
                "title": scene["short_title"],
                "duration_seconds": round(timings[short_index].duration, 3),
                "video": None,
                "cover": f"shorts/covers/{short_index:02d}-{scene['slug']}.png",
                "captions": None,
            }
            for short_index, scene in enumerate(content["scenes"][1:9], start=1)
        ]
    write_metadata(content, timings, args.output)
    manifest = {
        "title": content["video_title"],
        "scene_count": len(content["scenes"]),
        "short_count": len(shorts),
        "duration_seconds": round(sum(item.duration for item in timings), 3),
        "rendered": bool(args.render),
        "model": MODEL if args.render else None,
        "voice": args.voice if args.render else None,
        "voice_disclosure": content["voice_disclosure"],
        "scenes": [
            {
                "index": item.index + 1,
                "title": item.title,
                "start_seconds": round(item.start, 3),
                "duration_seconds": round(item.duration, 3),
            }
            for item in timings
        ],
        "shorts": shorts,
        "files": {
            "video": content["video_filename"] if args.render else None,
            "thumbnail": "thumbnail.png",
            "captions": "captions.srt" if args.render else None,
            "metadata": "youtube-metadata.json",
            "shorts_metadata": "shorts/youtube-shorts-metadata.json",
        },
    }
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
