"""Keep native verification snapshots complete without mixing unrelated dirty documents.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_reader_quality_snapshot.py
"""
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from verify_reader_quality import dispatch_snapshot, select_reader_paths


class ReaderQualitySnapshotTests(unittest.TestCase):
    def test_failed_dispatch_preserves_pushed_identity_for_reconciliation(self):
        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory) / "tree.json"
            record = {"head": "commit", "branch": "check/test"}
            with patch("verify_reader_quality.github", SimpleNamespace(REPO="owner/repo", HEADERS={})), \
                 patch("verify_reader_quality.urllib.request.urlopen", side_effect=OSError("TLS EOF")):
                with self.assertRaisesRegex(OSError, "TLS EOF"):
                    dispatch_snapshot(record, receipt)
            expected = record | {"dispatch_pending": True}
            self.assertEqual(json.loads(receipt.read_text(encoding="utf8")), expected)
            self.assertEqual(json.loads((receipt.parent / "LATEST.json").read_text(encoding="utf8")), expected)

    def test_new_regression_dependencies_are_kept_with_their_tests(self):
        expected = [
            "docs/sources/uxx-aggregate-compatible.json",
            "scripts/prepare_model_image.py",
            "scripts/test_aggregate_source_config.py",
            "scripts/test_model_image_limit.py",
            "scripts/verify_reader_quality.py",
        ]
        self.assertEqual(select_reader_paths(expected + ["scripts/test_cache.py.bak", "scripts/__pycache__/test.pyc"]), expected)

    def test_document_type_configuration_is_verified_with_the_implementation(self):
        self.assertEqual(select_reader_paths(["project.yml", "project.yml.bak114", "SourceReadSwift/App/Info.plist"]),
                         ["SourceReadSwift/App/Info.plist", "project.yml"])

    def test_packaging_trigger_guard_is_kept_in_native_snapshots(self):
        self.assertEqual(select_reader_paths([".github/workflows/unsigned-ipa.yml"]),
                         [".github/workflows/unsigned-ipa.yml"])

    def test_sources_unit_and_ui_tests_are_included_but_documents_and_backups_are_not(self):
        expected = [
            ".github/workflows/ios.yml",
            "SourceReadSwift/Features/Reader/ComicStripReaderView.swift",
            "SourceReadSwiftTests/ComicStripLayoutTests.swift",
            "SourceReadSwiftUITests/ComicReaderFlowUITests.swift",
            "scripts/test_reader_controls_workflow.py",
        ]
        candidates = expected + [
            "CHANGELOG.md", "docs/release-1.1.7/RECOVERY.md",
            "SourceReadSwift/Features/Reader/ReaderView.swift.bak114", "secret.swift",
        ]
        self.assertEqual(select_reader_paths(candidates), expected)


if __name__ == "__main__":
    unittest.main()
