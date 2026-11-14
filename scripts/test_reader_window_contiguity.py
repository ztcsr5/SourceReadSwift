"""Guard the path that mounts completed downloads into continuous reading.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_reader_window_contiguity.py
The Swift test exercises the actual buffer with out-of-order completions.
"""
from pathlib import Path
import unittest


class ReaderWindowContiguityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = Path(__file__).resolve().parents[1] / "SourceReadSwift/Features/Reader/ReaderView.swift"
        cls.reader = path.read_text(encoding="utf-8")

    def test_forward_demand_finds_the_first_missing_chapter_not_the_highest_loaded(self):
        demand = self.reader.split("private func requestScrollForwardChapter()", 1)[1].split(
            "private func requestScrollBackwardChapter", 1
        )[0]
        self.assertIn("ReaderChapterWindowPolicy.nextMissingIndex", demand)

    def test_scroll_mount_applies_one_anchor_transaction_for_the_contiguous_batch(self):
        self.assertTrue("private func drainContiguousScrollChapters()" in self.reader,
                        "Continuous reading must mount through a contiguous batch")
        mount = self.reader.split("private func drainContiguousScrollChapters()", 1)[1].split(
            "private func", 1
        )[0]
        self.assertEqual(mount.count("applyWindowChange("), 1)
        self.assertEqual(mount.count("rebuildWindowPositionMapping()"), 1)
        self.assertIn("trimWindowIfNeeded()", mount)
