import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ReferenceEditionCopyTests(unittest.TestCase):
    def test_magazine_home_and_detail_have_no_decorative_english(self):
        # Check UI copy, not book titles, SF Symbol names or accessibility identifiers.
        paths = ['Bookshelf/AntigravityReadingCard.swift', 'Bookshelf/EditionMasthead.swift', 'Bookshelf/BookshelfView.swift',
                 'Discover/BoundEditionDetail.swift', 'Discover/BookDetailView.swift', 'Discover/BookDetailSummary.swift']
        for path in paths:
            with self.subTest(path=path):
                source = (ROOT / 'SourceReadSwift/Features' / path).read_text(encoding='utf8')
                literals = re.findall(r'"([^"\n]+)"', source)
                self.assertNotRegex('\n'.join(literals), r'\b(?:PAPERBETWEEN|ISSUE|NOW READING|ARCHIVE|FOLIO|SYNOPSIS|CONTENTS)\b|\b(?:NO|P)\.\d')


if __name__ == '__main__':
    unittest.main()
