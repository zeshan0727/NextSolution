import copy
from pathlib import Path
import unittest

from automation.editorial import build_candidates, load_json


AUTOMATION = Path("automation")
FIXTURES = AUTOMATION / "tests" / "fixtures"


class TrafficRankingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.categories = load_json(AUTOMATION / "categories.json")
        cls.site = load_json(AUTOMATION / "site.json")
        cls.state = load_json(FIXTURES / "editorial-state.json")

    def _variant(self, *, package: str, name: str, description: str) -> dict:
        item = copy.deepcopy(next(iter(self.state["pending"].values())))
        item["package"] = package
        item["name"] = name
        item["description"] = description
        item["identity"] = f"{package}|iphoneos-arm64"
        item["release_identity"] = f"{package}|{item['version']}|iphoneos-arm64"
        item["architecture"] = "iphoneos-arm64"
        return item

    def test_audience_priority_breaks_equal_technical_tie(self) -> None:
        niche = self._variant(
            package="com.example.diagnostics",
            name="Terminal Diagnostics",
            description="A command line CLI diagnostics utility for device information.",
        )
        audience = self._variant(
            package="com.example.dopaminecontrol",
            name="Dopamine Control Center",
            description=(
                "A rootless jailbreak tweak for Dopamine that customizes Control Center."
            ),
        )

        candidates = build_candidates(
            [niche, audience], self.categories, self.site
        )

        self.assertEqual(candidates[0]["package"], "com.example.dopaminecontrol")
        self.assertGreater(candidates[0]["audience_score"], candidates[1]["audience_score"])
        self.assertEqual(
            candidates[0]["score"],
            candidates[0]["base_score"] + candidates[0]["audience_score"],
        )

    def test_traffic_ranking_can_be_disabled_without_changing_base_score(self) -> None:
        item = self._variant(
            package="com.example.dopaminehelper",
            name="Dopamine Helper",
            description="A rootless jailbreak helper for Dopamine.",
        )
        disabled_site = copy.deepcopy(self.site)
        disabled_site["traffic_ranking"]["enabled"] = False

        candidate = build_candidates(
            [item], self.categories, disabled_site
        )[0]

        self.assertEqual(candidate["audience_score"], 0)
        self.assertEqual(candidate["score"], candidate["base_score"])


if __name__ == "__main__":
    unittest.main()
