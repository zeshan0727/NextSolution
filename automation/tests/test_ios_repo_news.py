from __future__ import annotations

from datetime import datetime, timezone
import unittest

from automation import ios_repo_news as news
from automation import ios_repo_news_hardened as hardened


class IOSRepoOriginalSourceNewsTests(unittest.TestCase):
    def test_candidate_path_extracts_repository_and_package(self) -> None:
        self.assertEqual(
            news._candidate_parts("https://www.ios-repo-updates.com/repository/poomsmart/package/com.ps.polyfills/"),
            ("poomsmart", "com.ps.polyfills"),
        )

    def test_audience_scoring_prefers_jailbreak_over_development(self) -> None:
        config = {
            "section_score": {"Jailbreak": 80, "Tweaks": 65, "Development": -25},
            "keyword_score": {"dopamine": 100, "jailbreak": 80},
        }
        jailbreak = news._score("Dopamine jailbreak Update Tweaks", config)
        framework = news._score("HookKit Framework Update Development", config)
        self.assertGreater(jailbreak, framework)

    def test_public_source_hosts_never_include_discovery_or_social_hosts(self) -> None:
        self.assertIn("ios-repo-updates.com", news.DISCOVERY_HOSTS)
        self.assertIn("x.com", hardened.BLOCKED_HINT_HOSTS)
        self.assertIn("t.me", hardened.BLOCKED_HINT_HOSTS)

    def test_validation_rejects_discovery_site_mentions(self) -> None:
        article = {
            "meta_description": "A" * 120,
            "summary": "iOS Repo Updates says this package changed. " + ("word " * 60),
            "key_takeaways": ["useful detail " * 6] * 4,
            "sections": [
                {"heading": f"Section {i}", "paragraphs": ["detail " * 60, "context " * 60], "bullets": []}
                for i in range(5)
            ],
            "faq": [{"question": "What changed here?", "answer": "answer " * 40}] * 3,
            "social_post": "A factual social post about the update without a URL.",
        }
        issues = news.validate_article(article, {}, {"minimum_article_words": 200, "minimum_sections": 5})
        self.assertTrue(any("discovery site" in issue for issue in issues))

    def test_preflight_respects_twice_daily_limit(self) -> None:
        now = datetime(2026, 8, 31, 18, 0, tzinfo=timezone.utc)
        config = {"enabled": True, "timezone": "Asia/Qatar", "max_per_day": 2, "minimum_site_gap_minutes": 90}
        audit = {
            "entries": [
                {"entry_type": "source-news", "published_at": "2026-08-31T08:00:00+00:00"},
                {"entry_type": "source-news", "published_at": "2026-08-31T14:00:00+00:00"},
            ]
        }
        allowed, reason = news.preflight(config, audit, now)
        self.assertFalse(allowed)
        self.assertEqual(reason, "daily-source-news-limit")


if __name__ == "__main__":
    unittest.main()
