"""Verify that the batch comparison never promotes untested sources to passes."""

import unittest

from audit_source_report_matrix import audit_batch


def report(identity: str = "https://publisher.invalid", keyword: str = "剑来", *, has_content: bool = True) -> dict:
    """Create one offline source report without any source script or credential."""
    stages = ["search", "detail", "toc", "content"] if has_content else ["search", "detail", "toc"]
    return {"keyword": keyword, "reports": [{"sourceURL": identity, "keyword": keyword,
                                              "steps": [{"stage": stage, "status": "passed"} for stage in stages]}]}


class SourceReportMatrixTests(unittest.TestCase):
    rules = [{"bookSourceUrl": "https://publisher.invalid"}]

    def test_missing_chapter_stage_is_not_a_pass(self):
        result = audit_batch(self.rules, report(), report(has_content=False))
        self.assertEqual(result["baseline"]["all_passed"], 1)
        self.assertEqual(result["candidate"]["all_passed"], 0)
        self.assertEqual(result["candidate"]["stages"]["content"], {"not_run": 1})
        self.assertNotIn("publisher.invalid", repr(result))

    def test_keyword_and_cohort_both_have_to_match(self):
        with self.assertRaisesRegex(ValueError, "keyword"):
            audit_batch(self.rules, report(), report(keyword="斗破苍穹"))
        with self.assertRaisesRegex(ValueError, "cohort mismatch"):
            audit_batch(self.rules, report(), report(identity="https://other.invalid"))

    def test_duplicate_rows_and_missing_rule_files_are_not_accepted(self):
        duplicate = self.rules + self.rules
        with self.assertRaisesRegex(ValueError, "duplicate"):
            audit_batch(duplicate, report())
        with self.assertRaisesRegex(ValueError, "rules do not match"):
            audit_batch([{"bookSourceUrl": "https://other.invalid"}], report())


if __name__ == "__main__":
    unittest.main()
