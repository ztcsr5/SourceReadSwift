"""Source/workflow isolation guards, not substitutes for native UI acceptance.

Usage: python -m unittest discover -s scripts -p test_floating_desk_scope.py
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FloatingDeskScopeTests(unittest.TestCase):
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
        self.assertIn('CoverToneSampler.shared.tone', module)
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


if __name__ == '__main__':
    unittest.main()
