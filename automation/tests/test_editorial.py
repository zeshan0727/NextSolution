from pathlib import Path
import unittest

from automation.editorial import (
    NoCandidateError,
    build_candidates,
    classify_category,
    load_json,
    mark_candidate_drafted,
    select_candidate,
    slugify,
)


AUTOMATION = Path("automation")
FIXTURES = AUTOMATION / "tests" / "fixtures"


class EditorialTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.categories = load_json(AUTOMATION / "categories.json")
        cls.site = load_json(AUTOMATION / "site.json")
        cls.state = load_json(FIXTURES / "editorial-state.json")

    def test_slugify_is_path_safe(self) -> None:
        self.assertEqual(slugify("Fócus Cards 2.0!"), "focus-cards-2-0")

    def test_home_screen_category_comes_from_facts(self) -> None:
        item = next(iter(self.state["pending"].values()))
        category = classify_category(item, self.categories)
        self.assertEqual(category["id"], "home-screen")

    def test_unknown_category_uses_system_utilities_fallback(self) -> None:
        category = classify_category(
            {"name": "Opaque Package", "description": "Provides a configurable helper."},
            self.categories,
        )
        self.assertEqual(category["id"], "system-utilities")

    def test_architecture_variants_become_one_candidate(self) -> None:
        candidates = build_candidates(
            self.state["pending"].values(), self.categories, self.site
        )
        self.assertEqual(len(candidates), 1)
        self.assertEqual(
            candidates[0]["architectures"], ["iphoneos-arm64", "iphoneos-arm64e"]
        )
        self.assertEqual(candidates[0]["slug"], "focus-cards-tweak")
        self.assertEqual(len(candidates[0]["release_identities"]), 2)
        self.assertEqual(len(candidates[0]["variants"]), 2)

    def test_select_candidate_rejects_empty_queue(self) -> None:
        with self.assertRaises(NoCandidateError):
            select_candidate({"pending": {}}, self.categories, self.site)

    def test_marking_candidate_covers_every_architecture_variant(self) -> None:
        state = load_json(FIXTURES / "editorial-state.json")
        candidate = select_candidate(state, self.categories, self.site)
        mark_candidate_drafted(
            state,
            candidate,
            drafted_at="2026-08-12T01:00:00+00:00",
            draft_target="focus-cards-tweak.html",
            candidate_fingerprint="abc123",
        )
        self.assertTrue(all(item.get("drafted_at") for item in state["pending"].values()))
        with self.assertRaises(NoCandidateError):
            select_candidate(state, self.categories, self.site)


if __name__ == "__main__":
    unittest.main()
