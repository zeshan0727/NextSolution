#!/usr/bin/env python3
"""Idempotently prepare and validate the Headphone Disconnect Haptic tutorial.

This script only targets zeshan0727/NextSolution / nextsolution.cc. It inserts the
new tutorial cards before the currently pinned Next Home Lock cards, adds one
sitemap entry, and validates the already-published Sileo package metadata.
"""
from __future__ import annotations
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VERSION = "1.0.0"
PACKAGE_ID = "com.nextsolution.headphonedisconnecthaptic"
ARTICLE_FILE = "headphone-disconnect-haptic-tweak-ios16.html"
ARTICLE_URL = f"https://nextsolution.cc/{ARTICLE_FILE}"
ROOT_HIDE = "HeadphoneDisconnectHaptic_1.0.0_RootHide.deb"
ROOTLESS = "HeadphoneDisconnectHaptic_1.0.0_Rootless.deb"
ADSENSE_CLIENT = "ca-pub-4770123899731214"
ARTICLE = ROOT / ARTICLE_FILE
INDEX = ROOT / "index.html"
TUTORIALS = ROOT / "tutorials.html"
SITEMAP = ROOT / "sitemap.xml"
PACKAGES = ROOT / "Packages"
HERO = ROOT / "assets/headphone-disconnect-haptic/headphone-disconnect-haptic-hero.svg"
FEATURES = ROOT / "assets/headphone-disconnect-haptic/headphone-disconnect-haptic-features.svg"
SETTINGS = ROOT / "assets/headphone-disconnect-haptic/headphone-disconnect-haptic-settings.svg"
RECENT_START = "<!-- HEADPHONE_DISCONNECT_HAPTIC_RECENT_CARD_START -->"
RECENT_END = "<!-- HEADPHONE_DISCONNECT_HAPTIC_RECENT_CARD_END -->"
TUTORIAL_START = "<!-- HEADPHONE_DISCONNECT_HAPTIC_TUTORIAL_CARD_START -->"
TUTORIAL_END = "<!-- HEADPHONE_DISCONNECT_HAPTIC_TUTORIAL_CARD_END -->"

RECENT_BLOCK = f'''{RECENT_START}
        <article class="card">
          <div class="icon"><i class="fas fa-headphones" aria-hidden="true"></i></div>
          <h3>Headphone Disconnect Haptic {VERSION}</h3>
          <p>Feel one warning haptic when wired or Bluetooth personal audio disconnects. Built for RootHide and standard rootless jailbreaks.</p>
          <a class="more" href="{ARTICLE_FILE}">Read guide &amp; download <i class="fas fa-arrow-right" aria-hidden="true"></i></a>
        </article>
        {RECENT_END}'''

TUTORIAL_BLOCK = f'''{TUTORIAL_START}
      <article class="card featured">
        <a class="featured-media" href="{ARTICLE_FILE}" aria-label="Open the Headphone Disconnect Haptic {VERSION} guide">
          <img src="assets/headphone-disconnect-haptic/headphone-disconnect-haptic-hero.svg" alt="Headphone Disconnect Haptic concept showing a headphone route disconnect warning" width="1200" height="630" loading="eager">
        </a>
        <div class="featured-body">
          <div class="icon"><i class="fas fa-headphones" aria-hidden="true"></i></div>
          <h3>Headphone Disconnect Haptic {VERSION}</h3>
          <div class="tags" aria-label="Headphone Disconnect Haptic compatibility">
            <span class="tag">iOS 15+</span><span class="tag">RootHide</span><span class="tag">Rootless</span><span class="tag">Free download</span>
          </div>
          <p>Get one warning haptic when wired or Bluetooth headphones disconnect and iOS falls away from a personal-audio route. Includes one clean enable switch.</p>
          <a href="{ARTICLE_FILE}">Read guide &amp; download</a>
        </div>
      </article>
      {TUTORIAL_END}'''

SITEMAP_ENTRY = f'''  <url>
    <loc>{ARTICLE_URL}</loc>
    <lastmod>2026-08-07</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.9</priority>
  </url>'''


def read(path: Path) -> str:
    if not path.is_file():
        raise SystemExit(f"Missing required file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def write_if_changed(path: Path, new: str, changed: list[Path]) -> None:
    old = read(path)
    if old != new:
        path.write_text(new, encoding="utf-8")
        changed.append(path)


def replace_or_insert(text: str, start: str, end: str, block: str, anchor: str) -> str:
    pat = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
    matches = list(pat.finditer(text))
    if len(matches) > 1:
        raise SystemExit(f"Duplicate marked block: {start}")
    if matches:
        return pat.sub(block, text, count=1)
    if anchor not in text:
        raise SystemExit(f"Missing insertion anchor: {anchor}")
    return text.replace(anchor, block + "\n        " + anchor, 1)


def normalize() -> list[Path]:
    changed: list[Path] = []
    index = replace_or_insert(read(INDEX), RECENT_START, RECENT_END, RECENT_BLOCK, "<!-- NEXT_HOME_LOCK_RECENT_CARD_START -->")
    write_if_changed(INDEX, index, changed)
    tutorials = replace_or_insert(read(TUTORIALS), TUTORIAL_START, TUTORIAL_END, TUTORIAL_BLOCK, "<!-- NEXT_HOME_LOCK_TUTORIAL_CARD_START -->")
    write_if_changed(TUTORIALS, tutorials, changed)
    sitemap = read(SITEMAP)
    if sitemap.count(ARTICLE_URL) == 0:
        if "</urlset>" not in sitemap:
            raise SystemExit("Invalid sitemap: missing </urlset>")
        sitemap = sitemap.replace("</urlset>", SITEMAP_ENTRY + "\n</urlset>", 1)
    elif sitemap.count(ARTICLE_URL) > 1:
        raise SystemExit("Duplicate Headphone Disconnect Haptic sitemap entries")
    write_if_changed(SITEMAP, sitemap, changed)
    return changed


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"Validation failed: {label}")


def validate_packages() -> None:
    text = read(PACKAGES)
    blocks = [b for b in re.split(r"\n\s*\n", text) if f"Package: {PACKAGE_ID}" in b]
    if len(blocks) != 2:
        raise SystemExit(f"Expected exactly two live package stanzas, found {len(blocks)}")
    expected = {
        "iphoneos-arm64e": ROOT_HIDE,
        "iphoneos-arm64": ROOTLESS,
    }
    for arch, filename in expected.items():
        candidates = [b for b in blocks if f"Architecture: {arch}" in b]
        if len(candidates) != 1:
            raise SystemExit(f"Missing or duplicate {arch} stanza")
        block = candidates[0]
        for needle, label in [
            (f"Version: {VERSION}", f"{arch} version"),
            (f"Filename: ./debfiles/{filename}", f"{arch} filename"),
            ("Homepage: https://nextsolution.cc/", f"{arch} homepage"),
            ("Depiction: https://nextsolution.cc/depictions/headphonedisconnecthaptic.html", f"{arch} depiction"),
            ("MD5sum:", f"{arch} MD5"), ("SHA1:", f"{arch} SHA1"), ("SHA256:", f"{arch} SHA256")]:
            require(block, needle, label)


def validate() -> None:
    article = read(ARTICLE); index = read(INDEX); tutorials = read(TUTORIALS); sitemap = read(SITEMAP)
    for asset in (HERO, FEATURES, SETTINGS):
        if not asset.is_file():
            raise SystemExit(f"Missing visual asset: {asset.relative_to(ROOT)}")
    for needle, label in [
        (f"Headphone Disconnect Haptic {VERSION}", "article version"),
        ('href="./"', "Home navigation"),
        ('href="tutorials.html" aria-current="page"', "active Tutorials navigation"),
        ('href="videos.html"', "Videos navigation"),
        ('href="./#faq"', "FAQ navigation"),
        ('"@type":"TechArticle"', "TechArticle structured data"),
        (ADSENSE_CLIENT, "AdSense client"),
        (f"https://nextsolution.cc/debfiles/{ROOT_HIDE}", "RootHide direct link"),
        (f"https://nextsolution.cc/debfiles/{ROOTLESS}", "rootless direct link"),
        ("sileo://source/https://nextsolution.cc/", "Sileo source"),
        ("Concept artwork", "concept-art disclosure")]: require(article, needle, label)
    if article.count("pagead2.googlesyndication.com/pagead/js/adsbygoogle.js") != 1:
        raise SystemExit("AdSense loader must occur exactly once")
    # Auto Ads is the verified site implementation; never invent a slot ID.
    if "data-ad-slot=" in article or "data-ad-client=" in article:
        raise SystemExit("Unexpected invented AdSense unit attributes")
    for text, start, end, label in [
        (index, RECENT_START, RECENT_END, "homepage card"),
        (tutorials, TUTORIAL_START, TUTORIAL_END, "Tutorials card")]:
        if text.count(start) != 1 or text.count(end) != 1:
            raise SystemExit(f"{label} markers missing or duplicated")
    # New card must remain pinned before Next Home Lock.
    if index.index(RECENT_START) > index.index("<!-- NEXT_HOME_LOCK_RECENT_CARD_START -->"):
        raise SystemExit("Homepage card is not pinned first")
    if tutorials.index(TUTORIAL_START) > tutorials.index("<!-- NEXT_HOME_LOCK_TUTORIAL_CARD_START -->"):
        raise SystemExit("Tutorial card is not first among current original-tweak cards")
    if sitemap.count(ARTICLE_URL) != 1:
        raise SystemExit("Sitemap entry missing or duplicated")
    for text in (article, index, tutorials, sitemap):
        if "zeshan0727.github.io" in text:
            raise SystemExit("Prepared tutorial changes reference the retired repository")
    validate_packages()


def main() -> int:
    p = argparse.ArgumentParser(); p.add_argument("--check", action="store_true"); args = p.parse_args()
    changed: list[Path] = []
    if not args.check:
        changed = normalize()
    validate()
    if changed:
        print("Changed files:")
        for path in changed: print(f"- {path.relative_to(ROOT)}")
    else:
        print("Headphone Disconnect Haptic tutorial preparation is current and valid.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
