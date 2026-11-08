"""Keep tab-glass validation serial, isolated, and accompanied by real home evidence.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_tab_glass_workflow.py
"""
from pathlib import Path
import subprocess
import unittest

import yaml

from verify_tab_glass_quality import BASE, ROOT, build_tree


class TabGlassWorkflowTests(unittest.TestCase):
    def test_both_runtimes_run_serially_and_preserve_real_window_and_home_evidence(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/tab-glass.yml").read_text(encoding="utf8"))
        job = workflow["jobs"]["glass"]
        self.assertEqual(job["strategy"]["max-parallel"], 1)
        self.assertEqual(job["strategy"]["matrix"]["runtime"], ["26", "18"])
        commands = "\n".join(step.get("run", "") for step in job["steps"])
        for suite in ["RootTabGlassTests", "TabChromeRegressionTests", "RootTabGlassUITests",
                      "testHomeGlobalSearchFindsTheLocalBookAndOpensItsDetails"]:
            self.assertIn(suite, commands)
        self.assertNotIn("testReaderSystemReturn", commands)
        self.assertNotIn("archivePath", commands)
        self.assertIn("--output-path tab-glass-snapshots/unit", commands)
        self.assertIn("--output-path tab-glass-snapshots/ui", commands)
        self.assertLess(commands.index("build-for-testing"), commands.index("test-without-building"))

    def test_snapshot_preserves_scroll_sources_and_does_not_touch_the_user_index(self):
        index = Path(subprocess.check_output(["git", "rev-parse", "--git-path", "index"], cwd=ROOT).decode().strip())
        if not index.is_absolute():
            index = ROOT / index
        previous = index.read_bytes()
        tree = build_tree()["tree"]
        self.assertEqual(index.read_bytes(), previous)
        changed = subprocess.check_output(["git", "diff", "--name-only", BASE, tree, "--",
            "SourceReadSwift/Features/Reader", "SourceReadSwiftTests/ReaderScrollSchedulingTests.swift",
            "SourceReadSwiftTests/ReaderScrollAnchorTests.swift"], cwd=ROOT)
        self.assertEqual(changed.strip(), b"")


if __name__ == "__main__":
    unittest.main()
