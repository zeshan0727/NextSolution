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
        sentence = (
            "This section explains the practical behavior a reader can verify, why the detail matters on a jailbroken device, "
            "what limitation to keep in mind, and which source fact supports the explanation before installation. "
        )
        self.article = {
            "summary": sentence * 3,
            "what_it_does": [sentence * 2 for _ in range(5)],
            "compatibility_note": sentence * 3,
            "installation_steps": [sentence * 2 for _ in range(5)],
            "safety_notes": [sentence * 2 for _ in range(3)],
            "faq": [
                {"question": f"Useful question {index}?", "answer": sentence * 4 + f" Answer focus {index}."}
                for index in range(4)
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
        manifest["article"]["what_it_does"] = [
            "Review the supplied package facts and listed architectures."
        ] * 5
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
