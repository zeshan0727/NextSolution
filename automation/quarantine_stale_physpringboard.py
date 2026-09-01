#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SLUG = "physpringboard-1-9-14-update"
HREF = f"{SLUG}/"
URL = f"https://nextjailbreak.com/{HREF}"


def main():
    audit_path = ROOT / "automation" / "published-articles.json"
    data = json.loads(audit_path.read_text(encoding="utf-8"))
    entries = data.get("entries") or []
    data["entries"] = [e for e in entries if str(e.get("href") or "").strip("/") != SLUG]
    audit_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    feed = ROOT / "feed.xml"
    text = feed.read_text(encoding="utf-8")
    text = re.sub(r"\s*<item>.*?<link>" + re.escape(URL) + r"</link>.*?</item>\s*", "\n", text, flags=re.S)
    feed.write_text(text, encoding="utf-8")

    sitemap = ROOT / "sitemap.xml"
    text = sitemap.read_text(encoding="utf-8")
    text = re.sub(r"\s*<url>\s*<loc>" + re.escape(URL) + r"</loc>.*?</url>\s*", "\n", text, flags=re.S)
    sitemap.write_text(text, encoding="utf-8")

    page = ROOT / SLUG / "index.html"
    if page.exists():
        text = page.read_text(encoding="utf-8")
        text = re.sub(r'<meta\s+name=["\']robots["\'][^>]*>', '<meta name="robots" content="noindex,nofollow">', text, count=1, flags=re.I)
        text = re.sub(r'\s*<meta\s+name=["\']google-adsense-account["\'][^>]*>\s*', '\n', text, flags=re.I)
        text = re.sub(r'\s*<script\s+async\s+src=["\']https://pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js\?client=[^"\']+["\'][^>]*>\s*</script>\s*', '\n', text, flags=re.I)
        page.write_text(text, encoding="utf-8")

    print("Quarantined stale Physpringboard 1.9.14 publication")


if __name__ == "__main__":
    main()
