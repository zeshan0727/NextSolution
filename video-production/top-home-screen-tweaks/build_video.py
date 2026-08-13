#!/usr/bin/env python3
"""Build the first Next Solution YouTube package from original source material."""

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
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError as exc:  # pragma: no cover - dependency is installed in CI
    raise SystemExit("Pillow is required: python3 -m pip install Pillow") from exc


WIDTH = 1920
HEIGHT = 1080
THUMB_WIDTH = 1280
THUMB_HEIGHT = 720
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
    draw.text((x + size + 20, y + 5), "Next", font=font(34 if small else 40, bold=True), fill=(22, 29, 52, 255))
    draw.text((x + size + 113, y + 5), "Solution", font=font(34 if small else 40), fill=(48, 60, 91, 255))


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


def render_slide(scene: dict[str, Any], index: int, count: int, logo_path: Path, target: Path) -> None:
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
    draw_phone(image, str(scene["accent"]), index)
    draw.text((86, 1012), "NEXTSOLUTION.CC", font=font(24, bold=True), fill=(87, 98, 127, 255))
    progress_left, progress_right = 530, 1240
    draw.rounded_rectangle((progress_left, 1022, progress_right, 1030), radius=4, fill=(204, 211, 230, 255))
    progress = progress_left + round((progress_right - progress_left) * ((index + 1) / count))
    draw.rounded_rectangle((progress_left, 1022, progress, 1030), radius=4, fill=accent)
    draw.text((1280, 1009), f"{index + 1:02d} / {count:02d}", font=font(24, bold=True), fill=(87, 98, 127, 255))
    target.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(target, quality=95)


def render_thumbnail(content: dict[str, Any], logo_path: Path, target: Path) -> None:
    accent = "#5b5ce2"
    image = gradient((THUMB_WIDTH, THUMB_HEIGHT), accent)
    draw = ImageDraw.Draw(image)
    draw_brand(image, logo_path, small=True)
    draw.rounded_rectangle((58, 150, 325, 204), radius=27, fill=(*hex_rgb(accent), 255))
    draw.text((86, 160), str(content["thumbnail_badge"]), font=font(25, bold=True), fill="white")
    lines = ["TOP 8", "HOME SCREEN", "TWEAKS"]
    y = 244
    for position, line in enumerate(lines):
        face = font(92 if position == 0 else 70, bold=True)
        colour = (*hex_rgb(accent), 255) if position == 0 else (20, 28, 53, 255)
        draw.text((58, y), line, font=face, fill=colour, stroke_width=1)
        y += 102 if position == 0 else 86
    draw.rounded_rectangle((59, 598, 803, 662), radius=25, fill=(255, 255, 255, 220), outline=(205, 213, 232, 255), width=2)
    draw.text((87, 612), "LAYOUTS  •  FOLDERS  •  WIDGETS", font=font(27, bold=True), fill=(58, 68, 96, 255))
    draw_phone(image, accent, 0, thumb=True)
    target.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(target, quality=96)


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


def write_metadata(content: dict[str, Any], timings: list[SceneTiming], output: Path) -> None:
    chapter_lines = [f"{chapter_timestamp(item.start)} {item.title}" for item in timings]
    description = (
        "Eight Home Screen jailbreak tweaks for layouts, folders, widgets and shortcuts, compared using their current package listings. "
        "This is an editorial overview, not a hands-on compatibility test. Always confirm your exact iOS version, jailbreak, bootstrap, architecture, dependencies and current package details before installing.\n\n"
        f"Read the full comparison: {content['article_url']}\n\n"
        "CHAPTERS\n"
        + "\n".join(chapter_lines)
        + "\n\n"
        + str(content["voice_disclosure"])
        + " Original script and graphics by Next Solution. Package names and trademarks belong to their respective owners.\n\n"
        "#JailbreakTweaks #iPhoneCustomization #HomeScreen"
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
    }
    (output / "youtube-metadata.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (output / "youtube-description.txt").write_text(description + "\n", encoding="utf-8")


def render_video(content: dict[str, Any], output: Path, *, api_key: str, voice: str) -> list[SceneTiming]:
    scenes = content["scenes"]
    scene_videos: list[Path] = []
    timings: list[SceneTiming] = []
    cursor = 0.0
    for index, scene in enumerate(scenes):
        audio = output / f"scene-{index + 1:02d}.aac"
        video = output / f"scene-{index + 1:02d}.mp4"
        slide = output / "slides" / f"scene-{index + 1:02d}.png"
        generate_speech(str(scene["narration"]), audio, api_key=api_key, voice=voice)
        duration = media_duration(audio)
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
    final_video = output / "top-8-home-screen-tweaks-2026.mp4"
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


def validate_content(content: dict[str, Any]) -> None:
    required = {"video_title", "thumbnail_title", "thumbnail_badge", "article_url", "channel_url", "voice_disclosure", "tags", "scenes"}
    missing = sorted(required - content.keys())
    if missing:
        raise ValueError(f"missing content keys: {', '.join(missing)}")
    if not 8 <= len(content["scenes"]) <= 15:
        raise ValueError("expected 8-15 scenes")
    total_words = 0
    for index, scene in enumerate(content["scenes"], start=1):
        scene_required = {"kicker", "title", "subtitle", "facts", "accent", "narration"}
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
    logo_path = repository_root / "NextSolutionRepoIcon.png"
    for index, scene in enumerate(content["scenes"]):
        render_slide(scene, index, len(content["scenes"]), logo_path, args.output / "slides" / f"scene-{index + 1:02d}.png")
    render_thumbnail(content, logo_path, args.output / "thumbnail.png")

    timings: list[SceneTiming] = []
    if args.render:
        for executable in ("ffmpeg", "ffprobe"):
            run([executable, "-version"], capture=True)
        api_key = os.environ.get("OPENAI_API_KEY", "")
        if not api_key:
            raise SystemExit("OPENAI_API_KEY is required when --render is used")
        timings = render_video(content, args.output, api_key=api_key, voice=args.voice)
    else:
        # Approximate chapter starts are useful in a design-only preview.
        cursor = 0.0
        for index, scene in enumerate(content["scenes"]):
            word_count = len(str(scene["narration"]).split())
            duration = word_count / 140 * 60
            timings.append(SceneTiming(index=index, title=str(scene["title"]), start=cursor, duration=duration))
            cursor += duration
    write_metadata(content, timings, args.output)
    manifest = {
        "title": content["video_title"],
        "scene_count": len(content["scenes"]),
        "duration_seconds": round(sum(item.duration for item in timings), 3),
        "rendered": bool(args.render),
        "model": MODEL if args.render else None,
        "voice": args.voice if args.render else None,
        "voice_disclosure": content["voice_disclosure"],
        "files": {
            "video": "top-8-home-screen-tweaks-2026.mp4" if args.render else None,
            "thumbnail": "thumbnail.png",
            "captions": "captions.srt" if args.render else None,
            "metadata": "youtube-metadata.json",
        },
    }
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
