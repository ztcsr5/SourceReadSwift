"""Check the persisted raw-rule smoke and its provenance, without a native-pass claim."""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "SourceReadSwiftTests" / "Fixtures" / "bookshan"


class BookShanOriginalReplayTests(unittest.TestCase):
    def test_persisted_library_and_stage_rules_match_recorded_provenance(self):
        source = json.loads((FIXTURES / "source.json").read_text(encoding="utf-8"))
        provenance = json.loads((FIXTURES / "provenance.json").read_text(encoding="utf-8"))
        self.assertEqual(
            hashlib.sha256(source["jsLib"].encode()).hexdigest(),
            provenance["fixtureLibraryUTF8SHA256"],
        )
        for field, expected in provenance["originalRulesUTF8SHA256"].items():
            encoded = json.dumps(source[field], ensure_ascii=False, sort_keys=True, separators=(",", ":"))
            self.assertEqual(hashlib.sha256(encoded.encode()).hexdigest(), expected, field)
        self.assertEqual(source["bookSourceUrl"], "https://bookshan.fixture.invalid")
        self.assertNotIn("variable", source)
        self.assertNotIn("cookie", source)

    @unittest.skipUnless(shutil.which("node"), "Node is required for raw JavaScript replay")
    def test_original_novel_and_fanqie_rules_replay_with_synthetic_responses(self):
        for arguments, scenario in [((), "novel"), (("--fanqie",), "fanqie")]:
            with self.subTest(scenario=scenario):
                completed = subprocess.run(
                    ["node", "--permission", f"--allow-fs-read={FIXTURES / 'source.json'}",
                     str(ROOT / "scripts" / "replay_bookshan_original.cjs"), *arguments],
                    cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
                    timeout=15, check=True,
                )
                report = json.loads(completed.stdout)
                self.assertEqual(report["scenario"], scenario)
                self.assertEqual(report["assertions"], "passed")
                self.assertFalse(report["originalLibrary"])
                self.assertTrue(report["volumeURLIsEmpty"])
                self.assertTrue(report["subContentIsEmpty"])
                self.assertEqual(report["catalogEntries"], 3)
                self.assertEqual(
                    [request["path"] for request in report["requestShapes"]],
                    ["/details", "/catalog", "/content"],
                )
                self.assertIn("Node VM only", report["boundary"])


if __name__ == "__main__":
    unittest.main()
