#!/usr/bin/env python3
"""Prepare and validate the Low Power Mode Haptic tutorial publication.

The script is idempotent, preserves unrelated website content, and never merges the
approval-gated branch. Run without --check to add/update cards and sitemap data.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ARTICLE = ROOT / "low-power-mode-haptic-tweak-ios16.html"
INDEX = ROOT / "index.html"
TUTORIALS = ROOT / "tutorials.html"
SITEMAP = ROOT / "sitemap.xml"
HERO = ROOT / "assets/low-power-mode-haptic/low-power-mode-haptic-hero.svg"
SETTINGS = ROOT / "assets/low-power-mode-haptic/low-power-mode-haptic-settings.svg"
ARTICLE_URL = "https://nextsolution.cc/low-power-mode-haptic-tweak-ios16.html"
ADSENSE_CLIENT = "ca-pub-4770123899731214"
ROOT_HIDE = "LowPowerModeHaptic_1.0.0_RootHide.deb"
ROOTLESS = "LowPowerModeHaptic_1.0.0_Rootless.deb"
RECENT_START = "<!-- LOW_POWER_MODE_HAPTIC_RECENT_CARD_START -->"
RECENT_END = "<!-- LOW_POWER_MODE_HAPTIC_RECENT_CARD_END -->"
TUTORIAL_START = "<!-- LOW_POWER_MODE_HAPTIC_TUTORIAL_CARD_START -->"
TUTORIAL_END = "<!-- LOW_POWER_MODE_HAPTIC_TUTORIAL_CARD_END -->"

RECENT_CARD = f'''{RECENT_START}
<article class="tutorial-card low-power-mode-haptic-card" data-pinned="true">
  <a href="low-power-mode-haptic-tweak-ios16.html" aria-label="Read the Low Power Mode Haptic tutorial">
    <img src="assets/low-power-mode-haptic/low-power-mode-haptic-hero.svg" alt="Low Power Mode Haptic jailbreak tweak" width="1600" height="900" loading="lazy">
    <div class="tutorial-card-content"><span class="tag">New tweak</span><h3>Low Power Mode Haptic</h3><p>Feel distinct feedback when iPhone Low Power Mode turns on or off.</p></div>
  </a>
</article>
{RECENT_END}'''

TUTORIAL_CARD = f'''{TUTORIAL_START}
<article class="tutorial-card low-power-mode-haptic-card">
  <a href="low-power-mode-haptic-tweak-ios16.html" aria-label="Open Low Power Mode Haptic installation guide">
    <img src="assets/low-power-mode-haptic/low-power-mode-haptic-hero.svg" alt="Low Power Mode Haptic tweak tutorial" width="1600" height="900" loading="lazy">
    <div class="tutorial-card-content"><span class="tag">iOS 15–16</span><h3>Low Power Mode Haptic 1.0.0</h3><p>RootHide and rootless downloads, Settings guide and physical-device test checklist.</p></div>
  </a>
</article>
{TUTORIAL_END}'''

SITEMAP_ENTRY = "  <url><loc>https://nextsolution.cc/low-power-mode-haptic-tweak-ios16.html</loc><lastmod>2026-08-01</lastmod><changefreq>monthly</changefreq><priority>0.9</priority></url>"


def read(path: Path) -> str:
    if not path.is_file():
        raise SystemExit(f"Missing required file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def write_if_changed(path: Path, text: str, changed: list[Path]) -> None:
    if read(path) != text:
        path.write_text(text, encoding="utf-8")
        changed.append(path)


def upsert_marked(text: str, start: str, end: str, block: str, insertion: str) -> str:
    pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
    if pattern.search(text):
        return pattern.sub(block, text, count=1)
    if insertion not in text:
        raise SystemExit(f"Cannot find insertion point: {insertion}")
    return text.replace(insertion, block + "\n" + insertion, 1)


def normalize() -> list[Path]:
    changed: list[Path] = []
    index = upsert_marked(read(INDEX), RECENT_START, RECENT_END, RECENT_CARD, "</main>")
    write_if_changed(INDEX, index, changed)
    tutorials = upsert_marked(read(TUTORIALS), TUTORIAL_START, TUTORIAL_END, TUTORIAL_CARD, "</main>")
    write_if_changed(TUTORIALS, tutorials, changed)

    sitemap = read(SITEMAP)
    rows = [row for row in sitemap.splitlines() if ARTICLE_URL not in row]
    sitemap = "\n".join(rows)
    if "</urlset>" not in sitemap:
        raise SystemExit("sitemap.xml is missing </urlset>")
    sitemap = sitemap.replace("</urlset>", SITEMAP_ENTRY + "\n</urlset>", 1)
    if not sitemap.endswith("\n"):
        sitemap += "\n"
    write_if_changed(SITEMAP, sitemap, changed)
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
            raise SystemExit(f"Missing concept asset: {asset.relative_to(ROOT)}")

    checks = [
        (article, 'href="./"', "Home navigation"),
        (article, 'href="tutorials.html" aria-current="page"', "active Tutorials tab"),
        (article, 'href="videos.html"', "Videos navigation"),
        (article, 'href="./#faq"', "FAQ navigation"),
        (article, '"@type":"TechArticle"', "TechArticle structured data"),
        (article, ADSENSE_CLIENT, "verified AdSense client"),
        (article, ROOT_HIDE, "RootHide direct download"),
        (article, ROOTLESS, "rootless direct download"),
        (article, "https://nextsolution.cc/debfiles/", "live repository download base"),
        (article, "Build-validated and awaiting physical-device confirmation", "approval warning"),
        (index, RECENT_START, "homepage pinned card"),
        (index, 'data-pinned="true"', "homepage pinned attribute"),
        (tutorials, TUTORIAL_START, "Tutorials card"),
        (sitemap, ARTICLE_URL, "sitemap entry"),
    ]
    for text, needle, label in checks:
        require(text, needle, label)

    if article.count("pagead2.googlesyndication.com/pagead/js/adsbygoogle.js") != 1:
        raise SystemExit("AdSense loader must occur exactly once")
    if any(value in article for value in ("zeshan0727.github.io", "raw.githubusercontent.com/zeshan0727/zeshan0727.github.io")):
        raise SystemExit("Retired repository dependency found")
    if index.count(RECENT_START) != 1 or index.count(RECENT_END) != 1:
        raise SystemExit("Homepage card markers are missing or duplicated")
    if tutorials.count(TUTORIAL_START) != 1 or tutorials.count(TUTORIAL_END) != 1:
        raise SystemExit("Tutorial card markers are missing or duplicated")
    if sitemap.count(ARTICLE_URL) != 1:
        raise SystemExit("Sitemap entry is missing or duplicated")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    changed: list[Path] = []
    if not args.check:
        changed = normalize()
    validate()
    if changed:
        print("Prepared files:")
        for path in changed:
            print(f"- {path.relative_to(ROOT)}")
    else:
        print("Low Power Mode Haptic tutorial publication is already valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
