from copy import deepcopy
from datetime import datetime, timezone
import json
from pathlib import Path
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
        cls.site["base_url"] = "https://nextsolution.cc"
        cls.site["publishing"] = {
            "enabled": True,
            "max_per_day": 1,
            "timezone": "Asia/Qatar",
        }
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
            "<url><loc>https://nextsolution.cc/</loc></url></urlset>",
            encoding="utf-8",
        )
        audit_path = root / "automation" / "published-articles.json"
        audit_path.parent.mkdir(parents=True)
        return audit_path

    def test_preflight_obeys_kill_switch_and_qatar_daily_limit(self) -> None:
        ready = preflight(self.site, self.empty_audit(), now=NOW)
        self.assertTrue(ready.allowed)
        self.assertEqual(ready.local_day, "2026-08-12")
        disabled = deepcopy(self.site)
        disabled["publishing"]["enabled"] = False
        self.assertEqual(
            preflight(disabled, self.empty_audit(), now=NOW).reason,
            "kill-switch-disabled",
        )
        audit = self.empty_audit()
        audit["events"].append({"published_at": "2026-08-12T00:01:00+00:00"})
        blocked = preflight(self.site, audit, now=NOW)
        self.assertFalse(blocked.allowed)
        self.assertEqual(blocked.reason, "daily-limit-reached")

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
            self.assertIn(self.article["title"], (root / "index.html").read_text())
            self.assertIn(self.article["title"], (root / "tutorials.html").read_text())
            feed = ElementTree.fromstring((root / "feed.xml").read_text())
            self.assertEqual(feed.tag, "rss")
            sitemap = ElementTree.fromstring((root / "sitemap.xml").read_text())
            self.assertTrue(sitemap.tag.endswith("urlset"))
            audit = json.loads(audit_path.read_text())
            self.assertEqual(len(audit["entries"]), 1)
            self.assertEqual(len(audit["events"]), 1)
            self.assertEqual(audit["events"][0]["run_id"], "123")
            self.assertEqual(
                preflight(self.site, audit, now=NOW).reason, "daily-limit-reached"
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
