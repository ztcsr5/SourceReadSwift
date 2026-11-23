"""Verify accounting without contacting a source or running its scripts."""
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from inspect_source_inventory import inspect_sources, merge_native_passes, stage_native_inputs
from prepare_private_source_corpus import sha256


class SourceInventoryTests(unittest.TestCase):
    def test_live_gate_rejects_a_stale_sha_and_does_not_count_url_extraction(self):
        with TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "books.json"
            source.write_text('[{"bookSourceType":4},{"bookSourceType":2}]', encoding="utf8")
            inventory = inspect_sources([source])
            revision = "a" * 40
            stages = [{"stage": step, "status": "passed"} for step in ("search", "detail", "toc", "content")]
            file_sha = inventory["files"][0]["sha256"]
            rows = [
                {"fileId": "sources-01", "index": 0, "fileSHA": file_sha, "status": "mediaExtracted",
                 "resolvedMediaKind": 3, "stages": stages},
                {"fileId": "sources-01", "index": 1, "fileSHA": file_sha, "status": "passed",
                 "resolvedMediaKind": 2, "stages": stages, "imageSampleDecoded": [True, True]},
            ]
            receipt = root / "native.json"
            report = {"mode": "live", "revision": revision, "rows": rows}
            receipt.write_text(json.dumps(report), encoding="utf8")
            with self.assertRaises(ValueError):
                merge_native_passes(inventory, [receipt], "b" * 40)
            merge_native_passes(inventory, [receipt], revision)
            self.assertEqual(inventory["endToEndPassed"], 1)
            self.assertFalse(inventory["releaseGatePassed"])
            rows[0].update(status="passed", playbackVerified=True,
                           stages=stages + [{"stage": "media-playback", "status": "passed"}])
            receipt.write_text(json.dumps(report), encoding="utf8")
            merge_native_passes(inventory, [receipt], revision)
            self.assertEqual(inventory["endToEndPassed"], 2)
            self.assertTrue(inventory["releaseGatePassed"])

    def test_canonical_duplicates_do_not_hide_a_different_revision_or_inflate_passes(self):
        with TemporaryDirectory() as folder:
            root = Path(folder)
            source = {"bookSourceUrl": "https://fixture.invalid", "bookSourceType": 4,
                      "ruleContent": {"content": "@js:neverRun()"}}
            changed = dict(source, ruleContent={"content": "$.data.sources"})
            first = root / "first.json"
            second = root / "second.json"
            first.write_text(json.dumps([source, changed]), encoding="utf8")
            second.write_text(json.dumps([dict(reversed(tuple(source.items())))]), encoding="utf8")
            inventory = inspect_sources([first, second])
            self.assertEqual(inventory["totalRows"], 3)
            self.assertEqual(inventory["uniqueDefinitions"], 2)
            self.assertEqual(inventory["minimumPasses"], 2)
            self.assertEqual(inventory["endToEndPassed"], 0)
            self.assertEqual(inventory["hasScript"], 1)
            self.assertEqual(inventory["declaredTypes"], {"4": 2})
            self.assertNotIn("fixture.invalid", json.dumps(inventory))
            self.assertNotIn("neverRun", json.dumps(inventory))
            self.assertEqual(sorted(len(entry["occurrences"]) for entry in inventory["definitions"].values()), [1, 2])

            staging = root / "native"
            stage_native_inputs([first, second], inventory, staging)
            manifest = json.loads((staging / "manifest.json").read_bytes())
            self.assertEqual(manifest["totalRecords"], 3)
            self.assertEqual(manifest["files"][1]["expectedCount"], 1)
            self.assertEqual(manifest["files"][1]["sha256"], sha256(second.read_bytes()))
            self.assertEqual((staging / "sources-02.json").read_bytes(), second.read_bytes())


if __name__ == "__main__":
    unittest.main()
