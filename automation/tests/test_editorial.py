import copy
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

    def test_non_ascii_only_name_does_not_stop_other_candidates(self) -> None:
        valid = copy.deepcopy(next(iter(self.state["pending"].values())))
        unsluggable = copy.deepcopy(valid)
        unsluggable["package"] = "com.example.symbols"
        unsluggable["identity"] = "com.example.symbols|iphoneos-arm64"
        unsluggable["release_identity"] = "com.example.symbols|1.2.0|iphoneos-arm64"
        unsluggable["name"] = "中文"
        candidates = build_candidates(
            [unsluggable, valid], self.categories, self.site
        )
        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0]["package"], "com.example.focuscards")

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
            select_candidate(
                {"pending": {}, "evergreen": {}}, self.categories, self.site
            )

    def test_pending_release_has_priority_over_evergreen(self) -> None:
        state = copy.deepcopy(self.state)
        evergreen_item = copy.deepcopy(next(iter(state["pending"].values())))
        evergreen_item["package"] = "com.example.evergreen"
        evergreen_item["identity"] = "com.example.evergreen|iphoneos-arm64"
        evergreen_item["release_identity"] = (
            "com.example.evergreen|1.2.0|iphoneos-arm64"
        )
        state["evergreen"] = {evergreen_item["release_identity"]: evergreen_item}
        candidate = select_candidate(state, self.categories, self.site)
        self.assertEqual(candidate["selection_pool"], "pending")
        self.assertEqual(candidate["package"], "com.example.focuscards")

    def test_new_page_selection_excludes_existing_packages(self) -> None:
        state = copy.deepcopy(self.state)
        new_item = copy.deepcopy(next(iter(state["pending"].values())))
        new_item["package"] = "com.example.newpage"
        new_item["identity"] = "com.example.newpage|iphoneos-arm64"
        new_item["release_identity"] = "com.example.newpage|1.2.0|iphoneos-arm64"
        state["pending"][new_item["release_identity"]] = new_item

        candidate = select_candidate(
            state,
            self.categories,
            self.site,
            excluded_packages={"com.example.focuscards"},
        )
        self.assertEqual(candidate["package"], "com.example.newpage")

    def test_evergreen_is_used_when_release_queue_is_empty(self) -> None:
        state = copy.deepcopy(self.state)
        state["evergreen"] = state.pop("pending")
        state["pending"] = {}
        candidate = select_candidate(state, self.categories, self.site)
        self.assertEqual(candidate["selection_pool"], "evergreen")
        self.assertEqual(candidate["slug"], "focus-cards-tweak")

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

    def test_marking_release_updates_both_editorial_pools(self) -> None:
        state = copy.deepcopy(self.state)
        state["evergreen"] = copy.deepcopy(state["pending"])
        candidate = select_candidate(state, self.categories, self.site)
        mark_candidate_drafted(
            state,
            candidate,
            drafted_at="2026-08-12T01:00:00+00:00",
            draft_target="focus-cards-tweak.html",
            candidate_fingerprint="abc123",
        )
        for pool_name in ("pending", "evergreen"):
            self.assertTrue(
                all(item.get("drafted_at") for item in state[pool_name].values())
            )


if __name__ == "__main__":
    unittest.main()
