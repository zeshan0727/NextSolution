#!/usr/bin/env python3
"""Generate clean GitHub Pages routes from root HTML files.

The repository keeps root ``*.html`` files as legacy publisher targets, while
public URLs are served from ``/<slug>/index.html``. This script is idempotent
and also rewrites site navigation, canonical URLs, feed/sitemap URLs, and
social preview images to GitHub-Pages-safe values.
"""

from __future__ import annotations

from pathlib import Path
import re
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
SITE = "https://nextjailbreak.com"
SOCIAL_IMAGE = f"{SITE}/assets/brand/next-jailbreak-social-card.png"

ATTR_RE = re.compile(
    r"(?P<prefix>\b(?:href|src|poster|action)\s*=\s*)(?P<quote>[\"'])(?P<url>.*?)(?P=quote)",
    re.IGNORECASE,
)
META_IMAGE_RE = re.compile(
    r"(?P<prefix><meta\s+[^>]*(?:property|name)=[\"'](?:og:image|twitter:image)[\"'][^>]*content=[\"'])(?P<url>[^\"']+)(?P<suffix>[\"'][^>]*>)",
    re.IGNORECASE,
)
META_IMAGE_RE_REVERSED = re.compile(
    r"(?P<prefix><meta\s+[^>]*content=[\"'])(?P<url>[^\"']+)(?P<middle>[\"'][^>]*(?:property|name)=[\"'](?:og:image|twitter:image)[\"'][^>]*>)",
    re.IGNORECASE,
)
JSON_LD_IMAGE_RE = re.compile(r'"image"\s*:\s*"(?P<url>https://[^"\\]+)"', re.IGNORECASE)
ARTICLE_HERO_IMAGE_RE = re.compile(
    r'<figure\s+class=[\"\'][^\"\']*article-visual[^\"\']*[\"\'][^>]*>.*?<img\s+[^>]*src=[\"\'](?P<url>https://[^\"\']+)[\"\']',
    re.IGNORECASE | re.DOTALL,
)
REDIRECT_MARKER = "data-clean-url-redirect"
REDIRECT_SCRIPT = """  <script data-clean-url-redirect>\n    (function () {\n      var path = window.location.pathname;\n      if (/\\.html$/i.test(path) && path.toLowerCase() !== '/index.html') {\n        window.location.replace(path.slice(0, -5) + '/' + window.location.search + window.location.hash);\n      }\n    }());\n  </script>\n"""


def page_names() -> set[str]:
    return {
        path.name
        for path in ROOT.glob("*.html")
        if path.name.lower() not in {"index.html", "404.html"}
    }


def clean_path(filename: str) -> str:
    return f"/{filename[:-5]}/"


def _assemble(path: str, query: str, fragment: str) -> str:
    value = path
    if query:
        value += "?" + query
    if fragment:
        value += "#" + fragment
    return value


def rewrite_url(value: str, pages: set[str]) -> str:
    raw = value.strip()
    if not raw or raw.startswith("#") or raw.startswith("//"):
        return value
    if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", raw):
        parsed = urlsplit(raw)
        if parsed.scheme not in {"http", "https"} or parsed.netloc.lower() not in {
            "nextjailbreak.com",
            "www.nextjailbreak.com",
        }:
            return value
        local = parsed.path.lstrip("/")
        if local == "index.html":
            path = "/"
        elif local in pages:
            path = clean_path(local)
        else:
            return value
        return f"{SITE}{_assemble(path, parsed.query, parsed.fragment)}"

    parsed = urlsplit(raw)
    local = parsed.path
    normalized = local.lstrip("/")
    while normalized.startswith("./"):
        normalized = normalized[2:]

    if normalized in {"", "."}:
        path = "/"
    elif normalized == "index.html":
        path = "/"
    elif normalized in pages:
        path = clean_path(normalized)
    elif local.startswith("/"):
        path = local
    else:
        # Root HTML files historically resolve relative assets from /. Their
        # clean copies live one directory deeper, so make those references
        # root-absolute to preserve the existing site layout and assets.
        path = "/" + normalized
    return _assemble(path, parsed.query, parsed.fragment)


def rewrite_attributes(text: str, pages: set[str]) -> str:
    def repl(match: re.Match[str]) -> str:
        url = rewrite_url(match.group("url"), pages)
        return f"{match.group('prefix')}{match.group('quote')}{url}{match.group('quote')}"

    return ATTR_RE.sub(repl, text)


def rewrite_absolute_page_urls(text: str, pages: set[str]) -> str:
    for filename in sorted(pages, key=len, reverse=True):
        slug = filename[:-5]
        text = text.replace(f"https://nextjailbreak.com/{filename}", f"https://nextjailbreak.com/{slug}/")
        text = text.replace(f"https://www.nextjailbreak.com/{filename}", f"https://nextjailbreak.com/{slug}/")
        text = text.replace(f"http://nextjailbreak.com/{filename}", f"https://nextjailbreak.com/{slug}/")
        text = text.replace(f"http://www.nextjailbreak.com/{filename}", f"https://nextjailbreak.com/{slug}/")
    return text


def social_image_is_safe(url: str) -> bool:
    parsed = urlsplit(url)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        return False

    host = parsed.netloc.lower()
    if host in {"nextjailbreak.com", "www.nextjailbreak.com"}:
        return parsed.path.lower().endswith((".png", ".jpg", ".jpeg", ".webp"))

    # Havoc serves package screenshots from extensionless HTTPS media URLs.
    # Those are valid Open Graph/Twitter card images and should not be replaced
    # by the generic Next Jailbreak brand image.
    if host == "media.havoc.app":
        return True

    # Preserve other attributable external raster images when the URL itself
    # clearly identifies a supported image format.
    return parsed.path.lower().endswith((".png", ".jpg", ".jpeg", ".webp"))


def preferred_social_image(text: str) -> str | None:
    """Recover the article-specific image from structured data or the hero.

    Older clean-url runs replaced external OG/Twitter images with the generic
    Next Jailbreak showcase image. The original article image is still present
    in JSON-LD and/or the authentic article hero, so use it to restore cards.
    """
    for pattern in (JSON_LD_IMAGE_RE, ARTICLE_HERO_IMAGE_RE):
        match = pattern.search(text)
        if match:
            candidate = match.group("url")
            if social_image_is_safe(candidate):
                return candidate
    return None


def stabilize_social_images(text: str) -> str:
    article_image = preferred_social_image(text)

    def replacement_for(url: str) -> str:
        if social_image_is_safe(url) and url != SOCIAL_IMAGE:
            return url
        if article_image:
            return article_image
        if social_image_is_safe(url):
            return url
        return SOCIAL_IMAGE

    def repl(match: re.Match[str]) -> str:
        url = replacement_for(match.group("url"))
        return f"{match.group('prefix')}{url}{match.group('suffix')}"

    text = META_IMAGE_RE.sub(repl, text)

    def repl_reversed(match: re.Match[str]) -> str:
        url = replacement_for(match.group("url"))
        return f"{match.group('prefix')}{url}{match.group('middle')}"

    return META_IMAGE_RE_REVERSED.sub(repl_reversed, text)


def ensure_legacy_redirect(text: str) -> str:
    if REDIRECT_MARKER in text or "</head>" not in text:
        return text
    return text.replace("</head>", REDIRECT_SCRIPT + "</head>", 1)


def normalize_html(text: str, pages: set[str], *, legacy_redirect: bool) -> str:
    text = rewrite_attributes(text, pages)
    text = rewrite_absolute_page_urls(text, pages)
    text = stabilize_social_images(text)
    if legacy_redirect:
        text = ensure_legacy_redirect(text)
    return text


def update_discovery_file(path: Path, pages: set[str]) -> None:
    if not path.exists():
        return
    old = path.read_text(encoding="utf-8")
    new = rewrite_absolute_page_urls(old, pages)
    if new != old:
        path.write_text(new, encoding="utf-8")


def main() -> int:
    pages = page_names()
    if not pages:
        raise SystemExit("no root HTML pages found")

    # Keep the homepage at /, but make every link it emits clean.
    index = ROOT / "index.html"
    if index.exists():
        old = index.read_text(encoding="utf-8")
        new = normalize_html(old, pages, legacy_redirect=False)
        if new != old:
            index.write_text(new, encoding="utf-8")

    for filename in sorted(pages):
        source = ROOT / filename
        old = source.read_text(encoding="utf-8")
        normalized = normalize_html(old, pages, legacy_redirect=True)
        if normalized != old:
            source.write_text(normalized, encoding="utf-8")

        target_dir = ROOT / filename[:-5]
        if target_dir.exists():
            unexpected = [p for p in target_dir.iterdir() if p.name != "index.html"]
            if unexpected:
                raise RuntimeError(
                    f"clean URL target conflicts with existing directory content: {target_dir}"
                )
        target_dir.mkdir(parents=True, exist_ok=True)
        target = target_dir / "index.html"
        if not target.exists() or target.read_text(encoding="utf-8") != normalized:
            target.write_text(normalized, encoding="utf-8")

    update_discovery_file(ROOT / "feed.xml", pages)
    update_discovery_file(ROOT / "sitemap.xml", pages)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())