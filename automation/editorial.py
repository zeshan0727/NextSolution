"""Deterministic candidate selection for the Next Solution editorial queue."""

from __future__ import annotations

from collections import defaultdict
import json
from pathlib import Path
import re
from typing import Any, Iterable
import unicodedata


MODERN_ARCHITECTURES = {"iphoneos-arm64", "iphoneos-arm64e"}
INFRASTRUCTURE_PREFIXES = (
    "apt",
    "base",
    "bash",
    "ca-certificates",
    "coreutils",
    "darwintools",
    "firmware",
    "lib",
    "openssh",
    "python",
    "sed",
    "shell-cmds",
    "system-cmds",
    "xz",
)


class NoCandidateError(RuntimeError):
    """Raised when no pending release passes the editorial gates."""


def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return data


def slugify(value: str, limit: int = 72) -> str:
    normalized = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    slug = re.sub(r"[^a-z0-9]+", "-", normalized.lower()).strip("-")
    slug = re.sub(r"-{2,}", "-", slug)[:limit].rstrip("-")
    if not slug:
        raise ValueError("cannot create a slug from an empty name")
    return slug


def classify_category(candidate: dict[str, Any], config: dict[str, Any]) -> dict[str, str]:
    categories = config.get("categories")
    if not isinstance(categories, list) or not categories:
        raise ValueError("category configuration requires categories[]")
    haystack = " ".join(
        str(candidate.get(key, ""))
        for key in ("name", "package", "description", "section", "tags")
    ).lower()
    scored: list[tuple[int, int, dict[str, Any]]] = []
    for index, category in enumerate(categories):
        keywords = category.get("keywords", [])
        score = sum(1 + haystack.count(str(keyword).lower()) for keyword in keywords if str(keyword).lower() in haystack)
        scored.append((score, -index, category))
    best_score, _, chosen = max(scored, key=lambda item: (item[0], item[1]))
    if best_score == 0:
        chosen = next(
            (category for category in categories if category.get("id") == "system-utilities"),
            categories[-1],
        )
    return {"id": str(chosen["id"]), "label": str(chosen["label"])}


def _candidate_score(candidate: dict[str, Any]) -> int:
    score = 0
    if candidate.get("change_type") == "updated":
        score += 50
    section = str(candidate.get("section", "")).lower()
    if "tweak" in section:
        score += 35
    if MODERN_ARCHITECTURES.intersection(candidate.get("architectures", [])):
        score += 25
    if candidate.get("facts_url") and candidate.get("facts_url") != candidate.get("source_url"):
        score += 12
    score += min(len(str(candidate.get("description", ""))) // 80, 18)
    package = str(candidate.get("package", "")).lower()
    if package.startswith(INFRASTRUCTURE_PREFIXES):
        score -= 120
    if candidate.get("source_id") == "bigboss":
        score -= 10
    return score


def _best_variant(values: list[dict[str, Any]]) -> dict[str, Any]:
    architecture_rank = {"iphoneos-arm64": 0, "iphoneos-arm64e": 1, "iphoneos-arm": 2, "all": 3}
    return sorted(
        values,
        key=lambda item: (
            architecture_rank.get(str(item.get("architecture", "")), 9),
            len(str(item.get("name", ""))),
            str(item.get("source_id", "")),
        ),
    )[0]


def build_candidates(
    pending: Iterable[dict[str, Any]],
    categories: dict[str, Any],
    site: dict[str, Any],
) -> list[dict[str, Any]]:
    excluded_sources = {str(value) for value in site.get("excluded_source_ids", [])}
    groups: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for item in pending:
        if not isinstance(item, dict):
            continue
        if not item.get("publish_eligible") or item.get("blockers"):
            continue
        if item.get("source_tier") != "verified" or item.get("source_id") in excluded_sources:
            continue
        if item.get("drafted_at"):
            continue
        required = ("package", "name", "version", "architecture", "description", "author", "sha256")
        if any(not str(item.get(field, "")).strip() for field in required):
            continue
        groups[(str(item["package"]), str(item["version"]))].append(item)

    candidates: list[dict[str, Any]] = []
    for (_, _), variants in groups.items():
        primary = dict(_best_variant(variants))
        architectures = sorted({str(item["architecture"]) for item in variants})
        source_ids = sorted({str(item["source_id"]) for item in variants})
        primary["architectures"] = architectures
        primary["source_ids"] = source_ids
        primary["release_identities"] = sorted(
            {str(item["release_identity"]) for item in variants}
        )
        primary["variants"] = sorted(
            [
                {
                    "architecture": str(item["architecture"]),
                    "release_identity": str(item["release_identity"]),
                    "sha256": str(item["sha256"]),
                }
                for item in variants
            ],
            key=lambda item: (item["architecture"], item["release_identity"]),
        )
        primary["category"] = classify_category(primary, categories)
        base_slug = slugify(str(primary["name"]))
        if not base_slug.endswith("tweak"):
            base_slug += "-tweak"
        primary["slug"] = base_slug
        primary["score"] = _candidate_score(primary)
        candidates.append(primary)

    candidates.sort(
        key=lambda item: (
            -int(item["score"]),
            str(item.get("detected_at", "")),
            str(item["package"]),
        )
    )
    return candidates


def select_candidate(
    state: dict[str, Any], categories: dict[str, Any], site: dict[str, Any]
) -> dict[str, Any]:
    pending = state.get("pending", {})
    if not isinstance(pending, dict):
        raise ValueError("scanner state pending must be an object")
    candidates = build_candidates(pending.values(), categories, site)
    if not candidates:
        raise NoCandidateError("no eligible editorial candidate is waiting")
    return candidates[0]


def mark_candidate_drafted(
    state: dict[str, Any],
    candidate: dict[str, Any],
    *,
    drafted_at: str,
    draft_target: str,
    candidate_fingerprint: str,
) -> None:
    pending = state.get("pending")
    if not isinstance(pending, dict):
        raise ValueError("scanner state pending must be an object")
    release_identities = candidate.get("release_identities", [])
    if not release_identities:
        raise ValueError("candidate does not contain release identities")
    for release_identity in release_identities:
        queued = pending.get(release_identity)
        if not isinstance(queued, dict):
            raise ValueError(f"pending release disappeared: {release_identity}")
        queued["drafted_at"] = drafted_at
        queued["draft_target"] = draft_target
        queued["candidate_fingerprint"] = candidate_fingerprint
