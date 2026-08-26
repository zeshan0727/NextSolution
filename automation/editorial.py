"""Deterministic candidate selection for the Next Jailbreak editorial queue."""

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
    """Raised when no release in either editorial pool passes the gates."""


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


def _base_candidate_score(candidate: dict[str, Any]) -> int:
    """Score factual release quality before audience-interest weighting."""
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


def _normalized_priority_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    normalized = re.sub(r"[^a-z0-9]+", " ", normalized.lower())
    return re.sub(r"\s+", " ", normalized).strip()


def _contains_priority_term(haystack: str, term: str) -> bool:
    needle = _normalized_priority_text(term)
    if not needle:
        return False
    return f" {needle} " in f" {haystack} "


def _priority_weights(value: Any, *, field: str) -> dict[str, int]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ValueError(f"traffic_ranking.{field} must be an object")
    result: dict[str, int] = {}
    for keyword, weight in value.items():
        if not isinstance(keyword, str) or not keyword.strip():
            raise ValueError(f"traffic_ranking.{field} contains an invalid keyword")
        if not isinstance(weight, int) or weight < 0:
            raise ValueError(f"traffic_ranking.{field}.{keyword} must be a non-negative integer")
        result[keyword] = weight
    return result


def _audience_priority_score(candidate: dict[str, Any], site: dict[str, Any]) -> int:
    """Apply transparent editorial priorities without claiming search-volume data."""
    config = site.get("traffic_ranking", {})
    if not isinstance(config, dict):
        raise ValueError("site traffic_ranking must be an object")
    if config.get("enabled") is not True:
        return 0

    max_bonus = config.get("max_bonus", 80)
    max_penalty = config.get("max_penalty", 40)
    if not isinstance(max_bonus, int) or max_bonus < 0:
        raise ValueError("traffic_ranking.max_bonus must be a non-negative integer")
    if not isinstance(max_penalty, int) or max_penalty < 0:
        raise ValueError("traffic_ranking.max_penalty must be a non-negative integer")

    boosts = _priority_weights(config.get("boost_keywords"), field="boost_keywords")
    penalties = _priority_weights(
        config.get("deprioritize_keywords"), field="deprioritize_keywords"
    )
    haystack = _normalized_priority_text(
        " ".join(
            str(candidate.get(key, ""))
            for key in ("name", "package", "description", "section", "tags")
        )
    )
    bonus = sum(
        weight for keyword, weight in boosts.items() if _contains_priority_term(haystack, keyword)
    )
    penalty = sum(
        weight for keyword, weight in penalties.items() if _contains_priority_term(haystack, keyword)
    )
    return min(bonus, max_bonus) - min(penalty, max_penalty)


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
    *,
    selection_pool: str = "pending",
) -> list[dict[str, Any]]:
    if selection_pool not in {"pending", "evergreen"}:
        raise ValueError(f"unsupported editorial pool: {selection_pool}")
    excluded_sources = {str(value) for value in site.get("excluded_source_ids", [])}
    groups: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for item in pending:
        if not isinstance(item, dict):
            continue
        if not item.get("publish_eligible") or item.get("blockers"):
            continue
        if item.get("source_tier") != "verified" or item.get("source_id") in excluded_sources:
            continue
        if item.get("drafted_at") or item.get("draft_rejected_at"):
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
        primary["selection_pool"] = selection_pool
        try:
            base_slug = slugify(str(primary["name"]))
        except ValueError:
            # A package whose display name contains no ASCII letters or digits
            # cannot produce a stable website path without transliteration.
            # Skip that one catalog entry rather than stopping the entire run.
            continue
        if not base_slug.endswith("tweak"):
            base_slug += "-tweak"
        primary["slug"] = base_slug
        primary["base_score"] = _base_candidate_score(primary)
        primary["audience_score"] = _audience_priority_score(primary, site)
        primary["score"] = int(primary["base_score"]) + int(primary["audience_score"])
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
    state: dict[str, Any],
    categories: dict[str, Any],
    site: dict[str, Any],
    *,
    excluded_packages: set[str] | None = None,
) -> dict[str, Any]:
    pending = state.get("pending", {})
    if not isinstance(pending, dict):
        raise ValueError("scanner state pending must be an object")
    candidates = build_candidates(
        pending.values(), categories, site, selection_pool="pending"
    )
    if excluded_packages:
        candidates = [
            candidate
            for candidate in candidates
            if str(candidate.get("package", "")) not in excluded_packages
        ]
    if candidates:
        return candidates[0]
    evergreen = state.get("evergreen", {})
    if not isinstance(evergreen, dict):
        raise ValueError("scanner state evergreen must be an object")
    candidates = build_candidates(
        evergreen.values(), categories, site, selection_pool="evergreen"
    )
    if excluded_packages:
        candidates = [
            candidate
            for candidate in candidates
            if str(candidate.get("package", "")) not in excluded_packages
        ]
    if candidates:
        return candidates[0]
    if excluded_packages:
        raise NoCandidateError(
            "no unpublished eligible release or evergreen tweak is waiting"
        )
    raise NoCandidateError("no eligible undrafted release or evergreen tweak is waiting")


def mark_candidate_drafted(
    state: dict[str, Any],
    candidate: dict[str, Any],
    *,
    drafted_at: str,
    draft_target: str,
    candidate_fingerprint: str,
) -> None:
    release_identities = candidate.get("release_identities", [])
    if not release_identities:
        raise ValueError("candidate does not contain release identities")
    package = str(candidate.get("package", ""))
    version = str(candidate.get("version", ""))
    marked = 0
    for pool_name in ("pending", "evergreen"):
        pool = state.get(pool_name, {})
        if not isinstance(pool, dict):
            raise ValueError(f"scanner state {pool_name} must be an object")
        for queued in pool.values():
            if not isinstance(queued, dict):
                continue
            if str(queued.get("package", "")) != package or str(
                queued.get("version", "")
            ) != version:
                continue
            queued["drafted_at"] = drafted_at
            queued["draft_target"] = draft_target
            queued["candidate_fingerprint"] = candidate_fingerprint
            marked += 1
    if marked == 0:
        raise ValueError("selected release disappeared from editorial state")


def mark_candidate_rejected(
    state: dict[str, Any],
    candidate: dict[str, Any],
    *,
    rejected_at: str,
    reason: str,
    candidate_fingerprint: str,
) -> None:
    """Quarantine one exact package version after bounded verification fails."""
    release_identities = candidate.get("release_identities", [])
    if not release_identities:
        raise ValueError("candidate does not contain release identities")
    package = str(candidate.get("package", ""))
    version = str(candidate.get("version", ""))
    marked = 0
    for pool_name in ("pending", "evergreen"):
        pool = state.get(pool_name, {})
        if not isinstance(pool, dict):
            raise ValueError(f"scanner state {pool_name} must be an object")
        for queued in pool.values():
            if not isinstance(queued, dict):
                continue
            if str(queued.get("package", "")) != package or str(
                queued.get("version", "")
            ) != version:
                continue
            queued["draft_rejected_at"] = rejected_at
            queued["draft_rejection_reason"] = reason[:1000]
            queued["draft_rejection_fingerprint"] = candidate_fingerprint
            marked += 1
    if marked == 0:
        raise ValueError("rejected release disappeared from editorial state")
