"""Test the native return evidence validator. Usage: unittest discover -s scripts -p test_book_passage_log.py."""
import unittest
from verify_book_passage_log import inspect_passages
import verify_book_passage_log as verifier

class BookPassageLogTests(unittest.TestCase):
    def test_alignment_requires_actual_source_and_rectangle_callbacks(self):
        self.assertEqual(verifier.inspect_alignment("ALIGN_CONFIGURED\nALIGN_SOURCE ready=1\nALIGN_RECT ready=1"),
                         {"native_source": True, "native_alignment": True})

    def test_configuring_an_alignment_without_using_it_cannot_pass(self):
        with self.assertRaises(ValueError):
            verifier.inspect_alignment("ALIGN_CONFIGURED")

    def test_a_missing_source_or_rectangle_cannot_pass(self):
        for log in ["ALIGN_CONFIGURED\nALIGN_SOURCE ready=0\nALIGN_RECT ready=1",
                    "ALIGN_CONFIGURED\nALIGN_SOURCE ready=1\nALIGN_RECT ready=0"]:
            with self.assertRaises(ValueError):
                verifier.inspect_alignment(log)

    def test_a_silent_fallback_after_success_cannot_pass(self):
        with self.assertRaises(ValueError):
            verifier.inspect_alignment("ALIGN_CONFIGURED\nALIGN_SOURCE ready=1\nALIGN_RECT ready=1\nALIGN_SOURCE ready=0")

    def zoom_ui(self, before=0, after=1, passed=True):
        case = "Test Case '-[SourceReadSwiftUITests.FloatingReadingDeskUITests testReaderSystemReturnCanCancelWithoutLosingItsSavedParagraph]'"
        return (case + " started.\n" +
                f"BOOK_NATIVE_CANCEL_VERIFIED motion_before={before} motion_after={after}\n" +
                case + (" passed (3 seconds)." if passed else " failed (3 seconds)."))

    def test_zoom_cancel_before_pop_requires_native_motion_and_passed_ui_postconditions(self):
        log = "PAN_MOVED native=1 count=1\nBEGIN interactive=1\nEND cancelled=0"
        self.assertEqual(inspect_passages(log, self.zoom_ui()),
                         {"interactive_cancel": 1, "interactive_finish": 1})

    def test_zoom_ui_marker_alone_cannot_prove_native_motion(self):
        with self.assertRaises(ValueError):
            inspect_passages("BEGIN interactive=1\nEND cancelled=0", self.zoom_ui())

    def test_native_motion_without_a_passed_cancel_test_cannot_prove_cancellation(self):
        with self.assertRaises(ValueError):
            inspect_passages("PAN_MOVED native=1 count=1\nBEGIN interactive=1\nEND cancelled=0",
                             self.zoom_ui(passed=False))

    def test_native_motion_counter_must_really_advance(self):
        with self.assertRaises(ValueError):
            inspect_passages("PAN_MOVED native=1 count=1\nBEGIN interactive=1\nEND cancelled=0",
                             self.zoom_ui(before=1, after=1))

    def test_cancelled_zoom_still_requires_a_real_interactive_finish(self):
        with self.assertRaises(ValueError):
            inspect_passages("PAN_MOVED native=1 count=1\nBEGIN interactive=0\nEND cancelled=0",
                             self.zoom_ui())

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
