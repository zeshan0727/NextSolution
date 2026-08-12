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
    render_article,
    main,
    validate_article,
    write_artifacts,
)
from automation.editorial import load_json, select_candidate


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
        self.assertEqual(payload["@type"], "Article")
        self.assertIn("https://example.com/repo/", rendered)
        self.assertNotIn("https://example.com/depictions/", rendered)

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
