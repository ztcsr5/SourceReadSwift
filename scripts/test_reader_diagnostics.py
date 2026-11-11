"""Guard focused feedback without accepting it as a complete release gate.
Usage: python -m unittest discover -s scripts -p test_reader_diagnostics.py
"""
from pathlib import Path
import unittest
import subprocess
import tempfile
import io
import json
import zipfile
from unittest.mock import patch
import verify_reader_quality as quality
import verify_reader_diagnostics as diagnostics
from verify_reader_diagnostics import materialize_focused_tree
from deliver_reader_quality import require_native_steps
from verify_reader_diagnostics import failure_lines, collect_early_unit
ROOT = Path(__file__).resolve().parents[1]
class ReaderDiagnosticsTests(unittest.TestCase):
    def test_early_feedback_selects_ios26_even_when_ios18_uploaded_first(self):
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, "w") as bundle:
            bundle.writestr("diagnostic-unit.log", "Fixture.swift:17: error: viewport failed\n")
        artifacts = [
            {"id": 18, "name": "reader-diag-unit-sha-ios18-attempt1", "expired": False},
            {"id": 26, "name": "reader-diag-unit-sha-ios26-attempt1", "expired": False},
        ]
        with tempfile.TemporaryDirectory() as folder, patch.object(quality, "EVIDENCE", Path(folder)), \
                patch.object(quality, "github") as github:
            github.api.return_value = {"artifacts": artifacts}
            github.signed_download.return_value = archive.getvalue()
            report = collect_early_unit(1, {"head": "sha"})
            github.signed_download.assert_called_once_with("actions/artifacts/26/zip")
            self.assertEqual(report["runtime"], "26")
            self.assertEqual(report["failures"], ["Fixture.swift:17: error: viewport failed"])
            self.assertEqual(Path(report["path"]).read_text(), "Fixture.swift:17: error: viewport failed\n")

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
        self.assertIn("max-parallel: 1", workflow)
        self.assertIn("inputs.navigation_only && !inputs.ios26_only", workflow)
        self.assertIn("-only-testing:SourceReadSwiftUITests/FloatingReadingDeskUITests/testReaderShortDefaultSpeedEdgeDragCancels", workflow)
        self.assertIn("-only-testing:SourceReadSwiftUITests/ReaderOverlayCycleUITests", workflow)
        self.assertIn("-maximum-test-execution-time-allowance 60", workflow)
        self.assertIn("-maximum-test-execution-time-allowance 180", workflow)

    def test_runtime_specific_dispatch_has_its_own_receipt_and_input(self):
        with tempfile.TemporaryDirectory() as folder, \
                patch.object(quality, "EVIDENCE", Path(folder)), \
                patch.object(quality, "snapshot_tree", return_value=("full", [diagnostics.TEMPLATE])), \
                patch.object(quality, "run_git", side_effect=["base", "f" * 40, ""]), \
                patch.object(diagnostics, "materialize_focused_tree", return_value="focused"), \
                patch.object(diagnostics, "read_diagnostics_status", return_value=[]), \
                patch.object(diagnostics, "persist_diagnostic") as persist, \
                patch.object(diagnostics.urllib.request, "urlopen") as open_dispatch:
            open_dispatch.return_value.__enter__.return_value.status = 204
            snapshot = diagnostics.snapshot_diagnostics(ios26_only=True)
            request = open_dispatch.call_args.args[0]
            self.assertEqual(json.loads(request.data)["inputs"], {"ios26_only": True, "zoom_experiment": False})
            self.assertEqual(persist.call_args.args[1].name, "diagnostic-focused-ios26.json")
            self.assertFalse(snapshot["dispatch_pending"])
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
