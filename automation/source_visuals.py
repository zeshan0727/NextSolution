#!/usr/bin/env python3
"""Acquire unique, source-grounded visuals for editorial/news pages.

The publisher must never fall back to a repeated generic hero. It inspects the
actual cited source pages, finds editorial imagery (Open Graph/Twitter/inline
images), validates the returned file, and stores a local copy. A visual URL may
only be assigned to one article, which prevents a cluster of automated pages
from reusing the same source preview.
"""

from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
from html.parser import HTMLParser
import json
import mimetypes
from pathlib import Path
import re
from typing import Iterable
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen


USER_AGENT = (
    "Mozilla/5.0 (compatible; NextJailbreakEditorialBot/1.0; "
    "+https://nextjailbreak.com/)"
)
MAX_IMAGE_BYTES = 8 * 1024 * 1024
BAD_TERMS = (
    "avatar",
    "favicon",
    "logo",
    "icon",
    "emoji",
    "badge",
    "shield",
    "pixel",
    "tracking",
    "spinner",
    "sponsor",
    "donate",
    "button",
    "profile",
)
GOOD_TERMS = (
    "screenshot",
    "screen-shot",
    "preview",
    "hero",
    "banner",
    "demo",
    "feature",
    "cover",
    "social",
    "opengraph",
    "open-graph",
    "readme",
    "assets",
)


@dataclass(frozen=True)
class VisualCandidate:
    image_url: str
    source_url: str
    score: int
    origin: str


class _MediaParser(HTMLParser):
    def __init__(self, source_url: str) -> None:
        super().__init__(convert_charrefs=True)
        self.source_url = source_url
        self.candidates: list[VisualCandidate] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {str(key).lower(): str(value or "") for key, value in attrs}
        if tag.lower() == "meta":
            prop = (values.get("property") or values.get("name") or "").lower()
            content = values.get("content", "").strip()
            if content and prop in {
                "og:image",
                "og:image:url",
                "og:image:secure_url",
                "twitter:image",
                "twitter:image:src",
            }:
                score = 120 if prop.startswith("og:") else 110
                self._add(content, score, prop)
        elif tag.lower() == "img":
            src = (values.get("src") or values.get("data-src") or values.get("data-lazy-src") or "").strip()
            if not src:
                return
            descriptor = " ".join(
                filter(None, (values.get("alt"), values.get("class"), values.get("id"), src))
            ).lower()
            score = 55
            if any(term in descriptor for term in GOOD_TERMS):
                score += 35
            self._add(src, score, "img")

    def _add(self, value: str, score: int, origin: str) -> None:
        url = urljoin(self.source_url, value)
        parsed = urlparse(url)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            return
        lowered = url.lower()
        if any(term in lowered for term in BAD_TERMS):
            return
        if any(term in lowered for term in GOOD_TERMS):
            score += 15
        self.candidates.append(VisualCandidate(url, self.source_url, score, origin))


def _fetch(url: str, *, max_bytes: int, accept: str) -> tuple[bytes, str]:
    request = Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": accept,
            "Accept-Language": "en-US,en;q=0.8",
        },
    )
    with urlopen(request, timeout=20) as response:  # nosec - source URLs are repository-controlled editorial inputs
        content_type = str(response.headers.get("Content-Type", "")).split(";", 1)[0].strip().lower()
        body = response.read(max_bytes + 1)
        if len(body) > max_bytes:
            raise ValueError(f"remote resource exceeded {max_bytes} bytes")
        return body, content_type


def candidates_from_html(source_url: str, html_text: str) -> list[VisualCandidate]:
    parser = _MediaParser(source_url)
    parser.feed(html_text)
    best: dict[str, VisualCandidate] = {}
    for candidate in parser.candidates:
        current = best.get(candidate.image_url)
        if current is None or candidate.score > current.score:
            best[candidate.image_url] = candidate
    return sorted(best.values(), key=lambda item: (-item.score, item.image_url))


def discover_candidates(source_urls: Iterable[str]) -> list[VisualCandidate]:
    all_candidates: list[VisualCandidate] = []
    for source_url in source_urls:
        try:
            body, content_type = _fetch(
                source_url,
                max_bytes=3 * 1024 * 1024,
                accept="text/html,application/xhtml+xml;q=0.9,*/*;q=0.5",
            )
        except Exception:
            continue
        if "html" not in content_type and not body.lstrip().startswith((b"<!", b"<html", b"<HTML")):
            continue
        text = body.decode("utf-8", errors="replace")
        all_candidates.extend(candidates_from_html(source_url, text))
    best: dict[str, VisualCandidate] = {}
    for candidate in all_candidates:
        current = best.get(candidate.image_url)
        if current is None or candidate.score > current.score:
            best[candidate.image_url] = candidate
    return sorted(best.values(), key=lambda item: (-item.score, item.image_url))


def _extension(content_type: str, image_url: str) -> str:
    preferred = {
        "image/jpeg": ".jpg",
        "image/png": ".png",
        "image/webp": ".webp",
        "image/gif": ".gif",
    }.get(content_type)
    if preferred:
        return preferred
    suffix = Path(urlparse(image_url).path).suffix.lower()
    if suffix in {".jpg", ".jpeg", ".png", ".webp", ".gif"}:
        return ".jpg" if suffix == ".jpeg" else suffix
    guessed = mimetypes.guess_extension(content_type or "")
    return guessed if guessed in {".jpg", ".png", ".webp", ".gif"} else ".jpg"


def load_registry(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("source visual registry must be an object")
    return {str(key): str(item) for key, item in value.items()}


def save_registry(path: Path, registry: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(registry, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def acquire_unique_source_visual(
    *,
    source_urls: Iterable[str],
    slug: str,
    repository_root: Path,
    registry_path: Path | None = None,
) -> dict[str, str]:
    registry_path = registry_path or repository_root / "automation/source-visual-registry.json"
    registry = load_registry(registry_path)
    normalized_slug = re.sub(r"[^a-z0-9-]+", "-", slug.lower()).strip("-") or "article"

    for candidate in discover_candidates(source_urls):
        owner = registry.get(candidate.image_url)
        if owner and owner != normalized_slug:
            continue
        try:
            body, content_type = _fetch(candidate.image_url, max_bytes=MAX_IMAGE_BYTES, accept="image/*,*/*;q=0.2")
        except Exception:
            continue
        if not content_type.startswith("image/"):
            continue
        if len(body) < 12_000:
            # Tiny badges/icons are not useful editorial visuals.
            continue
        extension = _extension(content_type, candidate.image_url)
        digest = sha256(candidate.image_url.encode("utf-8")).hexdigest()[:10]
        relative = Path("assets/articles/source-media") / f"{normalized_slug}-{digest}{extension}"
        destination = repository_root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(body)
        registry[candidate.image_url] = normalized_slug
        save_registry(registry_path, registry)
        host = urlparse(candidate.source_url).netloc.lower().removeprefix("www.")
        return {
            "image": relative.as_posix(),
            "image_url": candidate.image_url,
            "source_url": candidate.source_url,
            "source_host": host,
            "credit": f"Source visual from {host}",
            "origin": candidate.origin,
        }

    raise ValueError(
        "No unique authentic visual was available from the cited source pages; publication is held instead of reusing a generic image."
    )
