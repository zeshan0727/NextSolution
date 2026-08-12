import gzip
from pathlib import Path
import unittest
from unittest.mock import patch

from automation.scanner import (
    classify_changes,
    deduplicate,
    load_registry,
    normalize_package,
    scan_source,
    suppress_first_seen_sources,
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


if __name__ == "__main__":
    unittest.main()
