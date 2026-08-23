#!/usr/bin/env python3
"""One-time site/category repair and publisher hardening for Next Solution."""

from __future__ import annotations

import html
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "automation" / "published-articles.json"
HOME = ROOT / "index.html"
TUTORIAL_PAGES = [ROOT / "tutorials.html", ROOT / "tutorials" / "index.html"]
PUBLISHER = ROOT / "automation" / "publisher.py"

HOME_START = "<!-- AUTO_ARTICLES_HOME_START -->"
HOME_END = "<!-- AUTO_ARTICLES_HOME_END -->"
TWEAKS_START = "<!-- AUTO_ARTICLES_TUTORIALS_START -->"
TWEAKS_END = "<!-- AUTO_ARTICLES_TUTORIALS_END -->"
JAILBREAK_START = "<!-- AUTO_ARTICLES_JAILBREAK_START -->"
JAILBREAK_END = "<!-- AUTO_ARTICLES_JAILBREAK_END -->"


def category_id(entry: dict) -> str:
    category = entry.get("category")
    if isinstance(category, dict):
        return str(category.get("id") or "").strip().lower()
    return ""


def is_jailbreak(entry: dict) -> bool:
    category = entry.get("category")
    label = ""
    if isinstance(category, dict):
        label = str(category.get("label") or "").strip().lower()
    return category_id(entry) == "jailbreak" or label == "jailbreak"


def clean_href(value: object) -> str:
    href = str(value or "").strip()
    if href.startswith(("http://", "https://", "/")):
        return href
    if href.endswith(".html"):
        return "/" + href[:-5].strip("/") + "/"
    return "/" + href.lstrip("/")


def clean_image(value: object) -> str:
    image = str(value or "").strip()
    if not image:
        return "/assets/brand/next-solution-hero.svg"
    if image.startswith(("http://", "https://", "/")):
        return image
    return "/" + image.lstrip("/")


def render_card(entry: dict, *, indent: str = "          ") -> str:
    esc = lambda value: html.escape(str(value), quote=True)
    category = entry.get("category")
    label = "Tweak"
    if isinstance(category, dict) and category.get("label"):
        label = str(category["label"])
    href = clean_href(entry.get("href"))
    image = clean_image(entry.get("image"))
    title = str(entry.get("title") or entry.get("name") or "Next Solution article")
    description = str(entry.get("description") or "Read the full Next Solution article for details, compatibility notes, and source information.")
    source_name = str(entry.get("source_name") or "Next Solution")
    return "\n".join(
        (
            f'{indent}<article class="content-card has-visual">',
            f'{indent}  <div class="card-meta"><span class="tag">{esc(label)}</span><span class="tag">{esc(source_name)}</span></div>',
            f'{indent}  <a class="card-media" href="{esc(href)}" aria-label="Open {esc(title)}"><img src="{esc(image)}" alt="{esc(title)}" width="1600" height="900" loading="lazy"></a>',
            f'{indent}  <h3>{esc(title)}</h3>',
            f'{indent}  <p>{esc(description)}</p>',
            f'{indent}  <a class="card-link" href="{esc(href)}">Read article →</a>',
            f"{indent}</article>",
        )
    )


def sorted_entries(entries: list[dict]) -> list[dict]:
    return sorted(
        (entry for entry in entries if isinstance(entry, dict) and entry.get("href")),
        key=lambda entry: str(entry.get("modified_at") or entry.get("published_at") or ""),
        reverse=True,
    )


def render_cards(entries: list[dict], *, mode: str, limit: int) -> str:
    ordered = sorted_entries(entries)
    if mode == "jailbreak":
        ordered = [entry for entry in ordered if is_jailbreak(entry)]
    elif mode == "tweaks":
        ordered = [entry for entry in ordered if not is_jailbreak(entry)]
    elif mode != "all":
        raise ValueError(f"unknown mode: {mode}")
    return "\n".join(render_card(entry) for entry in ordered[:limit])


def replace_marker(text: str, start: str, end: str, body: str) -> str:
    if text.count(start) != 1 or text.count(end) != 1:
        raise RuntimeError(f"expected one marker pair: {start} / {end}")
    before, rest = text.split(start, 1)
    _, after = rest.split(end, 1)
    return before + start + "\n" + body.rstrip() + "\n          " + end + after


def rebuild_home(entries: list[dict]) -> None:
    text = HOME.read_text(encoding="utf-8")
    start = '          <div class="news-feed">'
    end = '          </div>\n\n          <aside class="blog-sidebar"'
    if start not in text or end not in text:
        raise RuntimeError("home news-feed boundaries were not found")
    before, rest = text.split(start, 1)
    _, after = rest.split(end, 1)
    latest = render_cards(entries, mode="all", limit=5)
    replacement = (
        start
        + "\n          "
        + HOME_START
        + "\n"
        + latest
        + "\n          "
        + HOME_END
        + "\n"
        + '          </div>\n\n          <aside class="blog-sidebar"'
    )
    text = before + replacement + after
    text = text.replace('>Cydia Tweaks</a>', '>Tweaks</a>')
    text = text.replace('>Latest tweaks</a>', '>Tweaks</a>')
    HOME.write_text(text, encoding="utf-8")


def rebuild_tutorial_page(path: Path, entries: list[dict]) -> None:
    text = path.read_text(encoding="utf-8")
    text = text.replace('>Cydia Tweaks</a>', '>Tweaks</a>')
    text = text.replace('>Latest tweak information</a>', '>Tweaks &amp; tweak articles</a>')
    text = text.replace('>Jailbreak tutorials</a>', '>Jailbreak news &amp; guides</a>')
    text = text.replace('<h2>Latest tweak guides</h2>', '<h2>Tweaks &amp; tweak articles</h2>')
    text = text.replace('<h2>Jailbreak &amp; package tutorials</h2>', '<h2>Jailbreak news &amp; guides</h2>')

    text = replace_marker(text, TWEAKS_START, TWEAKS_END, render_cards(entries, mode="tweaks", limit=60))

    jailbreak_cards = render_cards(entries, mode="jailbreak", limit=60)
    if JAILBREAK_START in text and JAILBREAK_END in text:
        text = replace_marker(text, JAILBREAK_START, JAILBREAK_END, jailbreak_cards)
    else:
        anchor = '        <div class="content-grid guide-card-grid">'
        if anchor not in text:
            raise RuntimeError(f"jailbreak guide grid not found in {path}")
        block = (
            anchor
            + "\n          "
            + JAILBREAK_START
            + "\n"
            + jailbreak_cards
            + "\n          "
            + JAILBREAK_END
        )
        text = text.replace(anchor, block, 1)

    path.write_text(text, encoding="utf-8")


def patch_publisher() -> None:
    text = PUBLISHER.read_text(encoding="utf-8")

    constants_old = (
        'TUTORIALS_START = "<!-- AUTO_ARTICLES_TUTORIALS_START -->"\n'
        'TUTORIALS_END = "<!-- AUTO_ARTICLES_TUTORIALS_END -->"\n'
    )
    constants_new = constants_old + (
        'JAILBREAK_START = "<!-- AUTO_ARTICLES_JAILBREAK_START -->"\n'
        'JAILBREAK_END = "<!-- AUTO_ARTICLES_JAILBREAK_END -->"\n'
    )
    if "JAILBREAK_START" not in text:
        if constants_old not in text:
            raise RuntimeError("publisher marker constants were not found")
        text = text.replace(constants_old, constants_new, 1)

    function_pattern = re.compile(
        r'def _render_cards\(entries: list\[dict\[str, Any\]\], \*, limit: int, indent: str\) -> str:\n.*?\n\n\ndef _render_feed',
        re.S,
    )
    function_new = '''def _entry_category_id(entry: dict[str, Any]) -> str:\n    category = entry.get("category")\n    if isinstance(category, dict):\n        return str(category.get("id") or "").strip().lower()\n    return ""\n\n\ndef _is_jailbreak_entry(entry: dict[str, Any]) -> bool:\n    category = entry.get("category")\n    label = ""\n    if isinstance(category, dict):\n        label = str(category.get("label") or "").strip().lower()\n    return _entry_category_id(entry) == "jailbreak" or label == "jailbreak"\n\n\ndef _render_cards(\n    entries: list[dict[str, Any]],\n    *,\n    limit: int,\n    indent: str,\n    jailbreak: bool | None = None,\n) -> str:\n    current = [entry for entry in entries if isinstance(entry, dict) and entry.get("href")]\n    if jailbreak is True:\n        current = [entry for entry in current if _is_jailbreak_entry(entry)]\n    elif jailbreak is False:\n        current = [entry for entry in current if not _is_jailbreak_entry(entry)]\n    current = sorted(\n        current,\n        key=lambda item: str(item.get("modified_at") or item.get("published_at") or ""),\n        reverse=True,\n    )[:limit]\n    return "\\n".join(_render_card(entry, indent=indent) for entry in current)\n\n\ndef _render_feed'''
    text, count = function_pattern.subn(function_new, text, count=1)
    if count != 1:
        raise RuntimeError("publisher _render_cards function was not patched")

    old_paths = '''    index_path = repository_root / "index.html"\n    tutorials_path = repository_root / "tutorials.html"\n    sitemap_path = repository_root / "sitemap.xml"\n    for required_path in (index_path, tutorials_path, sitemap_path):\n        if not required_path.exists():\n            raise PublishingError(f"required website file is missing: {required_path.name}")\n    next_index = _replace_marker_block(\n        index_path.read_text(encoding="utf-8"),\n        HOME_START,\n        HOME_END,\n        _render_cards(entries, limit=4, indent="          "),\n    )\n    next_tutorials = _replace_marker_block(\n        tutorials_path.read_text(encoding="utf-8"),\n        TUTORIALS_START,\n        TUTORIALS_END,\n        _render_cards(entries, limit=30, indent="          "),\n    )\n    next_feed = _render_feed(entries, site)\n'''
    new_paths = '''    index_path = repository_root / "index.html"\n    tutorials_paths = [\n        repository_root / "tutorials.html",\n        repository_root / "tutorials" / "index.html",\n    ]\n    sitemap_path = repository_root / "sitemap.xml"\n    for required_path in (index_path, *tutorials_paths, sitemap_path):\n        if not required_path.exists():\n            raise PublishingError(f"required website file is missing: {required_path}")\n    next_index = _replace_marker_block(\n        index_path.read_text(encoding="utf-8"),\n        HOME_START,\n        HOME_END,\n        _render_cards(entries, limit=5, indent="          "),\n    )\n    next_tutorials_pages: dict[Path, str] = {}\n    for tutorials_path in tutorials_paths:\n        next_tutorials = _replace_marker_block(\n            tutorials_path.read_text(encoding="utf-8"),\n            TUTORIALS_START,\n            TUTORIALS_END,\n            _render_cards(entries, limit=60, indent="          ", jailbreak=False),\n        )\n        next_tutorials = _replace_marker_block(\n            next_tutorials,\n            JAILBREAK_START,\n            JAILBREAK_END,\n            _render_cards(entries, limit=60, indent="          ", jailbreak=True),\n        )\n        next_tutorials_pages[tutorials_path] = next_tutorials\n    next_feed = _render_feed(entries, site)\n'''
    if old_paths not in text:
        raise RuntimeError("publisher page update block was not found")
    text = text.replace(old_paths, new_paths, 1)

    old_write = '''    target.write_text(rendered_article, encoding="utf-8")\n    index_path.write_text(next_index, encoding="utf-8")\n    tutorials_path.write_text(next_tutorials, encoding="utf-8")\n    (repository_root / "feed.xml").write_text(next_feed, encoding="utf-8")\n'''
    new_write = '''    target.write_text(rendered_article, encoding="utf-8")\n    index_path.write_text(next_index, encoding="utf-8")\n    for tutorials_path, next_tutorials in next_tutorials_pages.items():\n        tutorials_path.write_text(next_tutorials, encoding="utf-8")\n    (repository_root / "feed.xml").write_text(next_feed, encoding="utf-8")\n'''
    if old_write not in text:
        raise RuntimeError("publisher write block was not found")
    text = text.replace(old_write, new_write, 1)

    PUBLISHER.write_text(text, encoding="utf-8")


def validate(entries: list[dict]) -> None:
    home = HOME.read_text(encoding="utf-8")
    if home.count('<article class="content-card has-visual">') < 5:
        raise RuntimeError("homepage does not contain five visual latest cards")
    home_block = home.split(HOME_START, 1)[1].split(HOME_END, 1)[0]
    if home_block.count("<article ") != min(5, len(sorted_entries(entries))):
        raise RuntimeError("homepage latest block does not contain exactly the latest five entries")
    for path in TUTORIAL_PAGES:
        text = path.read_text(encoding="utf-8")
        tweak_block = text.split(TWEAKS_START, 1)[1].split(TWEAKS_END, 1)[0]
        jailbreak_block = text.split(JAILBREAK_START, 1)[1].split(JAILBREAK_END, 1)[0]
        if '<span class="tag">Jailbreak</span>' in tweak_block:
            raise RuntimeError(f"jailbreak article leaked into tweak section: {path}")
        expected_jailbreak = sum(1 for entry in entries if isinstance(entry, dict) and entry.get("href") and is_jailbreak(entry))
        if jailbreak_block.count("<article ") != min(60, expected_jailbreak):
            raise RuntimeError(f"jailbreak section count mismatch: {path}")
        if "AUTO_ARTICLES_JAILBREAK_START" not in text:
            raise RuntimeError(f"jailbreak automation marker missing: {path}")
    publisher = PUBLISHER.read_text(encoding="utf-8")
    for required in ("JAILBREAK_START", "jailbreak=False", "jailbreak=True", "limit=5", 'repository_root / "tutorials" / "index.html"'):
        if required not in publisher:
            raise RuntimeError(f"publisher fix missing: {required}")


def main() -> int:
    data = json.loads(AUDIT.read_text(encoding="utf-8"))
    entries = data.get("entries")
    if not isinstance(entries, list):
        raise RuntimeError("published-articles.json entries must be a list")
    rebuild_home(entries)
    for page in TUTORIAL_PAGES:
        rebuild_tutorial_page(page, entries)
    patch_publisher()
    validate(entries)
    print(
        json.dumps(
            {
                "latest_home": min(5, len(sorted_entries(entries))),
                "tweaks": sum(1 for entry in entries if isinstance(entry, dict) and entry.get("href") and not is_jailbreak(entry)),
                "jailbreak": sum(1 for entry in entries if isinstance(entry, dict) and entry.get("href") and is_jailbreak(entry)),
                "status": "ok",
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
