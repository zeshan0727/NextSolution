from copy import deepcopy
from contextlib import redirect_stdout
import io
from pathlib import Path
import json
import re
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
from xml.etree import ElementTree

from automation.draft_pipeline import (
    article_source_url,
    display_author,
    generate_draft,
    render_article,
    main,
    select_media_ready_candidate,
    validate_article,
    write_artifacts,
)
from automation.editorial import load_json, select_candidate
from automation.source_media import SourceMediaError


AUTOMATION = Path("automation")
FIXTURES = AUTOMATION / "tests" / "fixtures"


class DraftPipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.categories = load_json(AUTOMATION / "categories.json")
        cls.site = load_json(AUTOMATION / "site.json")
        cls.state = load_json(FIXTURES / "editorial-state.json")
        cls.candidate = select_candidate(cls.state, cls.categories, cls.site)
        cls.article = load_json(FIXTURES / "article-draft.json")

    def test_fixture_passes_deterministic_quality_gates(self) -> None:
        result = validate_article(self.article, self.candidate)
        self.assertTrue(result.approved, result.issues)
        self.assertGreaterEqual(result.metrics["youtube_narration_words"], 900)

    def test_unsupported_claims_and_urls_are_rejected(self) -> None:
        article = deepcopy(self.article)
        article["compatibility_note"] += " It supports iOS 18 with Dopamine. https://bad.example/test"
        result = validate_article(article, self.candidate)
        self.assertFalse(result.approved)
        joined = " ".join(result.issues)
        self.assertIn("unsupported iOS version claim", joined)
        self.assertIn("unsupported jailbreak claim", joined)
        self.assertIn("must not contain URLs", joined)

    def test_renderer_escapes_text_and_emits_valid_json_ld(self) -> None:
        article = deepcopy(self.article)
        article["summary"] += " <script>alert(1)</script>"
        rendered = render_article(article, self.candidate, self.site)
        self.assertNotIn("<script>alert(1)</script>", rendered)
        self.assertIn("&lt;script&gt;alert(1)&lt;/script&gt;", rendered)
        match = re.search(
            r'<script type="application/ld\+json">(.*?)</script>', rendered, re.S
        )
        self.assertIsNotNone(match)
        payload = json.loads(match.group(1))
        self.assertEqual(payload["@type"], "TechArticle")
        self.assertIn("https://example.com/repo/", rendered)
        self.assertNotIn("https://example.com/depictions/", rendered)

    def test_havoc_depiction_maps_to_direct_package_page(self) -> None:
        candidate = deepcopy(self.candidate)
        candidate["source_url"] = "https://havoc.app/"
        candidate["facts_url"] = "https://havoc.app/package/example/depiction.json"
        self.assertEqual(
            article_source_url(candidate), "https://havoc.app/package/example"
        )

    def test_public_author_omits_control_file_email(self) -> None:
        self.assertEqual(display_author("Example Dev <dev@example.com>"), "Example Dev")

    def test_artifact_bundle_is_explicitly_non_publishing(self) -> None:
        quality = validate_article(self.article, self.candidate)
        verifier = {
            "approved": True,
            "issues": [],
            "unsupported_claims": [],
            "notes": "fixture",
        }
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            write_artifacts(
                output,
                self.article,
                self.candidate,
                self.site,
                quality,
                verifier,
                {"fixture": True},
            )
            manifest = json.loads((output / "manifest.json").read_text())
            self.assertFalse(manifest["publication_authorized"])
            self.assertFalse(manifest["shortener_enabled"])
            ElementTree.fromstring((output / "sitemap-entry.xml").read_text())
            ElementTree.fromstring((output / "rss-item.xml").read_text())
            self.assertTrue((output / "youtube-script.md").exists())
            self.assertFalse((output / "article-visual.svg").exists())
            self.assertTrue(manifest["authentic_source_media_required"])

    def test_reader_article_hides_internal_automation_language(self) -> None:
        rendered = render_article(self.article, self.candidate, self.site)
        lowered = rendered.lower()
        self.assertNotIn("daily automation", lowered)
        self.assertNotIn("automated editor", lowered)
        self.assertNotIn("generated from", lowered)
        self.assertIn("authentic screenshots required", lowered)

    def test_rejected_generation_gets_one_bounded_repair_and_recheck(self) -> None:
        rejected = deepcopy(self.article)
        rejected["faq"] = rejected["faq"][:1]
        rejected["summary"] += " It supports iOS 18."
        rejected_verdict = {
            "approved": False,
            "issues": ["Unsupported compatibility claim."],
            "unsupported_claims": ["It supports iOS 18."],
            "notes": "repair required",
        }
        approved_verdict = {
            "approved": True,
            "issues": [],
            "unsupported_claims": [],
            "notes": "approved",
        }
        responses = [
            (rejected, {"response_id": "writer"}),
            (rejected_verdict, {"response_id": "verifier-1"}),
            (self.article, {"response_id": "repair"}),
            (approved_verdict, {"response_id": "verifier-2"}),
        ]
        with patch(
            "automation.draft_pipeline.structured_response", side_effect=responses
        ) as mocked:
            article, verifier, metadata = generate_draft(self.candidate, self.site)
        self.assertEqual(mocked.call_count, 4)
        self.assertEqual(article, self.article)
        self.assertTrue(verifier["approved"])
        self.assertTrue(metadata["repair_attempted"])
        self.assertIn("faq must contain 3-6 items", metadata["initial_rejection"]["deterministic_issues"])
        repair_payload = mocked.call_args_list[2].kwargs["input_payload"]
        self.assertIn("Unsupported compatibility claim.", repair_payload["rejection_reasons"])
        self.assertIn("unsupported iOS version claim", " ".join(repair_payload["rejection_reasons"]))

    def test_approved_generation_skips_repair(self) -> None:
        approved_verdict = {
            "approved": True,
            "issues": [],
            "unsupported_claims": [],
            "notes": "approved",
        }
        responses = [
            (self.article, {"response_id": "writer"}),
            (approved_verdict, {"response_id": "verifier"}),
        ]
        with patch(
            "automation.draft_pipeline.structured_response", side_effect=responses
        ) as mocked:
            article, verifier, metadata = generate_draft(self.candidate, self.site)
        self.assertEqual(mocked.call_count, 2)
        self.assertEqual(article, self.article)
        self.assertTrue(verifier["approved"])
        self.assertFalse(metadata["repair_attempted"])

    def test_verifier_rejection_without_details_still_triggers_repair(self) -> None:
        rejected_verdict = {
            "approved": False,
            "issues": [],
            "unsupported_claims": [],
            "notes": "rejected",
        }
        approved_verdict = {
            "approved": True,
            "issues": [],
            "unsupported_claims": [],
            "notes": "approved",
        }
        responses = [
            (self.article, {"response_id": "writer"}),
            (rejected_verdict, {"response_id": "verifier-1"}),
            (self.article, {"response_id": "repair"}),
            (approved_verdict, {"response_id": "verifier-2"}),
        ]
        with patch(
            "automation.draft_pipeline.structured_response", side_effect=responses
        ) as mocked:
            _, verifier, metadata = generate_draft(self.candidate, self.site)
        self.assertEqual(mocked.call_count, 4)
        self.assertTrue(verifier["approved"])
        self.assertTrue(metadata["repair_attempted"])
        repair_payload = mocked.call_args_list[2].kwargs["input_payload"]
        self.assertEqual(
            repair_payload["rejection_reasons"],
            ["The independent verifier rejected the draft without a detailed reason."],
        )

    def test_media_preflight_skips_blocked_candidate_before_generation(self) -> None:
        blocked = deepcopy(self.candidate)
        ready = deepcopy(self.candidate)
        blocked["package"] = "com.example.blocked"
        ready["package"] = "com.example.ready"
        with tempfile.TemporaryDirectory() as directory:
            catalog = Path(directory) / "source-media.json"
            catalog.write_text('{"schema_version": 1, "packages": {}}')
            with (
                patch(
                    "automation.draft_pipeline.select_candidate",
                    side_effect=[blocked, ready],
                ) as selected,
                patch(
                    "automation.draft_pipeline.resolve_source_media",
                    side_effect=[SourceMediaError("no media"), {"hero": {}}],
                ),
            ):
                candidate, skipped = select_media_ready_candidate(
                    self.state,
                    self.categories,
                    self.site,
                    catalog_path=catalog,
                )
        self.assertEqual(candidate["package"], "com.example.ready")
        self.assertEqual(skipped[0]["package"], "com.example.blocked")
        self.assertIn("com.example.blocked", selected.call_args_list[1].kwargs["excluded_packages"])

    def test_final_verifier_rejection_quarantines_candidate_and_tries_next(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state_path = root / "state.json"
            output = root / "draft"
            state = deepcopy(self.state)
            next_candidate = deepcopy(self.candidate)
            next_candidate["package"] = "com.example.nextcards"
            next_candidate["release_identities"] = [
                identity.replace("com.example.focuscards", "com.example.nextcards")
                for identity in next_candidate["release_identities"]
            ]
            next_pending = {}
            for identity, item in list(state["pending"].items()):
                copied = deepcopy(item)
                copied["package"] = "com.example.nextcards"
                copied["identity"] = copied["identity"].replace(
                    "com.example.focuscards", "com.example.nextcards"
                )
                copied["release_identity"] = copied["release_identity"].replace(
                    "com.example.focuscards", "com.example.nextcards"
                )
                next_pending[copied["release_identity"]] = copied
            state["pending"].update(next_pending)
            state_path.write_text(json.dumps(state))
            rejected = {
                "approved": False,
                "issues": ["compatibility wording omitted a tested iOS version"],
                "unsupported_claims": [],
                "notes": "reject",
            }
            approved = {
                "approved": True,
                "issues": [],
                "unsupported_claims": [],
                "notes": "approved",
            }
            argv = [
                "draft_pipeline",
                "--state",
                str(state_path),
                "--output",
                str(output),
            ]
            with (
                patch.object(sys, "argv", argv),
                patch(
                    "automation.draft_pipeline.select_media_ready_candidate",
                    side_effect=[(self.candidate, []), (next_candidate, [])],
                ),
                patch(
                    "automation.draft_pipeline.generate_draft",
                    side_effect=[
                        (self.article, rejected, {"attempt": 1}),
                        (self.article, approved, {"attempt": 2}),
                    ],
                ),
                redirect_stdout(io.StringIO()),
            ):
                self.assertEqual(main(), 0)
            saved = json.loads(state_path.read_text())
            rejected_items = [
                item
                for item in saved["pending"].values()
                if item["package"] == self.candidate["package"]
            ]
            self.assertTrue(all(item.get("draft_rejected_at") for item in rejected_items))
            manifest = json.loads((output / "manifest.json").read_text())
            self.assertEqual(manifest["candidate"]["package"], "com.example.nextcards")

    def test_cli_marks_fixture_release_and_does_not_repeat_it(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "state.json"
            output = root / "draft"
            shutil.copyfile(FIXTURES / "editorial-state.json", state)
            argv = [
                "draft_pipeline",
                "--state",
                str(state),
                "--fixture-article",
                str(FIXTURES / "article-draft.json"),
                "--output",
                str(output),
                "--write-state",
            ]
            with patch.object(sys, "argv", argv), redirect_stdout(io.StringIO()):
                self.assertEqual(main(), 0)
            saved = json.loads(state.read_text())
            self.assertTrue(
                all(item.get("drafted_at") for item in saved["pending"].values())
            )
            with patch.object(sys, "argv", argv), redirect_stdout(io.StringIO()):
                self.assertEqual(main(), 3)

    def test_cli_uses_evergreen_once_when_release_queue_is_empty(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state_path = root / "state.json"
            output = root / "draft"
            state = deepcopy(self.state)
            state["evergreen"] = state.pop("pending")
            state["pending"] = {}
            state_path.write_text(json.dumps(state))
            argv = [
                "draft_pipeline",
                "--state",
                str(state_path),
                "--fixture-article",
                str(FIXTURES / "article-draft.json"),
                "--output",
                str(output),
                "--write-state",
            ]
            with patch.object(sys, "argv", argv), redirect_stdout(io.StringIO()):
                self.assertEqual(main(), 0)
            manifest = json.loads((output / "manifest.json").read_text())
            saved = json.loads(state_path.read_text())
            self.assertEqual(manifest["candidate"]["selection_pool"], "evergreen")
            self.assertTrue(
                all(item.get("drafted_at") for item in saved["evergreen"].values())
            )
            with patch.object(sys, "argv", argv), redirect_stdout(io.StringIO()):
                self.assertEqual(main(), 3)


if __name__ == "__main__":
    unittest.main()
