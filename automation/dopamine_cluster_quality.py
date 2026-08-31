#!/usr/bin/env python3
"""Harden the Dopamine/news cluster publisher for 9/10 editorial quality.

This wrapper keeps the stable cluster publisher but adds fail-closed rules:
- at least 900 words of useful prose;
- enough independent sections to avoid thin SEO pages;
- a unique visual acquired from the article's own cited sources;
- no fallback to the shared generic Dopamine hero;
- source visual metadata propagated to cards and the publication audit.
"""

from __future__ import annotations

import html
import json
from pathlib import Path
import re
from typing import Any

from automation import dopamine_cluster as base
from automation.source_visuals import acquire_unique_source_visual


_ORIGINAL_VALIDATE = base.validate_article
_ORIGINAL_RENDER = base.render_article
_ORIGINAL_RENDER_CARDS = base._render_cards
_ORIGINAL_PUBLISH = base.publish_cluster
_MEDIA_BY_TARGET: dict[str, dict[str, str]] = {}
_CURRENT_ROOT = Path(".").resolve()


def _editorial_word_count(article: dict[str, Any]) -> int:
    prose: list[str] = [str(article.get("summary", ""))]
    prose.extend(str(item) for item in article.get("key_takeaways", []))
    for section in article.get("sections", []):
        if isinstance(section, dict):
            prose.extend(str(item) for item in section.get("paragraphs", []))
            prose.extend(str(item) for item in section.get("bullets", []))
    for item in article.get("faq", []):
        if isinstance(item, dict):
            prose.append(str(item.get("answer", "")))
    return len(re.findall(r"[A-Za-z0-9][A-Za-z0-9'’.-]*", " ".join(prose)))


def validate_article(article: dict[str, Any], facts: dict[str, Any]) -> list[str]:
    issues = list(_ORIGINAL_VALIDATE(article, facts))
    words = _editorial_word_count(article)
    if words < 900:
        issues.append(f"article prose is below the 9/10 editorial floor: {words} words; minimum 900")
    sections = article.get("sections", [])
    if not isinstance(sections, list) or len(sections) < 5:
        issues.append("article needs at least five substantive editorial sections")
    serialized = json.dumps(article, ensure_ascii=False).lower()
    weak_phrases = (
        "supplied package facts",
        "listed architectures",
        "listed dependencies",
        "review the supplied",
        "review the listed",
    )
    if sum(serialized.count(phrase) for phrase in weak_phrases) >= 2:
        issues.append("article repeats metadata-template wording instead of adding editorial value")
    return sorted(set(issues))


def render_article(
    article: dict[str, Any],
    topic: dict[str, Any],
    cluster: dict[str, Any],
    site: dict[str, Any],
    state: dict[str, Any],
    now: Any,
) -> str:
    target = str(topic["target_path"])
    slug = Path(target).stem
    sources = [str(value) for value in topic.get("sources", []) if str(value).strip()]
    if not sources:
        raise ValueError("source-grounded visual gate requires at least one cited source")
    media = acquire_unique_source_visual(
        source_urls=sources,
        slug=slug,
        repository_root=_CURRENT_ROOT,
    )
    _MEDIA_BY_TARGET[target] = media

    rendered = _ORIGINAL_RENDER(article, topic, cluster, site, state, now)
    old_image = "assets/articles/dopamine-3-ios-17-6-1-hero.jpg"
    rendered = rendered.replace(old_image, media["image"])
    source_host = html.escape(media["source_host"], quote=True)
    title = html.escape(str(article.get("title", "Dopamine 3 guide")), quote=True)
    rendered = rendered.replace(
        'alt="Next Jailbreak Dopamine 3 jailbreak guide visual based on a real test-device Home Screen"',
        f'alt="Source visual for {title} from {source_host}"',
    )
    rendered = re.sub(
        r"<figcaption>Next Jailbreak Dopamine 3 visual built from the real test-device guide\..*?</figcaption>",
        (
            f"<figcaption>Visual captured from the article’s cited original source at "
            f"{source_host}. Compatibility and release claims remain tied to the verified source links on this page.</figcaption>"
        ),
        rendered,
        count=1,
        flags=re.DOTALL,
    )
    return rendered


def _render_cards(entries: list[dict[str, Any]], *, limit: int, indent: str) -> str:
    patched: list[dict[str, Any]] = []
    for entry in entries:
        copy = dict(entry)
        media = _MEDIA_BY_TARGET.get(str(copy.get("href", "")))
        if media:
            copy["image"] = media["image"]
            copy["media_credit"] = media["credit"]
            copy["media_source_url"] = media["source_url"]
        patched.append(copy)
    return _ORIGINAL_RENDER_CARDS(patched, limit=limit, indent=indent)


def publish_cluster(**kwargs: Any) -> dict[str, Any]:
    global _CURRENT_ROOT
    _CURRENT_ROOT = Path(kwargs["repository_root"]).resolve()
    result = _ORIGINAL_PUBLISH(**kwargs)
    if result.get("published") is True:
        target = str(result.get("target_path", ""))
        media = _MEDIA_BY_TARGET.get(target)
        if not media:
            raise ValueError("published cluster page is missing its source visual record")
        audit_path = _CURRENT_ROOT / "automation/published-articles.json"
        audit = json.loads(audit_path.read_text(encoding="utf-8"))
        for entry in audit.get("entries", []):
            if isinstance(entry, dict) and str(entry.get("href", "")) == target:
                entry["image"] = media["image"]
                entry["media_credit"] = media["credit"]
                entry["media_source_url"] = media["source_url"]
                entry["source_visual_url"] = media["image_url"]
                entry["source_visual_origin"] = media["origin"]
        audit_path.write_text(
            json.dumps(audit, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
    return result


base.validate_article = validate_article
base.render_article = render_article
base._render_cards = _render_cards
base.publish_cluster = publish_cluster


def main() -> int:
    return base.main()


if __name__ == "__main__":
    raise SystemExit(main())
