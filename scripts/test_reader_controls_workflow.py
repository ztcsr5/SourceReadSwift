"""Keep CI setup budgets separate from product deadlines and preserve every suite.

Usage: python -m unittest discover -s scripts -p test_reader_controls_workflow.py
"""
from pathlib import Path
import re
import unittest


WORKFLOW = Path(__file__).resolve().parents[1] / '.github/workflows/ios.yml'


class WorkflowRunNameTests(unittest.TestCase):
    def test_run_titles_state_the_project_version_build_and_purpose(self):
        root = WORKFLOW.parents[2]
        project = (root / 'project.yml').read_text(encoding='utf8')
        version = re.search(r'MARKETING_VERSION: "([^"]+)"', project).group(1)
        build = re.search(r'CURRENT_PROJECT_VERSION: "([^"]+)"', project).group(1)
        for filename, purpose in [('unsigned-ipa.yml', 'IPA 未签名测试包'),
                                  ('ios.yml', 'iOS 完整验证'),
                                  ('floating-desk.yml', 'UI 专项（无 IPA）')]:
            with self.subTest(workflow=filename):
                workflow = (WORKFLOW.parent / filename).read_text(encoding='utf8')
                title = re.search(r'^run-name: (.+)$', workflow, re.M)
                self.assertIsNotNone(title, 'Do not use the commit message as the release identity')
                self.assertIn(f'{version} · Build {build}', title.group(1))
                self.assertIn(purpose, title.group(1))
                self.assertIn('github.run_number', title.group(1))

    def test_ipa_filename_includes_build_and_commit_without_changing_artifact_contract(self):
        workflow = (WORKFLOW.parent / 'unsigned-ipa.yml').read_text(encoding='utf8')
        filename = 'SourceReadSwift-${VERSION}-build${BUILD}-${SHORT_SHA}-unsigned.ipa'
        self.assertEqual(workflow.count(filename), 2, 'Packaging and summary must identify the same IPA')
        self.assertIn('name: SourceReadSwift-unsigned-ipa', workflow)
        self.assertIn('echo "- commit: \\`', workflow)


class ReaderControlsWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.native = WORKFLOW.read_text(encoding='utf8').split('  native-tabs:', 1)[1].split('  build:', 1)[0]

    def step(self, name):
        marker = '      - name: ' + name + '\n'
        self.assertIn(marker, self.native)
        return self.native.split(marker, 1)[1].split('      - name:', 1)[0]

    def test_boot_and_compilation_do_not_consume_the_product_runtime_budget(self):
        boot = self.step('Boot iOS26 simulator')
        build = self.step('Build iOS26 tests')
        runtime = self.step('iOS26 native tab runtime regression')
        self.assertIn('boot_native_simulator.py', boot)
        self.assertIn('build-for-testing', build)
        self.assertNotIn('boot_native_simulator.py', runtime)
        self.assertIn('test-without-building', runtime)
        self.assertIn('-maximum-test-execution-time-allowance 60', runtime)

    def test_all_original_native_product_suites_remain_selected(self):
        expected = '''TabChromeRegressionTests ReaderCoverTeardownTests AppLayoutDensityTests SourceOrganizationTests
            ReaderTocPerformanceTests ContentImagePipelineRegressionTests RemoteComicImageTests AppFrameProfilerTests
            Release116VisualTests ReaderModePositionRegressionTests Release117DetailTests Release117ComicCompatibilityTests
            Release117AppearanceTests Release117SearchProjectionTests Release117ChromeTests WebsiteSourceInferenceTests
            WebsiteSourceFamilyInferenceTests AIChatTests Release117PurificationTests LANWorkbenchTests ReadingNotesNavigationTests
            Release117ThemeCollaborationTests Release117ReaderPersonalizationTests Release117WallpaperEditorTests
            Release117ReadingHeroTests Release117MotionSystemTests Release117PolishTests ReaderSettingsStackTests
            FontImportRequestTests ReaderScrollCadenceTests ReaderBindingTests ReaderWorkbenchVisualTests
            ReaderControlsMaterialTests ReaderTabChromeExitTests ReaderPanController119Tests'''.split()
        actual = re.findall(r'-only-testing:SourceReadSwiftTests/(\w+)', self.step('iOS26 native tab runtime regression'))
        self.assertEqual(set(actual), set(expected))

    def test_multi_screen_ui_flows_have_their_own_bounded_budget_not_longer_product_deadlines(self):
        ui = self.step('Exercise real reader settings UI on iOS26')
        self.assertIn('test-without-building', ui)
        self.assertIn('-only-testing:SourceReadSwiftUITests/ReaderSettingsFlowUITests', ui)
        self.assertIn('-maximum-test-execution-time-allowance 180', ui)
        self.assertIn('timeout-minutes: 15', ui)
        self.assertNotIn('-only-testing:SourceReadSwiftTests/', ui)

    def test_unit_and_ui_results_and_attempt_artifacts_are_preserved_separately(self):
        self.assertIn('NativeTabResults.xcresult', self.native)
        self.assertIn('NativeReaderUIResults.xcresult', self.native)
        export = self.step('Export iOS26 attachments')
        self.assertIn('--output-path native-ui-snapshots/unit', export)
        self.assertIn('--output-path native-ui-snapshots/reader', export)
        for name in ['Preserve iOS26 runtime evidence', 'Preserve compact iOS26 UI snapshots']:
            self.assertIn('github.run_attempt', self.step(name))


if __name__ == '__main__':
    unittest.main()
