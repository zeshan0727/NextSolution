#!/usr/bin/env python3
from __future__ import annotations

import html
import json
import re
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


def newest_package_entries(entries):
    """Keep only the newest public index card for each package/article identity."""
    result = []
    seen = set()
    for e in entries:
        package = str(e.get("package") or "").strip().lower()
        name = str(e.get("name") or e.get("title") or "").strip().lower()
        key = ("package", package) if package else ("name", name)
        if key in seen:
            continue
        seen.add(key)
        result.append(e)
    return result


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


def clean_description(value):
    text = " ".join(str(value or "").split()).strip()
    fallback = "Read the full article for verified details, compatibility notes and source information."
    if not text:
        return fallback

    # Generated metadata should never expose an obviously chopped word such as "release-".
    if text.endswith(("-", "–", "—")):
        last_sentence = max(text.rfind(". "), text.rfind("! "), text.rfind("? "))
        if last_sentence >= 0:
            text = text[: last_sentence + 1].strip()
        else:
            text = text.rsplit(" ", 1)[0].rstrip("-–—,;:").strip()
            if text and text[-1] not in ".!?":
                text += "."
    return text or fallback


def normalize_manifest_descriptions(data):
    changed = False
    for e in data.get("entries") or []:
        if not isinstance(e, dict) or "description" not in e:
            continue
        cleaned = clean_description(e.get("description"))
        if cleaned != e.get("description"):
            e["description"] = cleaned
            changed = True
    return changed


def card(e, indent="          "):
    esc = lambda v: html.escape(str(v or ""), quote=True)
    c = e.get("category") or {}
    label = c.get("label") if isinstance(c, dict) else "Tweak"
    title = e.get("title") or e.get("name") or "Next Jailbreak article"
    description = clean_description(e.get("description"))
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


def dedupe_blogposting_jsonld(text):
    """Remove duplicate BlogPosting URLs from homepage Blog JSON-LD."""
    pattern = re.compile(r'(<script\s+type="application/ld\+json">\s*)(\{.*?\})(\s*</script>)', re.S)

    def rewrite(match):
        try:
            payload = json.loads(match.group(2))
        except json.JSONDecodeError:
            return match.group(0)
        if payload.get("@type") != "Blog" or not isinstance(payload.get("blogPost"), list):
            return match.group(0)
        seen = set()
        posts = []
        for post in payload["blogPost"]:
            if not isinstance(post, dict):
                continue
            key = str(post.get("url") or post.get("headline") or "").strip().lower()
            if not key or key in seen:
                continue
            seen.add(key)
            posts.append(post)
        payload["blogPost"] = posts
        rendered = json.dumps(payload, ensure_ascii=False, indent=2)
        rendered = "\n".join("  " + line for line in rendered.splitlines())
        return match.group(1) + rendered.lstrip() + match.group(3)

    return pattern.sub(rewrite, text)


def main():
    data = json.loads(AUDIT.read_text(encoding="utf-8"))
    manifest_changed = normalize_manifest_descriptions(data)
    if manifest_changed:
        AUDIT.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    entries = newest_package_entries(ordered(data.get("entries") or []))
    if not entries:
        raise RuntimeError("published article manifest is empty")

    home_text = HOME.read_text(encoding="utf-8")
    home_text = replace(home_text, HOME_START, HOME_END, "\n".join(card(e) for e in entries[:5]))
    home_text = dedupe_blogposting_jsonld(home_text)
    HOME.write_text(home_text, encoding="utf-8")

    tweaks = [e for e in entries if not is_jailbreak(e)]
    jailbreaks = [e for e in entries if is_jailbreak(e)]
    for path in TUTORIALS:
        text = path.read_text(encoding="utf-8")
        text = replace(text, TWEAK_START, TWEAK_END, "\n".join(card(e) for e in tweaks[:60]))
        if JAIL_START in text and JAIL_END in text:
            text = replace(text, JAIL_START, JAIL_END, "\n".join(card(e) for e in jailbreaks[:60]))
        path.write_text(text, encoding="utf-8")

    print(f"Synchronized {len(entries)} unique published entries")


if __name__ == "__main__":
    main()
