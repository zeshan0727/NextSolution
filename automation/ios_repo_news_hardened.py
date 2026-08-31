#!/usr/bin/env python3
"""Safety wrapper for the twice-daily original-source news publisher."""

from __future__ import annotations

from urllib.parse import urlparse
from typing import Any

from automation import ios_repo_news as base


BLOCKED_HINT_HOSTS = {
    "twitter.com", "www.twitter.com", "x.com", "www.x.com",
    "t.me", "telegram.me", "discord.com", "discord.gg",
    "facebook.com", "www.facebook.com", "instagram.com", "www.instagram.com",
    "youtube.com", "www.youtube.com", "yourepo.com", "www.yourepo.com",
}

_original_hint_links = base._candidate_hint_links
_original_resolve = base.resolve_original_source


def _candidate_hint_links(candidate: base.Candidate) -> list[str]:
    links = _original_hint_links(candidate)
    safe: list[str] = []
    for url in links:
        host = urlparse(url).netloc.lower()
        if host in BLOCKED_HINT_HOSTS:
            continue
        safe.append(url)
    return safe


def resolve_original_source(candidate: base.Candidate, config: dict[str, Any]) -> dict[str, Any]:
    source = _original_resolve(candidate, config)
    source_urls = [
        url for url in source.get("source_urls", [])
        if urlparse(str(url)).netloc.lower() not in BLOCKED_HINT_HOSTS
        and urlparse(str(url)).netloc.lower() not in base.DISCOVERY_HOSTS
    ]
    if not source_urls:
        raise ValueError("no trustworthy original developer/repository source survived source validation")

    evidence = str(source.get("source_text", "")).lower()
    package_id = candidate.package_id.lower()
    package_name = str(source.get("name", "")).strip().lower()
    version = str(source.get("version", "")).strip().lower()

    identity_confirmed = package_id in evidence
    if not identity_confirmed and package_name and package_name != package_id:
        identity_confirmed = package_name in evidence
    if not identity_confirmed:
        raise ValueError("resolved source does not independently identify the discovered package")
    if version and version not in evidence:
        raise ValueError("resolved original source does not confirm the package version")

    source["source_urls"] = source_urls
    return source


base._candidate_hint_links = _candidate_hint_links
base.resolve_original_source = resolve_original_source


def main() -> int:
    return base.main()


if __name__ == "__main__":
    raise SystemExit(main())
