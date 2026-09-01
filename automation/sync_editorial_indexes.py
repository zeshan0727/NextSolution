#!/usr/bin/env python3
from __future__ import annotations

import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "automation" / "published-articles.json"
HOME = ROOT / "index.html"
TUTORIALS = [ROOT / "tutorials.html", ROOT / "tutorials" / "index.html"]
HOME_START = "<!-- AUTO_ARTICLES_HOME_START -->"
HOME_END = "<!-- AUTO_ARTICLES_HOME_END -->"
TWEAK_START = "<!-- AUTO_ARTICLES_TUTORIALS_START -->"
TWEAK_END = "<!-- AUTO_ARTICLES_TUTORIALS_END -->"
JAIL_START = "<!-- AUTO_ARTICLES_JAILBREAK_START -->"
JAIL_END = "<!-- AUTO_ARTICLES_JAILBREAK_END -->"


def ordered(entries):
    return sorted(
        [e for e in entries if isinstance(e, dict) and e.get("href")],
        key=lambda e: str(e.get("modified_at") or e.get("published_at") or ""),
        reverse=True,
    )


def is_jailbreak(e):
    c = e.get("category") or {}
    return isinstance(c, dict) and (
        str(c.get("id") or "").lower() == "jailbreak"
        or str(c.get("label") or "").lower() == "jailbreak"
    )


def href(v):
    value = str(v or "").strip()
    if value.startswith(("/", "http://", "https://", "#")):
        return value
    return "/" + value.lstrip("/")


def image(v):
    value = str(v or "").strip()
    if not value:
        return "/assets/brand/next-jailbreak-social-card.png"
    if value.startswith(("/", "http://", "https://")):
        return value
    return "/" + value.lstrip("/")


def card(e, indent="          "):
    esc = lambda v: html.escape(str(v or ""), quote=True)
    c = e.get("category") or {}
    label = c.get("label") if isinstance(c, dict) else "Tweak"
    title = e.get("title") or e.get("name") or "Next Jailbreak article"
    description = e.get("description") or "Read the full article for verified details, compatibility notes and source information."
    source = e.get("source_name") or "Next Jailbreak"
    return "\n".join([
        f'{indent}<article class="content-card has-visual">',
        f'{indent}  <div class="card-meta"><span class="tag">{esc(label or "Tweak")}</span><span class="tag">{esc(source)}</span></div>',
        f'{indent}  <a class="card-media" href="{esc(href(e.get("href")))}" aria-label="Open {esc(title)}"><img src="{esc(image(e.get("image")))}" alt="{esc(title)}" width="1600" height="900" loading="lazy"></a>',
        f'{indent}  <h3>{esc(title)}</h3>',
        f'{indent}  <p>{esc(description)}</p>',
        f'{indent}  <a class="card-link" href="{esc(href(e.get("href")))}">Read article →</a>',
        f'{indent}</article>',
    ])


def replace(text, start, end, body):
    if text.count(start) != 1 or text.count(end) != 1:
        raise RuntimeError(f"expected exactly one marker pair: {start} / {end}")
    before, tail = text.split(start, 1)
    _, after = tail.split(end, 1)
    return before + start + "\n" + body.rstrip() + "\n          " + end + after


def main():
    data = json.loads(AUDIT.read_text(encoding="utf-8"))
    entries = ordered(data.get("entries") or [])
    if not entries:
        raise RuntimeError("published article manifest is empty")

    home_text = HOME.read_text(encoding="utf-8")
    home_text = replace(home_text, HOME_START, HOME_END, "\n".join(card(e) for e in entries[:5]))
    HOME.write_text(home_text, encoding="utf-8")

    tweaks = [e for e in entries if not is_jailbreak(e)]
    jailbreaks = [e for e in entries if is_jailbreak(e)]
    for path in TUTORIALS:
        text = path.read_text(encoding="utf-8")
        text = replace(text, TWEAK_START, TWEAK_END, "\n".join(card(e) for e in tweaks[:60]))
        if JAIL_START in text and JAIL_END in text:
            text = replace(text, JAIL_START, JAIL_END, "\n".join(card(e) for e in jailbreaks[:60]))
        path.write_text(text, encoding="utf-8")

    print(f"Synchronized {len(entries)} published entries")


if __name__ == "__main__":
    main()
