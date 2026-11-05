"""Source/workflow isolation guards, not substitutes for native UI acceptance.

Usage: python -m unittest discover -s scripts -p test_floating_desk_scope.py
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FloatingDeskScopeTests(unittest.TestCase):
    def test_zoom_suspends_only_the_parent_pager_and_restores_it_on_dismantle(self):
        source = (ROOT / 'SourceReadSwift/Features/Reader/ComicPageZoomView.swift').read_text(encoding='utf8')
        begin = source.split("func scrollViewWillBeginZooming(", 1)[1].split("func scrollViewDidEndZooming", 1)[0]
        self.assertIn("suspendParentPaging(of: scrollView)", begin)
        self.assertIn("parent.isPagingEnabled", source)
        self.assertIn("parentWasScrollEnabled", source)
        teardown = source.split("static func dismantleUIView(", 1)[1].split("final class Coordinator", 1)[0]
        self.assertIn("coordinator.restoreParentPaging()", teardown)

    def test_continuous_cross_chapter_ui_checks_visible_prose_and_the_real_heading(self):
        ui = (ROOT / 'SourceReadSwiftUITests/FloatingReadingDeskUITests.swift').read_text(encoding='utf8')
        self.assertIn("for chapter in [3, 2, 1, 2, 3]", ui)
        self.assertIn("paragraph.frame.intersection(surface.frame)", ui)
        self.assertIn('element("reader.currentChapterHeading")', ui)
        self.assertIn('assertChapterAtViewportTop(3, surface: surface)', ui)
        workflow = (ROOT / '.github/workflows/ios.yml').read_text(encoding='utf8')
        self.assertIn("-only-testing:SourceReadSwiftUITests/FloatingReadingDeskUITests/testContinuousChapterCrossingKeepsProseHeadingAndReopenedPositionTogether", workflow)

    def test_comic_horizontal_ui_checks_both_directions_and_decoded_pages_at_boundaries(self):
        ui = (ROOT / 'SourceReadSwiftUITests/ComicPagingBoundaryUITests.swift').read_text(encoding='utf8')
        for required in ["checkTapBoundaries(rtl: false)", "checkTapBoundaries(rtl: true)",
                         "assertComicPage(chapter: 1, page: 6, app: app)",
                         "assertComicPage(chapter: 2, page: 6, app: app)",
                         'pager.images["漫画图片"]']:
            self.assertIn(required, ui)
        self.assertNotIn("sleep(", ui)

    def test_experimental_branch_never_packages_an_ipa(self):
        workflow = (ROOT / '.github/workflows/unsigned-ipa.yml').read_text(encoding='utf8')
        self.assertIn("if: github.ref != 'refs/heads/codex/floating-reading-desk'", workflow)
        dedicated = (ROOT / '.github/workflows/floating-desk.yml').read_text(encoding='utf8')
        self.assertNotIn('iphoneos', dedicated)
        self.assertNotIn('archivePath', dedicated)
        for expected in ['Xcode_16.4.app', 'Xcode_26.2.app', 'recordVideo --codec=h264', 'DeskUnit.xcresult', 'DeskUI.xcresult']:
            self.assertIn(expected, dedicated)

    def test_module_has_no_business_writes_or_continuous_render_loop(self):
        module = (ROOT / 'SourceReadSwift/Features/Bookshelf/FloatingReadingDesk.swift').read_text(encoding='utf8')
        for forbidden in ['Timer', 'TimelineView', 'CADisplayLink', 'DragGesture', 'updateReadingProgress', 'bookshelfStore']:
            self.assertNotIn(forbidden, module)
        for decoration in ['CoverToneSampler.shared.tone', 'LinearGradient', 'RadialGradient']:
            self.assertNotIn(decoration, module)
        self.assertIn('.bookHeroSource("continue|" + book.id', module)

    def test_old_style_remains_explicitly_available(self):
        card = (ROOT / 'SourceReadSwift/Features/Bookshelf/ReadingHeroCard.swift').read_text(encoding='utf8')
        self.assertIn('var usesFloatingStyle = false', card)
        self.assertIn('if usesSpatialStyle && usesFloatingStyle', card)
        shelf = (ROOT / 'SourceReadSwift/Features/Bookshelf/BookshelfView.swift').read_text(encoding='utf8')
        self.assertIn('Toggle("悬浮玻璃书台", isOn: $floatingReadingDeskEnabled)', shelf)

    def test_visual_effect_closure_returns_its_effect_after_local_geometry_calculation(self):
        style = (ROOT / 'SourceReadSwift/Features/Bookshelf/FloatingDeskStyle.swift').read_text(encoding='utf8')
        closure = style.split('content.visualEffect { effect, geometry in', 1)[1].split('} else', 1)[0]
        self.assertIn('let phase = Self.phase(geometry)', closure)
        self.assertIn('return effect.offset', closure)

    def test_offline_fixture_is_debug_only_and_requires_an_explicit_argument(self):
        launch = (ROOT / 'SourceReadSwift/App/ReaderRegressionLaunch.swift').read_text(encoding='utf8')
        self.assertGreater(launch.index('--floating-desk-regression'), launch.index('#if DEBUG'))
        fixture = (ROOT / 'SourceReadSwift/App/FloatingDeskRegressionLaunch.swift').read_text(encoding='utf8')
        self.assertIn('#if DEBUG', fixture)
        self.assertIn('temporaryDirectory', fixture)
        self.assertNotIn('URLSession', fixture)
        ui = (ROOT / 'SourceReadSwiftUITests/FloatingReadingDeskUITests.swift').read_text(encoding='utf8')
        self.assertNotIn('"-settings.floatingReadingDeskEnabled"', ui)

    def test_performance_metrics_observe_the_app_not_the_ui_test_runner(self):
        test = (ROOT / 'SourceReadSwiftUITests/FloatingReadingDeskUITests.swift').read_text(encoding='utf8')
        self.assertIn('XCTCPUMetric(application: app)', test)
        self.assertIn('XCTMemoryMetric(application: app)', test)

    def test_each_page_clips_its_displaced_caption_before_the_viewport(self):
        pager = (ROOT / 'SourceReadSwift/Features/Bookshelf/ReadingDeskPager.swift').read_text(encoding='utf8')
        self.assertIn('measuredCard(book).containerRelativeFrame(.horizontal).clipped().id(book.id)', pager)

    def test_full_suite_keeps_its_original_probe_environment_and_not_native_deadline(self):
        workflow = (ROOT / '.github/workflows/floating-desk.yml').read_text(encoding='utf8')
        self.assertIn('TEST_RUNNER_COMIC_CORPUS_PROBE: "1"', workflow)
        self.assertNotIn('DEADLINES=()', workflow)
        self.assertIn('COMMAND=(xcodebuild -project SourceReadSwift.xcodeproj', workflow)
        native = workflow.split('if [ "${{ matrix.name }}" = "liquid-glass" ]; then', 1)[1].split('fi', 1)[0]
        self.assertIn('COMMAND+=(-test-timeouts-enabled YES -maximum-test-execution-time-allowance 60)', native)
        self.assertIn('"${COMMAND[@]}" "${TESTS[@]}"', workflow)

    def test_revised_desk_removes_redundant_chrome_and_keeps_actual_context(self):
        module = (ROOT / 'SourceReadSwift/Features/Bookshelf/FloatingReadingDesk.swift').read_text(encoding='utf8')
        self.assertNotIn('Text(book.hasUpdates ? "有更新" : "续读")', module)
        self.assertNotIn('"作者未记录"', module)
        jacket = (ROOT / 'SourceReadSwift/Features/Bookshelf/EditorialBookJacket.swift').read_text(encoding='utf8')
        self.assertIn('EditorialBookJacket(height: height, palette: palette, stance: .shelf)', module)
        self.assertIn('rotation3DEffect(.degrees(stance == .shelf ? -9 : stance == .floating ? -12 : -5)', jacket)
        self.assertIn('rotationEffect(.degrees(stance == .shelf ? -3 : stance == .floating ? -4 : -2))', jacket)
        self.assertIn('ReadingDeskContent.contextLine(for: book)', module)
        fixture = (ROOT / 'SourceReadSwift/App/FloatingDeskRegressionLaunch.swift').read_text(encoding='utf8')
        self.assertNotIn('离线验收样本', fixture)
        self.assertNotIn('纸间 · 离线视觉验收', fixture)
        pager = (ROOT / 'SourceReadSwift/Features/Bookshelf/ReadingDeskPager.swift').read_text(encoding='utf8')
        self.assertIn('if !usesFloatingStyle {\n                        Text("最近阅读', pager)

    def test_ui_flow_is_split_without_removing_navigation_or_cancel_assertions(self):
        ui = (ROOT / 'SourceReadSwiftUITests/FloatingReadingDeskUITests.swift').read_text(encoding='utf8')
        for name in ['testWhiteVioletPagingAndCancelledDragInTheRealApp', 'testReadingDeskDetailsAndReturnInTheRealApp', 'testReadingDeskReaderAndReturnInTheRealApp']:
            self.assertIn(name, ui)
        self.assertIn('thenHoldForDuration: 0.3', ui)
        self.assertIn('Returning to the real shelf must restore navigation with it', ui)
        self.assertNotIn('app.staticTexts["最近阅读 · 1 / 3"]', ui)


if __name__ == '__main__':
    unittest.main()
