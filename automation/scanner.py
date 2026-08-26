#!/usr/bin/env python3
"""Read-only APT feed scanner for Next Jailbreak editorial automation."""

from __future__ import annotations

import argparse
import bz2
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timezone
import gzip
import ipaddress
import io
import json
import lzma
from pathlib import Path
import re
import socket
import sys
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

from automation.debian import compare_versions, newest, parse_control


DEFAULT_FEED_PATHS = ["Packages.xz", "Packages.gz", "Packages.bz2", "Packages"]
ALLOWED_TIERS = {"verified", "observe", "excluded"}
MAX_COMPRESSED_BYTES = 24 * 1024 * 1024
MAX_EXPANDED_BYTES = 64 * 1024 * 1024
USER_AGENT = "NextSolutionFeedScanner/0.1 (+https://nextsolution.cc/)"
RISK_PATTERNS = {
    "piracy_language": re.compile(r"\b(crack(?:ed)?|pirated?|warez)\b", re.I),
    "game_cheat_language": re.compile(
        r"\b(aimbot|wallhack|mod[ -]?menu|game[ -]?cheat|unlimited[ -]?(?:coins|gems))\b",
        re.I,
    ),
    "purchase_bypass_language": re.compile(
        r"\b(free[ -]?in[ -]?app[ -]?purchase|iap[ -]?bypass|license[ -]?bypass)\b",
        re.I,
    ),
}


@dataclass
class SourceScan:
    source: dict[str, Any]
    feed_url: str | None
    packages: list[dict[str, Any]]
    error: str | None
    attempts: list[str]


class SafeRedirectHandler(HTTPRedirectHandler):
    def __init__(self, allowed_hosts: set[str]) -> None:
        super().__init__()
        self.allowed_hosts = allowed_hosts

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        _validate_remote_url(newurl, self.allowed_hosts)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _is_public_hostname(hostname: str) -> bool:
    lowered = hostname.lower().rstrip(".")
    if lowered in {"localhost", "localhost.localdomain"} or lowered.endswith(".local"):
        return False
    try:
        address = ipaddress.ip_address(lowered)
    except ValueError:
        return True
    return not (
        address.is_private
        or address.is_loopback
        or address.is_link_local
        or address.is_multicast
        or address.is_reserved
        or address.is_unspecified
    )


def _validate_remote_url(url: str, allowed_hosts: set[str]) -> None:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        raise ValueError("only HTTP(S) feed URLs are allowed")
    if parsed.username or parsed.password:
        raise ValueError("credentials are not allowed in feed URLs")
    hostname = (parsed.hostname or "").lower()
    if not hostname or not _is_public_hostname(hostname):
        raise ValueError("feed URL must use a public hostname")
    if hostname not in allowed_hosts:
        raise ValueError(f"redirected to unapproved host {hostname}")


def _read_limited(response, limit: int) -> bytes:  # type: ignore[no-untyped-def]
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = response.read(min(64 * 1024, limit + 1 - total))
        if not chunk:
            break
        total += len(chunk)
        if total > limit:
            raise ValueError(f"response exceeds {limit} bytes")
        chunks.append(chunk)
    return b"".join(chunks)


def _expand_limited(payload: bytes, feed_url: str) -> bytes:
    if feed_url.endswith(".gz"):
        reader = gzip.GzipFile(fileobj=io.BytesIO(payload))
    elif feed_url.endswith(".bz2"):
        reader = bz2.BZ2File(io.BytesIO(payload))
    elif feed_url.endswith(".xz"):
        reader = lzma.LZMAFile(io.BytesIO(payload))
    else:
        if len(payload) > MAX_EXPANDED_BYTES:
            raise ValueError("uncompressed Packages index is too large")
        return payload
    try:
        expanded = reader.read(MAX_EXPANDED_BYTES + 1)
    finally:
        reader.close()
    if len(expanded) > MAX_EXPANDED_BYTES:
        raise ValueError("expanded Packages index is too large")
    return expanded


def _fetch(url: str, source: dict[str, Any], timeout: float) -> bytes:
    base_host = (urlparse(str(source["url"])).hostname or "").lower()
    allowed_hosts = {base_host}
    allowed_hosts.update(str(value).lower() for value in source.get("redirect_hosts", []))
    _validate_remote_url(url, allowed_hosts)
    opener = build_opener(SafeRedirectHandler(allowed_hosts))
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
    with opener.open(request, timeout=timeout) as response:
        return _read_limited(response, MAX_COMPRESSED_BYTES)


def _clean_text(value: str, limit: int = 1400) -> str:
    return re.sub(r"\s+", " ", value).strip()[:limit]


def normalize_package(fields: dict[str, str], source: dict[str, Any]) -> dict[str, Any] | None:
    package = fields.get("package", "").strip().lower()
    version = fields.get("version", "").strip()
    architecture = fields.get("architecture", "").strip().lower()
    if not package or not version or not architecture:
        return None
    if not re.fullmatch(r"[a-z0-9][a-z0-9+.-]{1,254}", package):
        return None
    if not re.fullmatch(r"[0-9][A-Za-z0-9.+:~_-]{0,127}", version):
        return None
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", architecture):
        return None

    description = _clean_text(fields.get("description", ""))
    name = _clean_text(fields.get("name", ""), 180) or package
    author = _clean_text(fields.get("author", "") or fields.get("maintainer", ""), 240)
    sha256 = fields.get("sha256", "").strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", sha256):
        sha256 = ""

    source_url = str(source["url"])
    depiction = fields.get("sileodepiction", "") or fields.get("depiction", "")
    homepage = fields.get("homepage", "")
    facts_url = next(
        (
            value.strip()
            for value in (depiction, homepage, source_url)
            if value.strip().startswith(("https://", "http://"))
        ),
        source_url,
    )

    blockers: list[str] = []
    if source["tier"] != "verified":
        blockers.append("source_requires_review")
    if not sha256:
        blockers.append("missing_sha256")
    if not author:
        blockers.append("missing_author")
    if len(description) < 24:
        blockers.append("description_too_short")
    risk_text = " ".join((package, name, description, fields.get("section", "")))
    for label, pattern in RISK_PATTERNS.items():
        if pattern.search(risk_text):
            blockers.append(label)

    return {
        "identity": f"{package}|{architecture}",
        "release_identity": f"{package}|{version}|{architecture}",
        "package": package,
        "name": name,
        "version": version,
        "architecture": architecture,
        "description": description,
        "author": author,
        "section": _clean_text(fields.get("section", ""), 120),
        "depends": _clean_text(fields.get("depends", ""), 600),
        "tags": _clean_text(fields.get("tag", ""), 600),
        "sha256": sha256,
        "filename": _clean_text(fields.get("filename", ""), 600),
        "facts_url": facts_url,
        "source_id": source["id"],
        "source_name": source["name"],
        "source_url": source_url,
        "source_tier": source["tier"],
        "blockers": sorted(set(blockers)),
    }


def scan_source(source: dict[str, Any], timeout: float) -> SourceScan:
    attempts: list[str] = []
    base_url = str(source["url"])
    feed_paths = source.get("feed_paths") or DEFAULT_FEED_PATHS
    last_error = "no Packages index candidates configured"
    for relative_path in feed_paths:
        feed_url = urljoin(base_url if base_url.endswith("/") else base_url + "/", relative_path)
        try:
            payload = _fetch(feed_url, source, timeout)
            text = _expand_limited(payload, feed_url).decode("utf-8", errors="replace")
            parsed = parse_control(text)
            normalized = [normalize_package(record, source) for record in parsed]
            packages = [record for record in normalized if record is not None]
            if not packages:
                raise ValueError("response did not contain valid package records")
            return SourceScan(source, feed_url, packages, None, attempts)
        except (
            EOFError,
            HTTPError,
            URLError,
            TimeoutError,
            socket.timeout,
            OSError,
            ValueError,
        ) as exc:
            reason = f"{type(exc).__name__}: {str(exc)[:180]}"
            attempts.append(f"{feed_url} — {reason}")
            last_error = reason
    return SourceScan(source, None, [], last_error, attempts)


def load_registry(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1 or not isinstance(data.get("sources"), list):
        raise ValueError("source registry must use schema_version 1 and contain sources[]")
    seen: set[str] = set()
    for index, source in enumerate(data["sources"]):
        if not isinstance(source, dict):
            raise ValueError(f"source #{index + 1} must be an object")
        missing = {"id", "name", "url", "tier"} - set(source)
        if missing:
            raise ValueError(f"source #{index + 1} is missing: {', '.join(sorted(missing))}")
        if not all(isinstance(source[key], str) for key in ("id", "name", "url", "tier")):
            raise ValueError(f"source #{index + 1} has a non-string required field")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{1,63}", source["id"]):
            raise ValueError(f"invalid source id: {source['id']}")
        if source["id"] in seen:
            raise ValueError(f"duplicate source id: {source['id']}")
        if source["tier"] not in ALLOWED_TIERS:
            raise ValueError(f"invalid tier for {source['id']}: {source['tier']}")
        _validate_remote_url(source["url"], {(urlparse(source["url"]).hostname or "").lower()})
        for host in source.get("redirect_hosts", []):
            if not isinstance(host, str) or not _is_public_hostname(host):
                raise ValueError(f"invalid redirect host for {source['id']}: {host}")
        for feed_path in source.get("feed_paths", DEFAULT_FEED_PATHS):
            if not isinstance(feed_path, str):
                raise ValueError(f"invalid feed path for {source['id']}: {feed_path}")
            parsed_path = urlparse(feed_path)
            if (
                parsed_path.scheme
                or parsed_path.netloc
                or feed_path.startswith("/")
                or ".." in parsed_path.path.split("/")
            ):
                raise ValueError(f"invalid feed path for {source['id']}: {feed_path}")
        seen.add(source["id"])
    return data


def load_state(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {
            "schema_version": 1,
            "packages": {},
            "pending": {},
            "evergreen": {},
            "sources": {},
        }
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1 or not isinstance(data.get("packages"), dict):
        raise ValueError("state file must use schema_version 1 and contain packages{}")
    if not isinstance(data.get("sources", {}), dict):
        raise ValueError("state file sources must be an object")
    if not isinstance(data.get("pending", {}), dict):
        raise ValueError("state file pending must be an object")
    if not isinstance(data.get("evergreen", {}), dict):
        raise ValueError("state file evergreen must be an object")
    data.setdefault("sources", {})
    data.setdefault("pending", {})
    data.setdefault("evergreen", {})
    return data


def deduplicate(records: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    tier_rank = {"verified": 0, "observe": 1, "excluded": 2}
    release_groups: dict[str, list[dict[str, Any]]] = {}
    for record in records:
        release_groups.setdefault(record["release_identity"], []).append(record)

    selected: list[dict[str, Any]] = []
    conflicts: list[dict[str, Any]] = []
    for release_identity, values in sorted(release_groups.items()):
        hashes = sorted({value["sha256"] for value in values if value["sha256"]})
        values.sort(key=lambda value: (tier_rank[value["source_tier"]], value["source_id"]))
        chosen = dict(values[0])
        chosen["also_seen_at"] = sorted({value["source_id"] for value in values[1:]})
        if len(hashes) > 1:
            chosen["blockers"] = sorted(set(chosen["blockers"] + ["checksum_conflict"]))
            conflicts.append(
                {
                    "release_identity": release_identity,
                    "sources": sorted({value["source_id"] for value in values}),
                    "sha256_values": hashes,
                }
            )
        selected.append(chosen)
    return selected, conflicts


def latest_releases(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    tier_rank = {"verified": 0, "observe": 1, "excluded": 2}
    identities: dict[str, list[dict[str, Any]]] = {}
    for record in records:
        identities.setdefault(record["identity"], []).append(record)
    selected: list[dict[str, Any]] = []
    for _, values in sorted(identities.items()):
        best_rank = min(tier_rank[str(value["source_tier"])] for value in values)
        best_tier = [
            value
            for value in values
            if tier_rank[str(value["source_tier"])] == best_rank
        ]
        selected.append(dict(newest(best_tier)))
    return selected


def classify_changes(
    latest: list[dict[str, Any]], state: dict[str, Any]
) -> tuple[list[dict[str, Any]], dict[str, dict[str, str]]]:
    previous = state["packages"]
    changes: list[dict[str, Any]] = []
    # Preserve entries from temporarily unavailable feeds. Removing them would
    # make an old release look new when that source recovers.
    next_state: dict[str, dict[str, str]] = {
        identity: dict(value) for identity, value in previous.items()
    }
    for record in latest:
        identity = record["identity"]
        old = previous.get(identity)
        next_state[identity] = {
            "version": record["version"],
            "sha256": record["sha256"],
            "source_id": record["source_id"],
        }
        change_type: str | None = None
        if old is None:
            change_type = "new"
        else:
            comparison = compare_versions(record["version"], str(old.get("version", "")))
            if comparison > 0:
                change_type = "updated"
            elif comparison == 0 and record["sha256"] and old.get("sha256") and record["sha256"] != old["sha256"]:
                change_type = "checksum_changed"
                record["blockers"] = sorted(set(record["blockers"] + ["immutable_version_changed"]))
        if change_type:
            item = dict(record)
            item["change_type"] = change_type
            item["previous_version"] = old.get("version") if old else None
            item["publish_eligible"] = not item["blockers"]
            changes.append(item)
    changes.sort(
        key=lambda item: (
            not item["publish_eligible"],
            0 if item["change_type"] == "updated" else 1,
            item["source_id"],
            item["package"],
        )
    )
    return changes, next_state


def suppress_first_seen_sources(
    changes: list[dict[str, Any]], first_seen_sources: set[str]
) -> tuple[list[dict[str, Any]], int]:
    """Baseline a source on its first successful scan.

    This prevents an existing catalog from becoming a publication queue when a
    source is added, when the workflow runs for the first time, or when a source
    recovers after being unavailable during the initial baseline.
    """

    retained = [item for item in changes if item["source_id"] not in first_seen_sources]
    return retained, len(changes) - len(retained)


def update_pending_queue(
    existing: dict[str, Any],
    latest: list[dict[str, Any]],
    changes: list[dict[str, Any]],
    generated_at: str,
) -> dict[str, dict[str, Any]]:
    """Keep eligible changes queued until a later publisher acknowledges them."""

    pending = {
        key: dict(value)
        for key, value in existing.items()
        if isinstance(key, str) and isinstance(value, dict)
    }
    current_by_identity = {item["identity"]: item for item in latest}

    for release_identity, queued in list(pending.items()):
        identity = queued.get("identity")
        current = current_by_identity.get(identity)
        if current is None:
            # Preserve the queue entry when its source is temporarily absent.
            continue
        comparison = compare_versions(
            str(current.get("version", "")), str(queued.get("version", ""))
        )
        if comparison > 0:
            # A newer release supersedes this entry. The new release is added
            # below only if it passes every safety gate.
            del pending[release_identity]
            continue
        if current.get("release_identity") == release_identity:
            refreshed = dict(current)
            refreshed["change_type"] = queued.get("change_type", "new")
            refreshed["previous_version"] = queued.get("previous_version")
            refreshed["detected_at"] = queued.get("detected_at", generated_at)
            for key in (
                "drafted_at",
                "draft_target",
                "candidate_fingerprint",
                "draft_rejected_at",
                "draft_rejection_reason",
                "draft_rejection_fingerprint",
            ):
                if queued.get(key):
                    refreshed[key] = queued[key]
            refreshed["publish_eligible"] = not refreshed.get("blockers")
            pending[release_identity] = refreshed

    for change in changes:
        if not change.get("publish_eligible"):
            continue
        queued = dict(change)
        queued["detected_at"] = generated_at
        pending[change["release_identity"]] = queued
    return dict(sorted(pending.items()))


def update_evergreen_catalog(
    existing: dict[str, Any],
    latest: list[dict[str, Any]],
    successful_source_ids: set[str],
    generated_at: str,
) -> dict[str, dict[str, Any]]:
    """Persist safe current metadata for non-repeating evergreen drafts.

    Entries from unavailable sources survive until that source recovers. A
    successful source refresh replaces its previous catalog entries, which
    means removed, superseded, or newly blocked releases cannot remain eligible.
    """

    current_identities = {
        str(record.get("identity", "")) for record in latest if record.get("identity")
    }
    catalog = {
        key: dict(value)
        for key, value in existing.items()
        if isinstance(key, str)
        and isinstance(value, dict)
        and str(value.get("source_id", "")) not in successful_source_ids
        and str(value.get("identity", "")) not in current_identities
    }
    required = (
        "identity",
        "release_identity",
        "package",
        "name",
        "version",
        "architecture",
        "description",
        "author",
        "sha256",
        "source_id",
        "source_name",
        "source_url",
    )
    for record in latest:
        if record.get("source_tier") != "verified" or record.get("blockers"):
            continue
        if any(not str(record.get(field, "")).strip() for field in required):
            continue
        release_identity = str(record["release_identity"])
        refreshed = dict(record)
        refreshed["change_type"] = "evergreen"
        refreshed["previous_version"] = None
        refreshed["publish_eligible"] = True
        old = existing.get(release_identity, {})
        refreshed["cataloged_at"] = old.get("cataloged_at", generated_at)
        refreshed["detected_at"] = old.get("detected_at", generated_at)
        for key in (
            "drafted_at",
            "draft_target",
            "candidate_fingerprint",
            "draft_rejected_at",
            "draft_rejection_reason",
            "draft_rejection_fingerprint",
        ):
            if old.get(key):
                refreshed[key] = old[key]
        catalog[release_identity] = refreshed
    return dict(sorted(catalog.items()))


def _markdown(report: dict[str, Any]) -> str:
    stats = report["stats"]
    lines = [
        "# Tweak feed dry-run report",
        "",
        f"Generated: `{report['generated_at']}`",
        "",
        "## Result",
        "",
        f"- Sources attempted: **{stats['sources_attempted']}**",
        f"- Sources successful: **{stats['sources_successful']}**",
        f"- Verified sources successful: **{stats['verified_sources_successful']}**",
        f"- Package records read: **{stats['package_records']}**",
        f"- Unique current packages: **{stats['unique_current_packages']}**",
        f"- Changes detected: **{stats['changes']}**",
        f"- Eligible after safety gates: **{stats['publish_eligible']}**",
        f"- Checksum conflicts: **{stats['checksum_conflicts']}**",
        f"- Historical changes baselined: **{stats['baseline_suppressed']}**",
        f"- Eligible releases waiting in queue: **{stats['pending_eligible']}**",
        f"- Verified evergreen releases available: **{stats['evergreen_eligible']}**",
        "",
        "The scanner never changes website files, package binaries, or links. Scanner state is written only when explicitly enabled.",
        "",
        "## Eligible changes (preview only)",
        "",
    ]
    eligible = [item for item in report["changes"] if item["publish_eligible"]]
    if not eligible:
        lines.append("No change passed every publication gate.")
    else:
        lines.extend(["| Change | Tweak | Version | Architecture | Source |", "|---|---|---:|---|---|"])
        for item in eligible[:30]:
            name = item["name"].replace("|", "\\|")
            lines.append(
                f"| {item['change_type']} | {name} | {item['version']} | "
                f"{item['architecture']} | {item['source_name']} |"
            )
    failed = [source for source in report["sources"] if source["status"] == "error"]
    lines.extend(["", "## Source health", ""])
    if failed:
        lines.append(f"{len(failed)} source(s) failed. See `report.json` for bounded error details.")
    else:
        lines.append("Every attempted source returned a valid Packages index.")
    lines.append("")
    return "\n".join(lines)


def run(args: argparse.Namespace) -> dict[str, Any]:
    registry = load_registry(args.sources)
    state = load_state(args.state)
    tiers = {value.strip() for value in args.tiers.split(",") if value.strip()}
    invalid_tiers = tiers - {"verified", "observe"}
    if invalid_tiers:
        raise ValueError(f"unsupported scan tier(s): {', '.join(sorted(invalid_tiers))}")
    sources = [source for source in registry["sources"] if source["tier"] in tiers]
    if args.only:
        requested = {value.strip() for value in args.only.split(",") if value.strip()}
        known = {source["id"] for source in registry["sources"]}
        missing = requested - known
        if missing:
            raise ValueError(f"unknown source id(s): {', '.join(sorted(missing))}")
        sources = [source for source in sources if source["id"] in requested]
    if not sources:
        raise ValueError("no sources matched the selected tiers and ids")

    results: list[SourceScan] = []
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {executor.submit(scan_source, source, args.timeout): source for source in sources}
        for future in as_completed(futures):
            results.append(future.result())
    results.sort(key=lambda result: result.source["id"])

    records = [package for result in results for package in result.packages]
    unique_releases, conflicts = deduplicate(records)
    latest = latest_releases(unique_releases)
    raw_changes, next_state = classify_changes(latest, state)
    successful_source_ids = {
        result.source["id"] for result in results if result.error is None
    }
    known_source_ids = set(state.get("sources", {}))
    first_seen_sources = (
        successful_source_ids - known_source_ids if args.baseline_new_sources else set()
    )
    changes, baseline_suppressed = suppress_first_seen_sources(
        raw_changes, first_seen_sources
    )
    verified_successes = sum(
        1 for result in results if result.error is None and result.source["tier"] == "verified"
    )
    if verified_successes < args.require_verified:
        raise RuntimeError(
            f"only {verified_successes} verified source(s) succeeded; required {args.require_verified}"
        )

    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    next_pending = update_pending_queue(
        state.get("pending", {}), latest, changes, generated_at
    )
    next_evergreen = update_evergreen_catalog(
        state.get("evergreen", {}), latest, successful_source_ids, generated_at
    )
    next_source_state = {
        source_id: dict(value) for source_id, value in state.get("sources", {}).items()
    }
    for result in results:
        if result.error is not None:
            continue
        entry = next_source_state.setdefault(
            result.source["id"],
            {
                "initialized_at": generated_at,
                "tier": result.source["tier"],
            },
        )
        entry["last_success_at"] = generated_at
        entry["tier"] = result.source["tier"]
    report = {
        "schema_version": 1,
        "mode": "stateless-dry-run" if not args.write_state else "stateful-dry-run",
        "generated_at": generated_at,
        "policy": registry.get("policy", {}),
        "baseline": {
            "first_seen_sources": sorted(first_seen_sources),
            "suppressed_changes": baseline_suppressed,
        },
        "stats": {
            "sources_attempted": len(results),
            "sources_successful": sum(result.error is None for result in results),
            "verified_sources_successful": verified_successes,
            "package_records": len(records),
            "unique_releases": len(unique_releases),
            "unique_current_packages": len(latest),
            "changes": len(changes),
            "publish_eligible": sum(item["publish_eligible"] for item in changes),
            "checksum_conflicts": len(conflicts),
            "baseline_suppressed": baseline_suppressed,
            "pending_total": len(next_pending),
            "pending_eligible": sum(
                bool(item.get("publish_eligible")) for item in next_pending.values()
            ),
            "evergreen_total": len(next_evergreen),
            "evergreen_eligible": sum(
                bool(item.get("publish_eligible")) and not item.get("drafted_at")
                for item in next_evergreen.values()
            ),
        },
        "sources": [
            {
                "id": result.source["id"],
                "name": result.source["name"],
                "tier": result.source["tier"],
                "status": "ok" if result.error is None else "error",
                "feed_url": result.feed_url,
                "package_count": len(result.packages),
                "error": result.error,
                "attempts": result.attempts,
            }
            for result in results
        ],
        "conflicts": conflicts[: args.max_items],
        "changes": changes[: args.max_items],
        "truncated": len(changes) > args.max_items or len(conflicts) > args.max_items,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.summary.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    args.summary.write_text(_markdown(report), encoding="utf-8")
    if args.write_state:
        state_payload = {
            "schema_version": 1,
            "updated_at": generated_at,
            "packages": next_state,
            "pending": next_pending,
            "evergreen": next_evergreen,
            "sources": next_source_state,
        }
        args.state.parent.mkdir(parents=True, exist_ok=True)
        args.state.write_text(json.dumps(state_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, default=Path("automation/sources.json"))
    parser.add_argument("--state", type=Path, default=Path("automation/state/known-packages.json"))
    parser.add_argument("--output", type=Path, default=Path("automation/out/report.json"))
    parser.add_argument("--summary", type=Path, default=Path("automation/out/summary.md"))
    parser.add_argument("--tiers", default="verified,observe")
    parser.add_argument("--only", default="", help="Optional comma-separated source ids")
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--workers", type=int, default=10)
    parser.add_argument("--max-items", type=int, default=250)
    parser.add_argument("--require-verified", type=int, default=1)
    parser.add_argument(
        "--baseline-new-sources",
        action="store_true",
        help="Suppress changes when a source succeeds for the first time.",
    )
    parser.add_argument(
        "--write-state",
        action="store_true",
        help="Persist the current feed snapshot. Omit for a non-mutating dry run.",
    )
    args = parser.parse_args(argv)
    if not 1 <= args.workers <= 20:
        parser.error("--workers must be between 1 and 20")
    if not 1 <= args.max_items <= 2000:
        parser.error("--max-items must be between 1 and 2000")
    if not 1 <= args.timeout <= 30:
        parser.error("--timeout must be between 1 and 30 seconds")
    if not 0 <= args.require_verified <= 100:
        parser.error("--require-verified must be between 0 and 100")
    return args


def main() -> int:
    try:
        report = run(parse_args())
    except (ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"scanner error: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(report["stats"], sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
