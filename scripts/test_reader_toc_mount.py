"""Check the real reader TOC wiring that is invisible to projection-only unit tests.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_reader_toc_mount.py
The long-directory XCUI test verifies actual scroll position.
"""
from pathlib import Path
import unittest


class ReaderTocMountTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        cls.reader = (root / "SourceReadSwift/Features/Reader/ReaderView.swift").read_text(encoding="utf-8")
        cls.directory = cls.reader.split("private var tocList:", 1)[1].split(
            "private func navigationEntryRow", 1
        )[0]

    def test_clearing_a_filter_restores_the_current_chapter_instead_of_row_zero(self):
        query_change = self.directory.split(".onChange(of: debouncedTocQuery)", 1)[1].split(".onChange", 1)[0]
        self.assertIn(".currentChapter", query_change, "Removing the filter must restore the current chapter")
        self.assertIn(".firstRow", query_change, "Entering a filter still scrolls to its first match")

    def test_scroll_request_addresses_the_same_concrete_id_as_the_list(self):
        self.assertIn(r"ForEach(visibleChapters.indices, id: \.self)", self.directory)
        self.assertTrue("proxy.scrollTo(row, anchor: anchor)" in self.directory,
                        "Pass the Int presentation slot directly to scrollTo")
        self.assertNotIn("AnyHashable", self.directory, "Do not erase the List's presentation slot type")

    def test_plain_chapter_button_uses_the_whole_row_as_its_hit_region(self):
        label = self.reader.split("private struct TocChapterRow:", 1)[1].split("private struct", 1)[0]
        self.assertIn(".contentShape(Rectangle())", label)
