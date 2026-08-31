#!/usr/bin/env python3
"""Fail-closed editorial quality gate for automated Next Jailbreak articles.

The AI writer and verifier are useful, but publication must also satisfy a
separate deterministic standard aimed at preventing thin, repetitive,
metadata-only, or malformed pages from reaching the live site.
"""

from __future__ import annotations

import argparse
from difflib import SequenceMatcher
import json
from pathlib import Path
import re
from typing import Any


WORD_RE = re.compile(r"\b[\w’'-]+\b", re.UNICODE)
METADATA_PHRASES = (
    "supplied package facts",
    "review the supplied",
    "review the listed",
    "listed architectures",
    "listed dependencies",
    "package overview",
    "supplied release facts",
)
MALFORMED_MARKERS = ("##?", "{{", "}}", "\ufffd")


class QualityGateError(RuntimeError):
    """Raised when a draft fails the independent deterministic quality gate."""


def word_count(value: Any) -> int:
    return len(WORD_RE.findall(str(value or "")))


def _list_text(article: dict[str, Any], key: str) -> list[str]:
    value = article.get(key)
    if not isinstance(value, list):
        return []
    return [str(item).strip() for item in value if str(item).strip()]


def _faq_answers(article: dict[str, Any]) -> list[str]:
    faq = article.get("faq")
    if not isinstance(faq, list):
        return []
    answers: list[str] = []
    for item in faq:
        if isinstance(item, dict) and str(item.get("answer", "")).strip():
            answers.append(str(item["answer"]).strip())
    return answers


def _normalized(value: str) -> str:
    return " ".join(re.sub(r"[^a-z0-9 ]+", " ", value.lower()).split())


def _similar_pairs(items: list[str], threshold: float = 0.84) -> int:
    normalized = [_normalized(item) for item in items if word_count(item) >= 12]
    pairs = 0
    for index, left in enumerate(normalized):
        for right in normalized[index + 1 :]:
            if SequenceMatcher(None, left, right).ratio() >= threshold:
                pairs += 1
    return pairs


def evaluate_manifest(manifest: dict[str, Any], site: dict[str, Any]) -> dict[str, Any]:
    article = manifest.get("article")
    if not isinstance(article, dict):
        raise QualityGateError("manifest article is missing or invalid")

    quality = site.get("quality")
    if not isinstance(quality, dict):
        raise QualityGateError("site quality policy is missing")
    if int(quality.get("target_score", 0)) < 9:
        raise QualityGateError("site quality target must remain at least 9/10")

    summary = str(article.get("summary", "")).strip()
    features = _list_text(article, "what_it_does")
    compatibility = str(article.get("compatibility_note", "")).strip()
    installation = _list_text(article, "installation_steps")
    safety = _list_text(article, "safety_notes")
    faq_answers = _faq_answers(article)

    section_words = {
        "summary": word_count(summary),
        "features": sum(word_count(item) for item in features),
        "compatibility": word_count(compatibility),
        "installation": sum(word_count(item) for item in installation),
        "safety": sum(word_count(item) for item in safety),
        "faq_answers": sum(word_count(item) for item in faq_answers),
    }
    editorial_words = sum(section_words.values())

    thresholds = {
        "summary": int(quality.get("minimum_summary_words", 45)),
        "features": int(quality.get("minimum_feature_words", 110)),
        "compatibility": int(quality.get("minimum_compatibility_words", 35)),
        "installation": int(quality.get("minimum_installation_words", 100)),
        "safety": int(quality.get("minimum_safety_words", 60)),
        "faq_answers": int(quality.get("minimum_faq_answer_words", 160)),
    }

    issues: list[str] = []
    minimum_total = int(quality.get("minimum_editorial_words", 500))
    if editorial_words < minimum_total:
        issues.append(
            f"editorial body is too thin: {editorial_words} words; minimum is {minimum_total}"
        )
    for section, minimum in thresholds.items():
        actual = section_words[section]
        if actual < minimum:
            issues.append(f"{section} is too thin: {actual} words; minimum is {minimum}")

    all_editorial_items = [summary, compatibility, *features, *installation, *safety, *faq_answers]
    editorial_blob = "\n".join(all_editorial_items)
    lowered = editorial_blob.lower()

    if quality.get("block_metadata_heavy_copy", True):
        metadata_hits = sum(lowered.count(phrase) for phrase in METADATA_PHRASES)
        if metadata_hits >= 2:
            issues.append(
                "article is too metadata/template-heavy; repeated package-fact phrasing was detected"
            )

    if quality.get("block_malformed_copy", True):
        found = [marker for marker in MALFORMED_MARKERS if marker in editorial_blob]
        if found:
            issues.append("malformed template markers detected: " + ", ".join(found))
        for label, value in (
            ("summary", summary),
            ("compatibility", compatibility),
        ):
            if re.search(r"(?:,|:|;)\s*$", value):
                issues.append(f"{label} appears truncated")
        for label, items in (
            ("feature", features),
            ("installation", installation),
            ("safety", safety),
            ("faq answer", faq_answers),
        ):
            if any(re.search(r"(?:,|:|;)\s*$", item) for item in items):
                issues.append(f"at least one {label} item appears truncated")

    repeated_pairs = _similar_pairs(features + installation + safety + faq_answers)
    if repeated_pairs >= 2:
        issues.append(
            f"article contains {repeated_pairs} highly similar editorial blocks; rewrite for original value"
        )

    if quality.get("require_authentic_source_media", True):
        if manifest.get("authentic_source_media_required") is not True:
            issues.append("manifest does not require authentic source media")

    verifier = manifest.get("verifier")
    deterministic = manifest.get("deterministic_quality")
    if not isinstance(verifier, dict) or verifier.get("approved") is not True:
        issues.append("independent verifier has not approved the article")
    if not isinstance(deterministic, dict) or deterministic.get("approved") is not True:
        issues.append("base deterministic quality validation has not approved the article")

    return {
        "approved": not issues,
        "target_score": int(quality.get("target_score", 9)),
        "editorial_words": editorial_words,
        "section_words": section_words,
        "similar_pairs": repeated_pairs,
        "issues": issues,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--site", type=Path, default=Path("automation/site.json"))
    parser.add_argument("--repository-root", type=Path, default=Path("."))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest_path = args.repository_root / args.manifest
    site_path = args.repository_root / args.site
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    site = json.loads(site_path.read_text(encoding="utf-8"))
    report = evaluate_manifest(manifest, site)
    print(json.dumps(report, indent=2, sort_keys=True))
    if not report["approved"]:
        raise QualityGateError("high-value editorial gate rejected the draft: " + "; ".join(report["issues"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
