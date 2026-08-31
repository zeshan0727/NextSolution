from copy import deepcopy
import unittest

from automation.quality_gate import evaluate_manifest


class QualityGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.site = {
            "quality": {
                "target_score": 9,
                "minimum_editorial_words": 500,
                "minimum_summary_words": 45,
                "minimum_feature_words": 110,
                "minimum_compatibility_words": 35,
                "minimum_installation_words": 100,
                "minimum_safety_words": 60,
                "minimum_faq_answer_words": 160,
                "require_authentic_source_media": True,
                "block_metadata_heavy_copy": True,
                "block_malformed_copy": True,
            }
        }

        def paragraph(topic: str, detail: str) -> str:
            return (
                f"For {topic}, this passage explains {detail} in practical terms for the reader. "
                "It explains why the behavior matters, which limitation deserves attention, how source evidence should be interpreted, "
                "and what should be verified before making a change. The wording adds editorial guidance instead of merely repeating metadata."
            )

        self.article = {
            "summary": paragraph("the overall package", "the main purpose, intended audience, strongest benefit, and important limitation") * 2,
            "what_it_does": [
                paragraph("interface behavior", "the visible change and when it is useful"),
                paragraph("daily workflow", "how the feature changes a common interaction"),
                paragraph("configuration", "which preferences affect the experience"),
                paragraph("system integration", "where the feature interacts with the operating system"),
                paragraph("practical value", "who benefits most and who may not need the feature"),
            ],
            "compatibility_note": paragraph("compatibility", "confirmed architecture information, dependency limits, and environment checks") * 2,
            "installation_steps": [
                paragraph("source verification", "how to confirm the original listing"),
                paragraph("device preparation", "why a backup and known-good state matter"),
                paragraph("package review", "how to inspect dependencies and compatibility"),
                paragraph("installation", "what to watch during the installation step"),
                paragraph("post-install check", "how to verify the expected feature without assuming unsupported behavior"),
            ],
            "safety_notes": [
                paragraph("backup safety", "why important data and a recovery path should exist first"),
                paragraph("dependency safety", "why dependencies and conflicts deserve verification"),
                paragraph("source trust", "why the original developer or repository page should remain the reference"),
            ],
            "faq": [
                {"question": "What should I verify before installing?", "answer": paragraph("pre-install verification", "the source, architecture, dependencies, and current release notes") * 2},
                {"question": "How do I judge whether the feature is useful?", "answer": paragraph("feature usefulness", "the workflow improvement, limits, and intended audience") * 2},
                {"question": "What compatibility information can I rely on?", "answer": paragraph("compatibility evidence", "only facts supported by the current source and package metadata") * 2},
                {"question": "What should I do if something goes wrong?", "answer": paragraph("recovery planning", "backups, rollback options, and returning to a known-good state") * 2},
            ],
        }
        self.manifest = {
            "article": self.article,
            "authentic_source_media_required": True,
            "verifier": {"approved": True, "issues": [], "unsupported_claims": []},
            "deterministic_quality": {"approved": True, "issues": []},
        }

    def test_deep_article_passes(self) -> None:
        report = evaluate_manifest(self.manifest, self.site)
        self.assertTrue(report["approved"], report["issues"])
        self.assertGreaterEqual(report["editorial_words"], 500)

    def test_thin_metadata_article_is_rejected(self) -> None:
        manifest = deepcopy(self.manifest)
        manifest["article"]["summary"] = "Review the supplied package facts and listed dependencies."
        manifest["article"]["what_it_does"] = ["Review the supplied package facts and listed architectures."] * 5
        report = evaluate_manifest(manifest, self.site)
        self.assertFalse(report["approved"])
        joined = " ".join(report["issues"])
        self.assertIn("too thin", joined)
        self.assertIn("metadata/template-heavy", joined)

    def test_missing_source_media_requirement_is_rejected(self) -> None:
        manifest = deepcopy(self.manifest)
        manifest["authentic_source_media_required"] = False
        report = evaluate_manifest(manifest, self.site)
        self.assertFalse(report["approved"])
        self.assertIn("authentic source media", " ".join(report["issues"]))

    def test_truncated_copy_is_rejected(self) -> None:
        manifest = deepcopy(self.manifest)
        manifest["article"]["compatibility_note"] += " before,"
        report = evaluate_manifest(manifest, self.site)
        self.assertFalse(report["approved"])
        self.assertIn("truncated", " ".join(report["issues"]))


if __name__ == "__main__":
    unittest.main()
