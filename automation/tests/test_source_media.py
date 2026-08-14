import json
from pathlib import Path
import tempfile
import unittest

from automation.source_media import (
    SourceMediaError,
    is_safe_media_reference,
    load_source_media,
    resolve_source_media,
    _validate_record,
)


class SourceMediaTests(unittest.TestCase):
    def test_curated_catalog_contains_only_trusted_media(self) -> None:
        packages = load_source_media(Path("automation/source-media.json"))
        self.assertGreaterEqual(len(packages), 8)
        for package, record in packages.items():
            with self.subTest(package=package):
                validated = _validate_record(record)
                self.assertTrue(is_safe_media_reference(validated["hero"]["url"]))
                self.assertTrue(validated["credit_label"])

    def test_untrusted_remote_media_is_rejected(self) -> None:
        with self.assertRaises(SourceMediaError):
            _validate_record(
                {
                    "credit_label": "Untrusted example",
                    "source_page_url": "https://example.com/package",
                    "official_source": False,
                    "hero": {
                        "url": "https://example.com/generated.jpg",
                        "alt": "A sufficiently descriptive fake screenshot",
                    },
                    "screenshots": [],
                }
            )

    def test_curated_package_resolves_without_network_access(self) -> None:
        record = {
            "credit_label": "Developer official listing",
            "source_page_url": "https://example.com/package",
            "official_source": True,
            "hero": {
                "url": "assets/articles/real-package-shot.jpg",
                "alt": "Real package feature screenshot",
            },
            "screenshots": [],
        }
        with tempfile.TemporaryDirectory() as directory:
            catalog = Path(directory) / "source-media.json"
            catalog.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "packages": {"com.example.real": record},
                    }
                ),
                encoding="utf-8",
            )
            resolved = resolve_source_media(
                {"package": "com.example.real", "name": "Real"},
                catalog_path=catalog,
                source_page_url="https://example.com/package",
            )
            self.assertEqual(
                resolved["hero"]["url"],
                "assets/articles/real-package-shot.jpg",
            )


if __name__ == "__main__":
    unittest.main()
