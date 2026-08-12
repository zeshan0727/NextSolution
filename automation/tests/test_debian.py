from pathlib import Path
import unittest

from automation.debian import compare_versions, newest, parse_control


FIXTURE = Path(__file__).parent / "fixtures" / "Packages"


class ControlParserTests(unittest.TestCase):
    def test_parses_paragraphs_and_continuations(self) -> None:
        records = parse_control(FIXTURE.read_text(encoding="utf-8"))
        self.assertEqual(len(records), 3)
        self.assertEqual(records[0]["package"], "com.example.focuscards")
        self.assertIn("per-page spacing", records[0]["description"])
        self.assertIn("\n\nSettings", records[0]["description"])

    def test_debian_version_ordering(self) -> None:
        ordered = ["1.0~beta1", "1.0", "1.0-1", "1.0-2", "1:0.1"]
        for lower, higher in zip(ordered, ordered[1:]):
            self.assertLess(compare_versions(lower, higher), 0)
            self.assertGreater(compare_versions(higher, lower), 0)
        self.assertEqual(compare_versions("1.02", "1.2"), 0)

    def test_selects_newest(self) -> None:
        record = newest([{"version": "1.0~rc1"}, {"version": "1.0"}, {"version": "0.9"}])
        self.assertEqual(record["version"], "1.0")


if __name__ == "__main__":
    unittest.main()
