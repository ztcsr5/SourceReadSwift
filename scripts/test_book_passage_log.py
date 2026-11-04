"""Test the native return evidence validator. Usage: unittest discover -s scripts -p test_book_passage_log.py."""
import unittest
from verify_book_passage_log import inspect_passages

class BookPassageLogTests(unittest.TestCase):
    def test_requires_both_real_interactive_outcomes(self):
        log = "BEGIN interactive=1\nEND cancelled=1\nBEGIN interactive=1\nEND cancelled=0"
        self.assertEqual(inspect_passages(log), {"interactive_cancel": 1, "interactive_finish": 1})

    def test_noninteractive_fallback_cannot_pass_as_finger_tracking(self):
        with self.assertRaisesRegex(ValueError, "actual cancel=0"):
            inspect_passages("BEGIN interactive=0\nEND cancelled=1\nBEGIN interactive=0\nEND cancelled=0")

    def test_empty_log_is_not_success(self):
        with self.assertRaises(ValueError):
            inspect_passages("")

    def test_unfinished_interactive_motion_is_not_success(self):
        with self.assertRaisesRegex(ValueError, "no completion"):
            inspect_passages("BEGIN interactive=1")

    def test_a_cancel_without_a_finish_is_not_success(self):
        with self.assertRaisesRegex(ValueError, "finish=0"):
            inspect_passages("BEGIN interactive=1\nEND cancelled=1")

    def test_overlapping_book_returns_are_not_success(self):
        with self.assertRaisesRegex(ValueError, "second book return"):
            inspect_passages("BEGIN interactive=1\nBEGIN interactive=0")

    def test_unrelated_log_lines_and_orphan_completions_are_ignored(self):
        log = "END cancelled=0\nother log\nBEGIN interactive=1\nEND cancelled=1\nBEGIN interactive=1\nEND cancelled=0"
        self.assertEqual(inspect_passages(log)["interactive_finish"], 1)
