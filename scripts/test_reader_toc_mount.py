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
        cls.directory = cls.reader.split("private var tocList:", 1)[1].split("private var bookmarkSheet", 1)[0]
        path = root / "SourceReadSwift/Features/Reader/ReaderChapterDirectoryList.swift"
        cls.list_source = path.read_text(encoding="utf-8") if path.exists() else ""

    def test_clearing_a_filter_restores_the_current_chapter_instead_of_row_zero(self):
        query_change = self.directory.split(".onChange(of: debouncedTocQuery)", 1)[1].split(".onChange", 1)[0]
        self.assertIn(".currentChapter", query_change, "Removing the filter must restore the current chapter")
        self.assertIn(".firstRow", query_change, "Entering a filter still scrolls to its first match")

    def test_long_directory_positions_exact_row_only_after_window_layout(self):
        self.assertIn("table.scrollToRow(at:", self.list_source)
        self.assertIn("table.window != nil", self.list_source)
        self.assertIn("table.estimatedRowHeight = 0", self.list_source)
        self.assertNotIn("tocScrollTask", self.reader, "A fixed delay does not prove that the list is mounted")

    def test_chapter_uses_the_whole_native_cell_as_its_hit_region(self):
        self.assertIn("func tableView(_ tableView: UITableView, didSelectRowAt", self.list_source)
        self.assertIn("cell.accessibilityIdentifier", self.list_source)
        self.assertIn("reader.toc.locate", self.directory)

    def test_open_snapshots_the_visible_chapter_before_the_cover_mounts(self):
        self.assertIn("tocVisibleChapter = currentDisplayChapterIndex", self.directory)
        self.assertIn("currentChapter: tocVisibleChapter", self.directory)
