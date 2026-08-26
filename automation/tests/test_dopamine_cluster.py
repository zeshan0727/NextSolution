from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
import tempfile
import unittest

from automation.dopamine_cluster import (
    cluster_preflight,
    load_json,
    render_article,
    select_topic,
    validate_article,
)


AUTOMATION = Path("automation")
NOW = datetime(2026, 8, 19, 15, 10, tzinfo=timezone.utc)


class DopamineClusterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.cluster = load_json(AUTOMATION / "dopamine3-cluster.json")
        cls.site = load_json(AUTOMATION / "site.json")

    def empty_state(self) -> dict:
        return {"schema_version": 1, "published": {}, "events": []}

    def fixture_article(self) -> dict:
        paragraph = " ".join(
            [
                "The supplied official project facts define the supported scope, and readers should use the linked official source to confirm current details for their exact device before making changes."
            ]
            * 8
        )
        return {
            "title": "Dopamine 3 Compatibility Guide for Supported iOS Versions and Devices",
            "meta_description": "Check the official Dopamine 3 compatibility ranges for arm64e, A12/A13 and arm64 devices, with source-backed guidance for current iOS support.",
            "summary": "This source-backed guide organizes the compatibility facts published by the official Dopamine 3 project without extending support beyond the documented ranges.",
            "key_takeaways": [
                "Dopamine 3 is described by its official project as a rootless semi-untethered jailbreak.",
                "The official 3.x README publishes separate compatibility ranges for arm64e, A12/A13 and arm64.",
                "Readers should verify their exact device and firmware at the official project before proceeding.",
            ],
            "sections": [
                {"heading": "Official compatibility structure", "paragraphs": [paragraph], "bullets": []},
                {"heading": "A12 and A13 range", "paragraphs": [paragraph], "bullets": []},
                {"heading": "arm64e and arm64 ranges", "paragraphs": [paragraph], "bullets": []},
                {"heading": "How to use the compatibility information", "paragraphs": [paragraph], "bullets": []},
            ],
            "faq": [
                {"question": "Is Dopamine 3 rootless?", "answer": "Yes. The supplied official project facts describe Dopamine as a rootless semi-untethered jailbreak."},
                {"question": "Should every arm64e device use the A12/A13 range?", "answer": "No. The supplied facts list a general arm64e range separately from the A12/A13 range, so the ranges must not be merged."},
                {"question": "Where should compatibility be confirmed?", "answer": "Use the linked official Dopamine project sources and confirm the exact device and firmware before making changes."},
            ],
            "social_post": "Dopamine 3 compatibility is broader than older releases, but the exact range depends on architecture and chip family. Here is the source-backed breakdown.",
        }

    def test_preflight_allows_two_pages_with_eight_hour_spacing(self) -> None:
        state = self.empty_state()
        ready = cluster_preflight(self.cluster, state, now=NOW)
        self.assertTrue(ready["allowed"])

        state["events"].append({"published_at": (NOW - timedelta(hours=9)).isoformat()})
        second = cluster_preflight(self.cluster, state, now=NOW)
        self.assertTrue(second["allowed"])
        self.assertEqual(second["published_today"], 1)

        state["events"].append({"published_at": (NOW - timedelta(minutes=10)).isoformat()})
        blocked = cluster_preflight(self.cluster, state, now=NOW)
        self.assertFalse(blocked["allowed"])
        self.assertEqual(blocked["reason"], "cluster-daily-limit")

    def test_preflight_blocks_short_interval(self) -> None:
        state = self.empty_state()
        state["events"].append({"published_at": (NOW - timedelta(hours=3)).isoformat()})
        blocked = cluster_preflight(self.cluster, state, now=NOW)
        self.assertFalse(blocked["allowed"])
        self.assertEqual(blocked["reason"], "cluster-interval-not-reached")

    def test_select_topic_prefers_master_hub(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            topic = select_topic(self.cluster, self.empty_state(), Path(directory))
            self.assertIsNotNone(topic)
            self.assertEqual(topic["id"], "dopamine3-master-compatibility")

    def test_select_topic_moves_to_next_after_publish(self) -> None:
        state = self.empty_state()
        state["published"]["dopamine3-master-compatibility"] = {"path": "dopamine-3-jailbreak.html"}
        with tempfile.TemporaryDirectory() as directory:
            topic = select_topic(self.cluster, state, Path(directory))
            self.assertIsNotNone(topic)
            self.assertEqual(topic["id"], "dopamine3-ios26-a12-a13")

    def test_quality_rejects_unsupported_ios_claim(self) -> None:
        topic = self.cluster["topics"][0]
        facts = {
            "common_facts": self.cluster["common_facts"],
            "topic_facts": topic["facts"],
        }
        article = self.fixture_article()
        article["sections"][0]["paragraphs"][0] += " iOS 99.1 is supported."
        issues = validate_article(article, facts)
        self.assertTrue(any("unsupported OS version" in issue for issue in issues))

    def test_quality_accepts_source_backed_major_version_wording(self) -> None:
        topic = self.cluster["topics"][0]
        facts = {
            "common_facts": self.cluster["common_facts"],
            "topic_facts": topic["facts"],
        }
        article = self.fixture_article()
        article["sections"][0]["paragraphs"][0] += (
            " Dopamine 3 reaches into the iOS 18 family only for the documented categories, "
            "while iOS 26 wording must remain limited to the documented A12 and A13 range."
        )
        issues = validate_article(article, facts)
        self.assertFalse(any("unsupported OS version" in issue for issue in issues))

    def test_render_uses_existing_real_dopamine_visual_and_related_link(self) -> None:
        topic = self.cluster["topics"][0]
        rendered = render_article(
            self.fixture_article(),
            topic,
            self.cluster,
            self.site,
            self.empty_state(),
            NOW,
        )
        self.assertIn("dopamine-3-jailbreak-ios-17-6-1.html", rendered)
        self.assertIn("dopamine-3-ios-17-6-1-hero.jpg", rendered)
        self.assertIn("https://nextjailbreak.com/dopamine-3-jailbreak.html", rendered)


if __name__ == "__main__":
    unittest.main()
