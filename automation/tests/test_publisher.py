from copy import deepcopy
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from xml.etree import ElementTree

from automation.draft_pipeline import validate_article
from automation.editorial import load_json, select_candidate
from automation.publisher import PublishingError, preflight, publish


AUTOMATION = Path("automation")
FIXTURES = AUTOMATION / "tests" / "fixtures"
NOW = datetime(2026, 8, 12, 14, 30, tzinfo=timezone.utc)


class PublisherTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        categories = load_json(AUTOMATION / "categories.json")
        state = load_json(FIXTURES / "editorial-state.json")
        base_site = load_json(AUTOMATION / "site.json")
        cls.site = deepcopy(base_site)
        cls.site["base_url"] = "https://nextjailbreak.com"
        cls.site["publishing"]["enabled"] = True
        cls.site["publishing"]["max_per_day"] = 3
        cls.site["publishing"]["timezone"] = "Asia/Qatar"
        cls.site["shortener"]["enabled"] = False
        cls.candidate = select_candidate(state, categories, cls.site)
        cls.article = load_json(FIXTURES / "article-draft.json")

    def empty_audit(self) -> dict:
        return {
            "schema_version": 1,
            "updated_at": None,
            "entries": [],
            "events": [],
        }

    def manifest(self) -> dict:
        quality = validate_article(self.article, self.candidate)
        return {
            "schema_version": 1,
            "candidate_fingerprint": "a" * 64,
            "target_path": f"{self.candidate['slug']}.html",
            "candidate": deepcopy(self.candidate),
            "article": deepcopy(self.article),
            "deterministic_quality": {
                "approved": quality.approved,
                "issues": quality.issues,
                "metrics": quality.metrics,
            },
            "verifier": {
                "approved": True,
                "issues": [],
                "unsupported_claims": [],
                "notes": "approved",
            },
            "api": {"verifier": {"model": "gpt-5.6-luna"}},
            "publication_authorized": False,
            "shortener_enabled": False,
        }

    def prepare_root(self, root: Path) -> Path:
        (root / "index.html").write_text(
            f"<main>{'<!-- AUTO_ARTICLES_HOME_START -->'}\n{'<!-- AUTO_ARTICLES_HOME_END -->'}</main>",
            encoding="utf-8",
        )
        (root / "tutorials.html").write_text(
            f"<main>{'<!-- AUTO_ARTICLES_TUTORIALS_START -->'}\n{'<!-- AUTO_ARTICLES_TUTORIALS_END -->'}</main>",
            encoding="utf-8",
        )
        (root / "sitemap.xml").write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
            "<url><loc>https://nextjailbreak.com/</loc></url></urlset>",
            encoding="utf-8",
        )
        audit_path = root / "automation" / "published-articles.json"
        audit_path.parent.mkdir(parents=True)
        (root / "automation" / "source-media.json").write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "packages": {
                        self.candidate["package"]: {
                            "credit_label": "Example Developer official listing",
                            "source_page_url": "https://example.com/focuscards",
                            "official_source": True,
                            "hero": {
                                "url": "assets/articles/focus-cards-real.jpg",
                                "alt": "Focus Cards real feature screenshot",
                            },
                            "screenshots": [],
                        }
                    },
                }
            ),
            encoding="utf-8",
        )
        return audit_path

    def test_preflight_obeys_kill_switch_and_three_hour_boost(self) -> None:
        ready = preflight(self.site, self.empty_audit(), now=NOW)
        self.assertTrue(ready.allowed)
        self.assertEqual(ready.local_day, "2026-08-12")
        self.assertTrue(ready.boost_active)
        self.assertEqual(ready.max_today, 8)
        disabled = deepcopy(self.site)
        disabled["publishing"]["enabled"] = False
        self.assertEqual(
            preflight(disabled, self.empty_audit(), now=NOW).reason,
            "kill-switch-disabled",
        )
        recent = self.empty_audit()
        recent["events"].append(
            {"published_at": (NOW - timedelta(hours=2)).isoformat()}
        )
        blocked = preflight(self.site, recent, now=NOW)
        self.assertFalse(blocked.allowed)
        self.assertEqual(blocked.reason, "three-hour-interval-not-reached")

    def test_preflight_allows_three_per_day_after_boost(self) -> None:
        after_boost = datetime(2026, 8, 17, 20, 30, tzinfo=timezone.utc)
        audit = self.empty_audit()
        audit["events"].extend(
            [
                {"published_at": "2026-08-17T03:10:00+00:00"},
                {"published_at": "2026-08-17T11:10:00+00:00"},
            ]
        )
        ready = preflight(self.site, audit, now=after_boost)
        self.assertTrue(ready.allowed)
        self.assertFalse(ready.boost_active)
        self.assertEqual(ready.max_today, 3)

        audit["events"].append({"published_at": "2026-08-17T19:10:00+00:00"})
        blocked = preflight(self.site, audit, now=after_boost)
        self.assertFalse(blocked.allowed)
        self.assertEqual(blocked.reason, "publication-limit-reached")

        expired_trigger = preflight(
            self.site,
            self.empty_audit(),
            now=after_boost,
            trigger_schedule=self.site["publishing"]["boost_cron"],
        )
        self.assertEqual(expired_trigger.reason, "launch-boost-ended")

    def test_scheduled_retry_only_allows_an_unmet_local_window(self) -> None:
        after_boost = datetime(2026, 8, 26, 5, 30, tzinfo=timezone.utc)
        schedule = self.site["publishing"]["normal_cron"]
        first_due = preflight(
            self.site,
            self.empty_audit(),
            now=after_boost,
            trigger_schedule=schedule,
        )
        self.assertTrue(first_due.allowed)

        audit = self.empty_audit()
        audit["events"].append(
            {"action": "create", "published_at": "2026-08-26T03:12:00+00:00"}
        )
        satisfied = preflight(
            self.site,
            audit,
            now=after_boost,
            trigger_schedule=schedule,
        )
        self.assertFalse(satisfied.allowed)
        self.assertEqual(satisfied.reason, "scheduled-window-already-satisfied")

        second_due = preflight(
            self.site,
            audit,
            now=datetime(2026, 8, 26, 11, 30, tzinfo=timezone.utc),
            trigger_schedule=schedule,
        )
        self.assertTrue(second_due.allowed)

    def test_scheduled_retry_waits_until_first_local_window(self) -> None:
        before_first_window = datetime(2026, 8, 26, 2, 30, tzinfo=timezone.utc)
        result = preflight(
            self.site,
            self.empty_audit(),
            now=before_first_window,
            trigger_schedule=self.site["publishing"]["normal_cron"],
        )
        self.assertFalse(result.allowed)
        self.assertEqual(result.reason, "no-publishing-window-due")

    def test_preflight_does_not_count_existing_page_updates_as_new_posts(self) -> None:
        after_boost = datetime(2026, 8, 17, 20, 30, tzinfo=timezone.utc)
        audit = self.empty_audit()
        audit["events"].extend(
            [
                {
                    "action": "update",
                    "published_at": "2026-08-17T03:10:00+00:00",
                },
                {
                    "action": "update",
                    "published_at": "2026-08-17T11:10:00+00:00",
                },
                {
                    "action": "update",
                    "published_at": "2026-08-17T19:10:00+00:00",
                },
            ]
        )
        ready = preflight(self.site, audit, now=after_boost)
        self.assertTrue(ready.allowed)
        self.assertEqual(ready.published_today, 0)
        self.assertEqual(ready.max_today, 3)

    def test_publish_writes_article_cards_feed_sitemap_and_audit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            audit_path = self.prepare_root(root)
            result = publish(
                repository_root=root,
                manifest=self.manifest(),
                site=self.site,
                audit=self.empty_audit(),
                audit_path=audit_path,
                now=NOW,
                run_id="123",
                confirm_live=True,
            )
            self.assertTrue(result["published"])
            target = root / f"{self.candidate['slug']}.html"
            self.assertTrue(target.exists())
            self.assertIn("/assets/site.css", target.read_text())
            self.assertIn(
                "assets/articles/focus-cards-real.jpg", target.read_text()
            )
            self.assertNotIn("concept artwork", target.read_text().lower())
            self.assertIn(self.article["title"], (root / "index.html").read_text())
            self.assertIn(self.article["title"], (root / "tutorials.html").read_text())
            feed = ElementTree.fromstring((root / "feed.xml").read_text())
            self.assertEqual(feed.tag, "rss")
            sitemap = ElementTree.fromstring((root / "sitemap.xml").read_text())
            self.assertTrue(sitemap.tag.endswith("urlset"))
            audit = json.loads(audit_path.read_text())
            self.assertEqual(len(audit["entries"]), 1)
            self.assertEqual(len(audit["events"]), 1)
            self.assertEqual(
                audit["entries"][0]["image"],
                "assets/articles/focus-cards-real.jpg",
            )
            self.assertEqual(audit["events"][0]["run_id"], "123")
            self.assertEqual(
                preflight(self.site, audit, now=NOW).reason,
                "three-hour-interval-not-reached",
            )

    def test_live_editorial_state_is_marked_only_by_successful_publication(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            audit_path = self.prepare_root(root)
            state_path = root / "automation" / "runtime-state" / "known-packages.json"
            state_path.parent.mkdir(parents=True)
            shutil.copyfile(FIXTURES / "editorial-state.json", state_path)

            publish(
                repository_root=root,
                manifest=self.manifest(),
                site=self.site,
                audit=self.empty_audit(),
                audit_path=audit_path,
                now=NOW,
                run_id="state-after-publish",
                confirm_live=True,
                editorial_state_path=state_path,
            )

            saved = json.loads(state_path.read_text())
            self.assertTrue(
                all(item.get("drafted_at") for item in saved["pending"].values())
            )
            self.assertTrue(
                all(
                    item.get("draft_target") == self.manifest()["target_path"]
                    for item in saved["pending"].values()
                )
            )

    def test_editorial_entry_stays_in_feed_without_duplicate_generated_card(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            audit_path = self.prepare_root(root)
            audit = self.empty_audit()
            editorial_title = "Top Home Screen Tweaks"
            editorial_time = (NOW - timedelta(hours=3)).isoformat()
            audit["entries"].append(
                {
                    "entry_type": "editorial",
                    "package": "editorial.home-screen",
                    "href": "top-home-screen-tweaks.html",
                    "title": editorial_title,
                    "description": "A source-checked editorial roundup.",
                    "category": {"id": "home-screen", "label": "Home Screen"},
                    "published_at": editorial_time,
                    "modified_at": editorial_time,
                }
            )
            audit["events"].append({"published_at": editorial_time})
            publish(
                repository_root=root,
                manifest=self.manifest(),
                site=self.site,
                audit=audit,
                audit_path=audit_path,
                now=NOW,
                run_id="editorial-preservation",
                confirm_live=True,
            )
            self.assertNotIn(editorial_title, (root / "index.html").read_text())
            self.assertIn(editorial_title, (root / "feed.xml").read_text())
            next_audit = json.loads(audit_path.read_text())
            self.assertEqual(len(next_audit["entries"]), 2)
            self.assertTrue(
                any(entry.get("entry_type") == "editorial" for entry in next_audit["entries"])
            )

    def test_duplicate_candidate_is_a_safe_noop_on_a_later_day(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            audit_path = self.prepare_root(root)
            manifest = self.manifest()
            publish(
                repository_root=root,
                manifest=manifest,
                site=self.site,
                audit=self.empty_audit(),
                audit_path=audit_path,
                now=NOW,
                run_id="123",
                confirm_live=True,
            )
            audit = json.loads(audit_path.read_text())
            next_day = datetime(2026, 8, 13, 14, 30, tzinfo=timezone.utc)
            duplicate = publish(
                repository_root=root,
                manifest=manifest,
                site=self.site,
                audit=audit,
                audit_path=audit_path,
                now=next_day,
                run_id="124",
                confirm_live=True,
            )
            self.assertFalse(duplicate["published"])
            self.assertTrue(duplicate["duplicate"])
            unchanged = json.loads(audit_path.read_text())
            self.assertEqual(len(unchanged["events"]), 1)

    def test_new_version_updates_the_existing_package_url(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            audit_path = self.prepare_root(root)
            first_manifest = self.manifest()
            publish(
                repository_root=root,
                manifest=first_manifest,
                site=self.site,
                audit=self.empty_audit(),
                audit_path=audit_path,
                now=NOW,
                run_id="123",
                confirm_live=True,
            )
            first_audit = json.loads(audit_path.read_text())
            original_published_at = first_audit["entries"][0]["published_at"]

            update_manifest = self.manifest()
            previous_version = str(update_manifest["candidate"]["version"])
            update_manifest["candidate"]["version"] = "9.9.9"
            update_manifest["article"]["title"] = update_manifest["article"][
                "title"
            ].replace(previous_version, "9.9.9")
            update_manifest["candidate_fingerprint"] = "b" * 64
            next_day = datetime(2026, 8, 13, 14, 30, tzinfo=timezone.utc)
            result = publish(
                repository_root=root,
                manifest=update_manifest,
                site=self.site,
                audit=first_audit,
                audit_path=audit_path,
                now=next_day,
                run_id="124",
                confirm_live=True,
            )

            self.assertEqual(result["action"], "update")
            self.assertEqual(result["target_path"], first_manifest["target_path"])
            updated_audit = json.loads(audit_path.read_text())
            self.assertEqual(len(updated_audit["entries"]), 1)
            self.assertEqual(len(updated_audit["events"]), 2)
            self.assertEqual(updated_audit["entries"][0]["version"], "9.9.9")
            self.assertEqual(
                updated_audit["entries"][0]["published_at"], original_published_at
            )

    def test_rejects_unapproved_or_self_authorized_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            audit_path = self.prepare_root(root)
            rejected = self.manifest()
            rejected["verifier"]["approved"] = False
            with self.assertRaises(PublishingError):
                publish(
                    repository_root=root,
                    manifest=rejected,
                    site=self.site,
                    audit=self.empty_audit(),
                    audit_path=audit_path,
                    now=NOW,
                    run_id="125",
                    confirm_live=True,
                )
            self_authorized = self.manifest()
            self_authorized["publication_authorized"] = True
            with self.assertRaises(PublishingError):
                publish(
                    repository_root=root,
                    manifest=self_authorized,
                    site=self.site,
                    audit=self.empty_audit(),
                    audit_path=audit_path,
                    now=NOW,
                    run_id="126",
                    confirm_live=True,
                )

    def test_requires_explicit_verified_and_eligible_source_flags(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            audit_path = self.prepare_root(root)
            for field in ("source_tier", "publish_eligible"):
                manifest = self.manifest()
                manifest["candidate"].pop(field)
                with self.subTest(field=field), self.assertRaises(PublishingError):
                    publish(
                        repository_root=root,
                        manifest=manifest,
                        site=self.site,
                        audit=self.empty_audit(),
                        audit_path=audit_path,
                        now=NOW,
                        run_id="128",
                        confirm_live=True,
                    )

    def test_refuses_to_overwrite_an_unmanaged_article(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            audit_path = self.prepare_root(root)
            (root / f"{self.candidate['slug']}.html").write_text("user content")
            with self.assertRaises(PublishingError):
                publish(
                    repository_root=root,
                    manifest=self.manifest(),
                    site=self.site,
                    audit=self.empty_audit(),
                    audit_path=audit_path,
                    now=NOW,
                    run_id="127",
                    confirm_live=True,
                )


if __name__ == "__main__":
    unittest.main()
