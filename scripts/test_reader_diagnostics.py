"""Guard focused feedback without accepting it as a complete release gate.
Usage: python -m unittest discover -s scripts -p test_reader_diagnostics.py
"""
from pathlib import Path
import unittest
import subprocess
import tempfile
from unittest.mock import patch
import verify_reader_quality as quality
from verify_reader_diagnostics import materialize_focused_tree
from deliver_reader_quality import require_native_steps
from verify_reader_diagnostics import failure_lines
ROOT = Path(__file__).resolve().parents[1]
class ReaderDiagnosticsTests(unittest.TestCase):
    def test_focused_job_cannot_start_on_every_push_or_package_an_ipa(self):
        workflow = (ROOT / ".github/workflows/reader-diagnostics.yml").read_text(encoding="utf8")
        self.assertIn("workflow_dispatch:", workflow)
        self.assertNotIn("  push:", workflow)
        self.assertNotIn("unsigned-ipa", workflow)
        self.assertIn("非 IPA 门禁", workflow)
        for case in ["testReaderSystemReturnCanCancelWithoutLosingItsSavedParagraph",
                     "testReaderSystemReturnCanCancelWithReducedMotion",
                     "testReaderLongEdgeReturnCompletesWithReducedMotion",
                     "testHomeGlobalSearchOnlyFindsAppFunctions",
                     "testContinuousChapterCrossingKeepsProseHeadingAndReopenedPositionTogether"]:
            self.assertIn(case, workflow)
        self.assertIn("ComicPagingBoundaryUITests", workflow)
        self.assertIn("-maximum-test-execution-time-allowance 60", workflow)
        self.assertIn("-maximum-test-execution-time-allowance 180", workflow)
    def test_failure_extraction_retains_assertions_without_exposing_urls(self):
        failure = b"Fixture.swift:39: error: XCTAssert failed https://fixture.invalid/private?token=not-real\nnormal line"
        self.assertEqual(failure_lines(failure), ["Fixture.swift:39: error: XCTAssert failed [url]"])
    def test_execution_failure_and_runner_restart_are_not_reported_as_no_failures(self):
        failure = b"Restarting after unexpected exit, crash, or test timeout\n** TEST EXECUTE FAILED **"
        self.assertEqual(failure_lines(failure), failure.decode().splitlines())
    def test_focused_green_job_cannot_pass_complete_release_requirements(self):
        with self.assertRaisesRegex(RuntimeError, "Native job build has not passed"):
            require_native_steps([{"name": "focused-ios26", "conclusion": "success", "steps": []}])

    def test_real_snapshot_includes_untracked_template_without_changing_index_or_full_workflow(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            workflow = root / ".github/workflows/ios.yml"
            workflow.parent.mkdir(parents=True)
            workflow.write_text("name: Full validation\n", encoding="utf8")
            def git(*arguments):
                return subprocess.check_output(["git", *arguments], cwd=root, stderr=subprocess.STDOUT)
            git("init", "-q")
            git("add", ".github/workflows/ios.yml")
            git("-c", "user.name=SnapshotTest", "-c", "user.email=snapshot@test.invalid", "commit", "-qm", "test: baseline")
            template = root / ".github/workflows/reader-diagnostics.yml"
            template.write_text("name: Focused validation\n", encoding="utf8")
            original_index = (root / ".git/index").read_bytes()
            with patch.object(quality, "ROOT", root), patch.object(quality, "EVIDENCE", root / "evidence"):
                tree, selected = quality.snapshot_tree()
                self.assertIn(".github/workflows/reader-diagnostics.yml", selected)
                focused = materialize_focused_tree(tree)
                self.assertEqual(git("show", focused + ":.github/workflows/ios.yml"), template.read_bytes())
            self.assertEqual(workflow.read_text(encoding="utf8"), "name: Full validation\n")
            self.assertEqual((root / ".git/index").read_bytes(), original_index)
