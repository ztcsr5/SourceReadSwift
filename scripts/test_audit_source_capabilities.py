"""Check static source inventories preserve variants without leaking source literals."""

import json
from pathlib import Path
import tempfile
import unittest

from audit_source_capabilities import audit_libraries, redact_script_literals, summarize_rule


class SourceCapabilityAuditTests(unittest.TestCase):
    def test_comments_and_literal_calls_do_not_become_capabilities(self):
        source = {"bookSourceUrl": "https://fixture.invalid", "jsLib": """
        // java.fakeComment();
        var token = 'fixture-secret java.fakeString()';
        /* android.fake.Comment(); */
        java.ajax('/read');
        java.reUiView = function() {};
        java.reUiView();
        """}
        summary = summarize_rule(source, "func ajax() {}")
        self.assertEqual(summary["call_candidates"], ["java.ajax", "java.reUiView"])
        self.assertEqual(summary["authored_bridge_definitions"], ["java.reUiView"])
        self.assertEqual(summary["not_named_in_native_core"], [])
        self.assertNotIn("fixture-secret", repr(summary))

    def test_stringified_form_actions_and_image_byte_hook_are_seen(self):
        source = {"bookSourceUrl": "https://fixture.invalid", "loginUi": json.dumps([
            {"type": "button", "action": "java.startBrowserAwait('http://fixture.invalid/login')"}]),
            "ruleContent": {"imageDecode": "const key='fixture-secret'; java.bytesToStr(result.slice(1,5)); src;"}}
        summary = summarize_rule(source, "")
        self.assertIn("java.startBrowserAwait", summary["call_candidates"])
        hook = summary["image_decode"][0]
        self.assertEqual(hook["form"], "plain")
        self.assertTrue(hook["uses_result_bytes"])
        self.assertTrue(hook["uses_source_url"])
        self.assertNotIn("fixture-secret", json.dumps(summary))
        self.assertNotIn("http://fixture.invalid", json.dumps(summary))

    def test_identity_variants_and_case_sensitive_paths_are_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sources.json"
            first = {"bookSourceUrl": "https://fixture.invalid/A", "bookSourceName": "A", "searchUrl": "/a"}
            modified = dict(first, searchUrl="/b")
            lower_path = dict(first, bookSourceUrl="https://fixture.invalid/a")
            path.write_text(json.dumps([first, first, modified, lower_path]), encoding="utf8")
            report = audit_libraries([path])
        self.assertEqual(report["records"], 4)
        self.assertEqual(report["distinct_definitions"], 3)
        self.assertEqual(report["distinct_source_identities"], 2)
        self.assertEqual(report["identities_with_definition_variants"], 1)
        self.assertEqual(len(report["rows"][0]["occurrences"]), 2)
        self.assertTrue(all(row["reading_pipeline"] == "not_executed" for row in report["rows"]))

    def test_blank_identity_and_nonobject_rows_fail_explicitly(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sources.json"
            for invalid, message in [([None], "nonobject"), ([{}], "no source identity"), ({}, "nonempty array")]:
                path.write_text(json.dumps(invalid), encoding="utf8")
                with self.subTest(invalid=invalid), self.assertRaisesRegex(ValueError, message):
                    audit_libraries([path])

    def test_escaped_literals_preserve_line_count_without_exposing_values(self):
        script = "'secret\\'still-secret';\njava.ajax('secret'); /* secret\nsecret */\n`secret ${java.hidden()}`;"
        masked = redact_script_literals(script)
        self.assertEqual(masked.count("\n"), script.count("\n"))
        self.assertNotIn("secret", masked)
        self.assertNotIn("java.hidden", masked)
        self.assertIn("java.ajax", masked)


if __name__ == "__main__":
    unittest.main()
