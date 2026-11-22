"""Guard the new theme scope without claiming native SwiftUI validation.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_atelier_redesign.py
"""
from pathlib import Path
import re
import subprocess
import unittest

import yaml

from verify_atelier_quality import BASE, build_tree

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / 'SourceReadSwift/Shared/DesignSystem'


class AtelierRedesignTests(unittest.TestCase):
    def test_atelier_pages_and_cards_do_not_paint_repeating_edge_marks(self):
        ornament = (DESIGN / 'AppThemeOrnament.swift').read_text(encoding='utf8')
        self.assertIn('if theme.isAtelier { return false }', ornament)
        pigments = (DESIGN / 'AppAtelierTheme.swift').read_text(encoding='utf8')
        self.assertNotIn('var needles = Path()', pigments)
        self.assertNotIn('struct AppAtelierImprint', pigments)

    def test_new_themes_do_not_inherit_monospace_or_serif_body_fonts(self):
        theme = (DESIGN / 'AppVisualTheme.swift').read_text(encoding='utf8')
        body_font = theme.split('var fontDesign:')[1].split('var ornament:')[0]
        self.assertNotIn('.kleinSage', body_font)
        self.assertNotIn('.classic', body_font)
        self.assertIn('static let initialSelection: Self = .forest', theme)

    def test_gallery_frames_are_not_reapplied_to_atelier_shelves(self):
        shelf = (ROOT / 'SourceReadSwift/Features/Bookshelf/BookshelfView.swift').read_text(encoding='utf8')
        self.assertIn('.padding(theme.usesFramedShelf(for: effectiveComposition) ? 12 : 0)', shelf)
        self.assertIn('if theme.usesFramedShelf(for: effectiveComposition) {', shelf)
        self.assertNotRegex(shelf, re.escape('.padding(theme.homeComposition == .gallery ? 12 : 0)'))

    def test_native_workflow_is_serial_and_names_existing_test_suites(self):
        workflow = yaml.safe_load((ROOT / '.github/workflows/atelier-redesign.yml').read_text(encoding='utf8'))
        job = workflow['jobs']['themes']
        self.assertEqual(job['strategy']['max-parallel'], 1)
        self.assertEqual(job['strategy']['matrix']['runtime'], ['26', '18'])
        commands = '\n'.join(step.get('run', '') for step in job['steps'])
        suites = re.findall(r'-only-testing:(SourceReadSwift(?:UI)?Tests)/(\w+)', commands)
        self.assertGreaterEqual(len(suites), 8)
        for target, suite in suites:
            self.assertTrue((ROOT / target / (suite + '.swift')).is_file(), suite)
        self.assertIn('AtelierLayoutTests', commands)
        self.assertIn('AtelierHomeUITests', commands)
        self.assertIn('HomeLayoutEvidenceTests', commands)
        self.assertNotIn('testReaderSystemReturn', commands)

    def test_snapshot_preserves_reader_glass_and_the_user_index(self):
        index = Path(subprocess.check_output(['git', 'rev-parse', '--git-path', 'index'], cwd=ROOT).decode().strip())
        if not index.is_absolute():
            index = ROOT / index
        previous = index.read_bytes()
        tree = build_tree()['tree']
        self.assertEqual(index.read_bytes(), previous)
        unchanged = ['SourceReadSwift/Features/Reader', 'SourceReadSwift/App/RootTabView.swift',
                     'SourceReadSwift/Features/Bookshelf/ForestReadingCard.swift',
                     'SourceReadSwift/Shared/DesignSystem/LegacyTabBar.swift',
                     'SourceReadSwift/Shared/DesignSystem/RootTabGlassSurface.swift']
        changed = subprocess.check_output(['git', 'diff', '--name-only', BASE, tree, '--', *unchanged], cwd=ROOT)
        self.assertEqual(changed.strip(), b'')
        frozen = subprocess.check_output(['git', 'show', tree + ':SourceReadSwift/Features/Bookshelf/BookshelfView.swift'], cwd=ROOT)
        self.assertNotIn(b'HomeReturnReadinessProbe', frozen)


if __name__ == '__main__':
    unittest.main()
