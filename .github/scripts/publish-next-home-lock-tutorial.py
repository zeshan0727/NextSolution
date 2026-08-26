#!/usr/bin/env python3
"""Validate and maintain the Next Home Lock tutorial publication.

The script is intentionally idempotent. It preserves unrelated website content and
uses permanent markers to prevent duplicate homepage and Tutorials-page cards.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VERSION = "1.0.5"
ARTICLE = ROOT / "next-home-lock-tweak-ios16.html"
INDEX = ROOT / "index.html"
TUTORIALS = ROOT / "tutorials.html"
SITEMAP = ROOT / "sitemap.xml"
HERO = ROOT / "assets/next-home-lock/next-home-lock-hero.svg"
SETTINGS = ROOT / "assets/next-home-lock/next-home-lock-settings.svg"
ADSENSE_CLIENT = "ca-pub-4770123899731214"
ROOT_HIDE = "NextHomeLock_1.0.5_RootHide.deb"
ROOTLESS = "NextHomeLock_1.0.5_Rootless.deb"
ARTICLE_URL = "https://nextjailbreak.com/next-home-lock-tweak-ios16.html"

RECENT_START = "<!-- NEXT_HOME_LOCK_RECENT_CARD_START -->"
RECENT_END = "<!-- NEXT_HOME_LOCK_RECENT_CARD_END -->"
TUTORIAL_START = "<!-- NEXT_HOME_LOCK_TUTORIAL_CARD_START -->"
TUTORIAL_END = "<!-- NEXT_HOME_LOCK_TUTORIAL_CARD_END -->"


def read(path: Path) -> str:
    if not path.is_file():
        raise SystemExit(f"Missing required file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def replace_marked_block(text: str, start: str, end: str, replacement: str) -> str:
    pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
    if pattern.search(text):
        return pattern.sub(replacement.strip(), text, count=1)
    raise SystemExit(f"Missing publication markers: {start} / {end}")


def normalize() -> list[Path]:
    changed: list[Path] = []

    article = read(ARTICLE)
    replacements = {
        "Next Home Lock 1.0.4": f"Next Home Lock {VERSION}",
        "NextHomeLock_1.0.4_RootHide.deb": ROOT_HIDE,
        "NextHomeLock_1.0.4_Rootless.deb": ROOTLESS,
        "version 1.0.4 was physically confirmed": "the diagnostic release was physically confirmed",
    }
    for old, new in replacements.items():
        article = article.replace(old, new)
    if article != read(ARTICLE):
        ARTICLE.write_text(article, encoding="utf-8")
        changed.append(ARTICLE)

    # Reinsert the already-reviewed card blocks exactly once if a future edit changes them.
    index = read(INDEX)
    recent_match = re.search(
        re.escape(RECENT_START) + r".*?" + re.escape(RECENT_END), index, re.S
    )
    if not recent_match:
        raise SystemExit("Homepage Next Home Lock card markers are missing")
    normalized_index = replace_marked_block(
        index, RECENT_START, RECENT_END, recent_match.group(0)
    )
    if normalized_index != index:
        INDEX.write_text(normalized_index, encoding="utf-8")
        changed.append(INDEX)

    tutorials = read(TUTORIALS)
    tutorial_match = re.search(
        re.escape(TUTORIAL_START) + r".*?" + re.escape(TUTORIAL_END), tutorials, re.S
    )
    if not tutorial_match:
        raise SystemExit("Tutorials-page Next Home Lock card markers are missing")
    normalized_tutorials = replace_marked_block(
        tutorials, TUTORIAL_START, TUTORIAL_END, tutorial_match.group(0)
    )
    if normalized_tutorials != tutorials:
        TUTORIALS.write_text(normalized_tutorials, encoding="utf-8")
        changed.append(TUTORIALS)

    sitemap = read(SITEMAP)
    entry = (
        "  <url><loc>https://nextjailbreak.com/next-home-lock-tweak-ios16.html</loc>"
        "<lastmod>2026-07-30</lastmod><changefreq>monthly</changefreq>"
        "<priority>0.9</priority></url>"
    )
    occurrences = sitemap.count(ARTICLE_URL)
    if occurrences == 0:
        sitemap = sitemap.replace("</urlset>", entry + "\n</urlset>")
    elif occurrences > 1:
        rows = sitemap.splitlines()
        kept = []
        seen = False
        for row in rows:
            if ARTICLE_URL in row:
                if seen:
                    continue
                seen = True
                row = entry
            kept.append(row)
        sitemap = "\n".join(kept) + "\n"
    if sitemap != read(SITEMAP):
        SITEMAP.write_text(sitemap, encoding="utf-8")
        changed.append(SITEMAP)

    return changed


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"Validation failed: {label}")


def validate() -> None:
    article = read(ARTICLE)
    index = read(INDEX)
    tutorials = read(TUTORIALS)
    sitemap = read(SITEMAP)
    for asset in (HERO, SETTINGS):
        if not asset.is_file():
            raise SystemExit(f"Missing asset: {asset.relative_to(ROOT)}")

    checks = [
        (article, f"Next Home Lock {VERSION}", "article version"),
        (article, 'href="./"', "Home navigation"),
        (article, 'href="tutorials.html" aria-current="page"', "active Tutorials tab"),
        (article, 'href="videos.html"', "Videos navigation"),
        (article, 'href="./#faq"', "FAQ navigation"),
        (article, ROOT_HIDE, "RootHide filename"),
        (article, ROOTLESS, "rootless filename"),
        (article, "raw.githubusercontent.com/zeshan0727/NextSolution/main/debfiles/", "new repository download base"),
        (article, ADSENSE_CLIENT, "AdSense client"),
        (article, '"@type": "TechArticle"', "TechArticle metadata"),
        (index, RECENT_START, "homepage start marker"),
        (index, RECENT_END, "homepage end marker"),
        (tutorials, TUTORIAL_START, "Tutorials start marker"),
        (tutorials, TUTORIAL_END, "Tutorials end marker"),
        (sitemap, ARTICLE_URL, "sitemap entry"),
    ]
    for text, needle, label in checks:
        require(text, needle, label)

    if index.count(RECENT_START) != 1 or index.count(RECENT_END) != 1:
        raise SystemExit("Homepage card markers are duplicated")
    if tutorials.count(TUTORIAL_START) != 1 or tutorials.count(TUTORIAL_END) != 1:
        raise SystemExit("Tutorials card markers are duplicated")
    if sitemap.count(ARTICLE_URL) != 1:
        raise SystemExit("Sitemap entry is missing or duplicated")
    if article.count("pagead2.googlesyndication.com/pagead/js/adsbygoogle.js") != 1:
        raise SystemExit("AdSense loader must appear exactly once in the tutorial")
    if "zeshan0727.github.io" in article:
        raise SystemExit("Tutorial still depends on the retired repository")
    if "Next Home Lock 1.0.4" in article:
        raise SystemExit("Old article version remains")
    if any(term in article for term in ("SpringBoard Injection", "Touch Hook", "Test Lock Now", "Refresh Diagnostics")):
        raise SystemExit("Removed diagnostic controls are still advertised")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Validate without modifying files")
    args = parser.parse_args()

    changed: list[Path] = []
    if not args.check:
        changed = normalize()
    validate()

    if changed:
        print("Changed files:")
        for path in changed:
            print(f"- {path.relative_to(ROOT)}")
    else:
        print("Next Home Lock tutorial files are already current.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
