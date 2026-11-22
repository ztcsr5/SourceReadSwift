"""Keep the opt-in cover wash shared and off the scrolling render path."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CoverGlassThemeTests(unittest.TestCase):
    def test_real_bitmap_check_awaits_preparation_not_a_poll_iteration_budget(self):
        native = (ROOT / 'SourceReadSwiftTests/CoverGlassThemeTests.swift').read_text(encoding='utf-8')
        actual = native.split('func testActualRenderer', 1)[1].split('func testDisabledThemes', 1)[0]
        self.assertEqual(actual.count('await CoverGlassBackdropStore.preparedImage(for: url)'), 2)
        self.assertNotIn('waitUntil', actual)
        self.assertIn('XCTAssertLessThanOrEqual(max(pixels.width, pixels.height), 96)', actual)
        self.assertIn('XCTAssertNotEqual(prepared.pngData(), original.pngData())', actual)
        self.assertIn('XCTAssertTrue(cached === prepared', actual)

    def test_theme_is_independent_and_only_fresh_installs_get_both_defaults(self):
        theme = (ROOT / 'SourceReadSwift/Shared/DesignSystem/AppVisualTheme.swift').read_text(encoding='utf-8')
        self.assertIn('case coverGlass', theme)
        self.assertIn('static let initialSelection: Self = .forest', theme)
        self.assertIn('HomeBookPresentation.bootstrapSelection', theme)
        presentation = (ROOT / 'SourceReadSwift/Features/Bookshelf/HomeBookPresentation.swift').read_text(encoding='utf-8')
        self.assertIn('isExistingInstall ? Self.classic : Self.showcase', presentation)

    def test_each_page_uses_one_cached_bitmap_without_live_blur(self):
        paper = (ROOT / 'SourceReadSwift/Shared/DesignSystem/AppTheme.swift').read_text(encoding='utf-8')
        self.assertIn('if theme == .coverGlass', paper)
        self.assertIn('CoverGlassBackdrop()', paper)
        backdrop = (ROOT / 'SourceReadSwift/Shared/DesignSystem/CoverGlassBackdrop.swift').read_text(encoding='utf-8')
        self.assertIn('private actor CoverGlassRenderer', backdrop)
        self.assertIn('maxPixelSize: 96', backdrop)
        self.assertIn('cache.countLimit = 4', backdrop)
        self.assertIn('CIGaussianBlur', backdrop)
        self.assertNotIn('.blur(', backdrop)
        self.assertNotIn('CADisplayLink', backdrop)
        self.assertNotIn('Timer', backdrop)

    def test_switching_tabs_does_not_recreate_or_resample_background(self):
        root = (ROOT / 'SourceReadSwift/App/RootTabView.swift').read_text(encoding='utf-8')
        self.assertIn('CoverGlassBackdropStore.shared.setEnabled(edition == .coverGlass)', root)
        home = (ROOT / 'SourceReadSwift/Features/Bookshelf/BookshelfView.swift').read_text(encoding='utf-8')
        self.assertIn('.task(id: activeHomeCoverURL)', home)
        self.assertIn('CoverGlassBackdropStore.shared.setSource(activeHomeCoverURL)', home)
        self.assertIn('theme != .coverGlass', home)


if __name__ == '__main__':
    unittest.main()
