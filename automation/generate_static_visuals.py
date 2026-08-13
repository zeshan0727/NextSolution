"""Refresh committed concept artwork for the launch editorial pages."""

from __future__ import annotations

from pathlib import Path

from automation.visuals import render_article_visual


PRESETS = (
    (
        {
            "slug": "top-home-screen-tweaks",
            "name": "Top Home Screen Tweaks",
            "version": "2026",
            "category": {"id": "home-screen", "label": "Home Screen"},
            "description": "Eight useful tweaks for layouts, folders, widgets and SpringBoard actions.",
        },
        {"what_it_does": ["Eight useful tweaks for layouts, folders, widgets and SpringBoard actions."]},
    ),
    (
        {
            "slug": "lslyrics-tweak",
            "name": "LSLyrics",
            "version": "2.0",
            "category": {"id": "lock-screen", "label": "Lock Screen"},
            "description": "Music lyrics on the Lock Screen.",
        },
        {"what_it_does": ["Displays music lyrics on the Lock Screen."]},
    ),
    (
        {
            "slug": "phonehub-tweak",
            "name": "Phonehub",
            "version": "1.1.3",
            "category": {"id": "messages-phone", "label": "Messages & Phone"},
            "description": "Caller ID, Auto Redial and Phone app features.",
        },
        {"what_it_does": ["Adds listed Caller ID, Auto Redial and Phone app features."]},
    ),
)


def main() -> None:
    target = Path("assets/articles")
    target.mkdir(parents=True, exist_ok=True)
    for candidate, article in PRESETS:
        path = target / f"{candidate['slug']}-hero.svg"
        path.write_text(render_article_visual(candidate, article), encoding="utf-8")


if __name__ == "__main__":
    main()
