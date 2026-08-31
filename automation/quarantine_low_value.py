#!/usr/bin/env python3
"""Quarantine legacy low-value auto articles from the active editorial surface.

Older automated pages are not deleted: they receive a persistent quality-hold
noindex directive and are removed from home/tutorial cards, RSS and sitemap.
They can be restored after a source-grounded rewrite. This is intentionally
separate from the legacy-route noindex marker so clean /slug/ copies inherit
the quality hold as well.
"""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
import json
import re
from typing import Any
from xml.etree import ElementTree

from automation.publisher import (
    HOME_END,
    HOME_START,
    TUTORIALS_END,
    TUTORIALS_START,
    _render_cards,
    _render_feed,
    _replace_marker_block,
)


QUALITY_START = "<!-- content-quality-hold:start -->"
QUALITY_END = "<!-- content-quality-hold:end -->"
QUALITY_BLOCK = (
    f"  {QUALITY_START}\n"
    '  <meta name="robots" content="noindex,nofollow,max-image-preview:large">\n'
    '  <meta name="nextjailbreak-content-quality" content="hold-for-editorial-rewrite">\n'
    f"  {QUALITY_END}\n"
)
QUALITY_RE = re.compile(
    rf"\s*{re.escape(QUALITY_START)}.*?{re.escape(QUALITY_END)}\s*",
    re.IGNORECASE | re.DOTALL,
)
WEAK_PHRASES = (
    "supplied package facts",
    "review the supplied package",
    "review the supplied release",
    "listed architectures and dependencies",
    "review the listed architectures",
    "review the listed dependencies",
)
MALFORMED = ("listed##?", "##?", "�")
EXCLUDED = {
    "index.html",
    "404.html",
    "privacy.html",
    "terms.html",
    "tutorials.html",
    "videos.html",
    "about.html",
    "contact.html",
}
SITEMAP_NS = "http://www.sitemaps.org/schemas/sitemap/0.9"


def should_hold(path: Path, text: str) -> list[str]:
    if path.name.lower() in EXCLUDED:
        return []
    lowered = text.lower()
    reasons: list[str] = []
    phrase_hits = [phrase for phrase in WEAK_PHRASES if phrase in lowered]
    if phrase_hits:
        reasons.append("legacy metadata-template copy: " + ", ".join(phrase_hits[:3]))
    malformed = [marker for marker in MALFORMED if marker.lower() in lowered]
    if malformed:
        reasons.append("malformed/truncated template marker: " + ", ".join(malformed))
    return reasons


def mark_hold(text: str) -> str:
    text = QUALITY_RE.sub("\n", text)
    if "</head>" not in text.lower():
        raise ValueError("HTML page is missing </head>")
    return re.sub(r"</head>", QUALITY_BLOCK + "</head>", text, count=1, flags=re.IGNORECASE)


def _entry_matches(entry: dict[str, Any], held_names: set[str], held_slugs: set[str]) -> bool:
    href = str(entry.get("href", "")).strip().lstrip("/")
    href_no_slash = href.rstrip("/")
    return (
        href in held_names
        or href_no_slash in held_names
        or Path(href_no_slash).stem in held_slugs
        or href_no_slash in held_slugs
    )


def _remove_sitemap_urls(text: str, held_names: set[str], held_slugs: set[str]) -> str:
    ElementTree.register_namespace("", SITEMAP_NS)
    root = ElementTree.fromstring(text)
    for node in list(root.findall(f"{{{SITEMAP_NS}}}url")):
        loc = node.find(f"{{{SITEMAP_NS}}}loc")
        value = str(loc.text or "") if loc is not None else ""
        path = value.split("?", 1)[0].rstrip("/").rsplit("/", 1)[-1]
        parent = value.split("?", 1)[0].rstrip("/").rsplit("/", 1)[-1]
        if path in held_names or path in held_slugs or f"{path}.html" in held_names or parent in held_slugs:
            root.remove(node)
    ElementTree.indent(root, space="  ")
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + ElementTree.tostring(root, encoding="unicode") + "\n"


def run(repository_root: Path) -> dict[str, Any]:
    held: dict[str, list[str]] = {}
    for path in sorted(repository_root.glob("*.html")):
        text = path.read_text(encoding="utf-8", errors="replace")
        reasons = should_hold(path, text)
        if reasons:
            path.write_text(mark_hold(text), encoding="utf-8")
            held[path.name] = reasons

    held_names = set(held)
    held_slugs = {Path(name).stem for name in held_names}
    audit_path = repository_root / "automation/published-articles.json"
    audit = json.loads(audit_path.read_text(encoding="utf-8"))
    old_entries = [item for item in audit.get("entries", []) if isinstance(item, dict)]
    active_entries = [item for item in old_entries if not _entry_matches(item, held_names, held_slugs)]
    audit["entries"] = active_entries
    audit["updated_at"] = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    audit_path.write_text(json.dumps(audit, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")

    index_path = repository_root / "index.html"
    tutorials_path = repository_root / "tutorials.html"
    index_text = _replace_marker_block(
        index_path.read_text(encoding="utf-8"), HOME_START, HOME_END,
        _render_cards(active_entries, limit=4, indent="          "),
    )
    tutorials_text = _replace_marker_block(
        tutorials_path.read_text(encoding="utf-8"), TUTORIALS_START, TUTORIALS_END,
        _render_cards(active_entries, limit=30, indent="          "),
    )
    index_path.write_text(index_text, encoding="utf-8")
    tutorials_path.write_text(tutorials_text, encoding="utf-8")

    site = json.loads((repository_root / "automation/site.json").read_text(encoding="utf-8"))
    (repository_root / "feed.xml").write_text(_render_feed(active_entries, site), encoding="utf-8")
    sitemap_path = repository_root / "sitemap.xml"
    sitemap_path.write_text(
        _remove_sitemap_urls(sitemap_path.read_text(encoding="utf-8"), held_names, held_slugs),
        encoding="utf-8",
    )

    report = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "held_count": len(held),
        "removed_from_active_index_count": len(old_entries) - len(active_entries),
        "held_pages": held,
    }
    (repository_root / "automation/content-quality-holds.json").write_text(
        json.dumps(report, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return report


def main() -> int:
    root = Path(".").resolve()
    report = run(root)
    print(json.dumps(report, indent=2, sort_keys=True, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
