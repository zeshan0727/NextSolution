import gzip
from pathlib import Path
import unittest
from unittest.mock import patch

from automation.scanner import (
    classify_changes,
    deduplicate,
    latest_releases,
    load_registry,
    normalize_package,
    scan_source,
    suppress_first_seen_sources,
    update_evergreen_catalog,
    update_pending_queue,
)


VERIFIED_SOURCE = {
    "id": "example",
    "name": "Example Repo",
    "url": "https://example.com/repo/",
    "tier": "verified",
}


def package(version: str = "1.0", sha: str = "a" * 64):
    return normalize_package(
        {
            "package": "com.example.cards",
            "name": "Example Cards",
            "version": version,
            "architecture": "iphoneos-arm64",
            "description": "Adds useful configurable cards to the Home Screen.",
            "author": "Example Developer",
            "section": "Tweaks",
            "sha256": sha,
        },
        VERIFIED_SOURCE,
    )


class ScannerPolicyTests(unittest.TestCase):
    def test_committed_registry_is_valid_and_complete(self) -> None:
        registry = load_registry(Path("automation/sources.json"))
        self.assertEqual(len(registry["sources"]), 68)
        self.assertGreaterEqual(
            sum(source["tier"] == "verified" for source in registry["sources"]), 1
        )

    def test_verified_complete_metadata_is_eligible(self) -> None:
        record = package()
        self.assertIsNotNone(record)
        self.assertEqual(record["blockers"], [])

    def test_scans_a_compressed_packages_index(self) -> None:
        payload = gzip.compress(
            (Path(__file__).parent / "fixtures" / "Packages").read_bytes()
        )
        source = dict(VERIFIED_SOURCE, feed_paths=["Packages.gz"])
        with patch("automation.scanner._fetch", return_value=payload):
            result = scan_source(source, timeout=1)
        self.assertIsNone(result.error)
        self.assertEqual(result.feed_url, "https://example.com/repo/Packages.gz")
        self.assertEqual(len(result.packages), 2)

    def test_risky_language_is_blocked(self) -> None:
        record = normalize_package(
            {
                "package": "com.example.menu",
                "version": "1.0",
                "architecture": "iphoneos-arm64",
                "name": "Unlimited Gems Mod Menu",
                "description": "A game cheat package with configurable controls.",
                "author": "Unknown",
                "sha256": "c" * 64,
            },
            VERIFIED_SOURCE,
        )
        self.assertIn("game_cheat_language", record["blockers"])

    def test_conflicting_checksums_are_never_eligible(self) -> None:
        first = package(sha="a" * 64)
        second = package(sha="b" * 64)
        second["source_id"] = "mirror"
        selected, conflicts = deduplicate([first, second])
        self.assertEqual(len(conflicts), 1)
        self.assertIn("checksum_conflict", selected[0]["blockers"])

    def test_observe_source_cannot_outrank_verified_source(self) -> None:
        verified = package(version="1.0")
        observed = package(version="99.0")
        observed["source_id"] = "unreviewed-mirror"
        observed["source_tier"] = "observe"
        observed["blockers"] = ["source_requires_review"]
        selected = latest_releases([verified, observed])
        self.assertEqual(len(selected), 1)
        self.assertEqual(selected[0]["version"], "1.0")
        self.assertEqual(selected[0]["source_tier"], "verified")

    def test_same_version_checksum_change_is_blocked(self) -> None:
        record = package(sha="b" * 64)
        state = {
            "packages": {
                record["identity"]: {
                    "version": "1.0",
                    "sha256": "a" * 64,
                    "source_id": "example",
                }
            }
        }
        changes, _ = classify_changes([record], state)
        self.assertEqual(changes[0]["change_type"], "checksum_changed")
        self.assertFalse(changes[0]["publish_eligible"])
        self.assertIn("immutable_version_changed", changes[0]["blockers"])

    def test_missing_source_does_not_disappear_from_next_state(self) -> None:
        state = {
            "packages": {
                "com.example.unavailable|iphoneos-arm64": {
                    "version": "2.0",
                    "sha256": "d" * 64,
                    "source_id": "temporarily-down",
                }
            }
        }
        _, next_state = classify_changes([], state)
        self.assertIn("com.example.unavailable|iphoneos-arm64", next_state)

    def test_first_successful_source_is_baselined(self) -> None:
        record = package()
        changes, _ = classify_changes([record], {"packages": {}})
        retained, suppressed = suppress_first_seen_sources(changes, {"example"})
        self.assertEqual(retained, [])
        self.assertEqual(suppressed, 1)

    def test_initialized_source_can_emit_a_future_update(self) -> None:
        record = package(version="1.1")
        state = {
            "packages": {
                record["identity"]: {
                    "version": "1.0",
                    "sha256": "a" * 64,
                    "source_id": "example",
                }
            }
        }
        changes, _ = classify_changes([record], state)
        retained, suppressed = suppress_first_seen_sources(changes, set())
        self.assertEqual(len(retained), 1)
        self.assertEqual(retained[0]["change_type"], "updated")
        self.assertEqual(suppressed, 0)

    def test_eligible_change_stays_in_pending_queue(self) -> None:
        record = package(version="1.1")
        record["change_type"] = "updated"
        record["previous_version"] = "1.0"
        record["publish_eligible"] = True
        pending = update_pending_queue({}, [record], [record], "2026-08-12T00:00:00+00:00")
        self.assertIn(record["release_identity"], pending)
        self.assertEqual(pending[record["release_identity"]]["detected_at"], "2026-08-12T00:00:00+00:00")

    def test_newer_blocked_release_removes_stale_pending_item(self) -> None:
        old = package(version="1.0")
        old["change_type"] = "new"
        old["previous_version"] = None
        old["publish_eligible"] = True
        old["detected_at"] = "2026-08-11T00:00:00+00:00"
        current = package(version="1.1")
        current["blockers"] = ["checksum_conflict"]
        pending = update_pending_queue(
            {old["release_identity"]: old},
            [current],
            [],
            "2026-08-12T00:00:00+00:00",
        )
        self.assertEqual(pending, {})

    def test_pending_item_is_preserved_during_source_failure(self) -> None:
        old = package(version="1.0")
        old["detected_at"] = "2026-08-11T00:00:00+00:00"
        pending = update_pending_queue(
            {old["release_identity"]: old},
            [],
            [],
            "2026-08-12T00:00:00+00:00",
        )
        self.assertIn(old["release_identity"], pending)

    def test_drafted_marker_survives_the_next_scan(self) -> None:
        old = package(version="1.0")
        old["change_type"] = "new"
        old["previous_version"] = None
        old["publish_eligible"] = True
        old["detected_at"] = "2026-08-11T00:00:00+00:00"
        old["drafted_at"] = "2026-08-11T01:00:00+00:00"
        old["draft_target"] = "example-cards-tweak.html"
        old["candidate_fingerprint"] = "abc123"
        current = package(version="1.0")
        pending = update_pending_queue(
            {old["release_identity"]: old},
            [current],
            [],
            "2026-08-12T00:00:00+00:00",
        )
        refreshed = pending[old["release_identity"]]
        self.assertEqual(refreshed["drafted_at"], old["drafted_at"])
        self.assertEqual(refreshed["candidate_fingerprint"], "abc123")

    def test_verifier_rejection_quarantine_survives_the_next_scan(self) -> None:
        old = package(version="1.1")
        old["change_type"] = "updated"
        old["previous_version"] = "1.0"
        old["publish_eligible"] = True
        old["detected_at"] = "2026-08-26T05:00:00+00:00"
        old["draft_rejected_at"] = "2026-08-26T06:00:00+00:00"
        old["draft_rejection_reason"] = "independent verifier rejected the draft"
        old["draft_rejection_fingerprint"] = "abc123"
        current = package(version="1.1")
        pending = update_pending_queue(
            {old["release_identity"]: old},
            [current],
            [],
            "2026-08-26T07:00:00+00:00",
        )
        refreshed = pending[old["release_identity"]]
        self.assertEqual(
            refreshed["draft_rejected_at"], old["draft_rejected_at"]
        )
        self.assertEqual(
            refreshed["draft_rejection_fingerprint"],
            old["draft_rejection_fingerprint"],
        )

    def test_verified_release_enters_evergreen_catalog(self) -> None:
        record = package()
        catalog = update_evergreen_catalog(
            {}, [record], {"example"}, "2026-08-12T00:00:00+00:00"
        )
        saved = catalog[record["release_identity"]]
        self.assertTrue(saved["publish_eligible"])
        self.assertEqual(saved["change_type"], "evergreen")
        self.assertEqual(saved["cataloged_at"], "2026-08-12T00:00:00+00:00")

    def test_unverified_or_blocked_release_is_not_evergreen(self) -> None:
        observed = package()
        observed["source_tier"] = "observe"
        blocked = package(version="2.0")
        blocked["blockers"] = ["checksum_conflict"]
        catalog = update_evergreen_catalog(
            {}, [observed, blocked], {"example"}, "2026-08-12T00:00:00+00:00"
        )
        self.assertEqual(catalog, {})

    def test_evergreen_marker_survives_refresh(self) -> None:
        record = package()
        saved = dict(record)
        saved.update(
            {
                "publish_eligible": True,
                "drafted_at": "2026-08-11T01:00:00+00:00",
                "draft_target": "example-cards-tweak.html",
                "candidate_fingerprint": "abc123",
                "cataloged_at": "2026-08-11T00:00:00+00:00",
            }
        )
        catalog = update_evergreen_catalog(
            {record["release_identity"]: saved},
            [record],
            {"example"},
            "2026-08-12T00:00:00+00:00",
        )
        refreshed = catalog[record["release_identity"]]
        self.assertEqual(refreshed["drafted_at"], saved["drafted_at"])
        self.assertEqual(refreshed["cataloged_at"], saved["cataloged_at"])

    def test_evergreen_survives_outage_but_not_successful_blocked_refresh(self) -> None:
        record = package()
        saved = dict(record, publish_eligible=True)
        existing = {record["release_identity"]: saved}
        during_outage = update_evergreen_catalog(
            existing, [], set(), "2026-08-12T00:00:00+00:00"
        )
        self.assertIn(record["release_identity"], during_outage)
        blocked = package(version="2.0")
        blocked["blockers"] = ["checksum_conflict"]
        after_refresh = update_evergreen_catalog(
            existing, [blocked], {"example"}, "2026-08-12T00:00:00+00:00"
        )
        self.assertEqual(after_refresh, {})

    def test_current_identity_supersedes_outage_copy_from_another_source(self) -> None:
        old = package(version="1.0")
        existing = {old["release_identity"]: dict(old, publish_eligible=True)}
        current = package(version="2.0")
        current["source_id"] = "replacement"
        current["source_name"] = "Replacement Repo"
        catalog = update_evergreen_catalog(
            existing,
            [current],
            {"replacement"},
            "2026-08-12T00:00:00+00:00",
        )
        self.assertNotIn(old["release_identity"], catalog)
        self.assertIn(current["release_identity"], catalog)


if __name__ == "__main__":
    unittest.main()
