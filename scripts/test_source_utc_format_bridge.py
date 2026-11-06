"""Replay the production JavaScript UTC bridge, including all source-supplied arguments.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_source_utc_format_bridge.py
The native formatting result is covered separately by XCTest.
"""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SourceUTCFormatBridgeTests(unittest.TestCase):
    def test_source_and_global_alias_preserve_pattern_and_millisecond_offset(self):
        source = (ROOT / 'SourceReadSwift/Core/JavaScript/JSCoreRuntime.swift').read_text(encoding='utf8')
        bridge = source[source.index('        java.timeFormatUTC = function'):source.index('        java.putCache = function')]
        alias = next(line.strip() for line in source.splitlines() if 'globalThis.timeFormatUTC = function' in line)
        script = """
        const java = {}, calls = [];
        function __native_timeFormatUTC(...args) { calls.push(args); return 'native-result'; }
        """ + bridge + alias + """
        const results = [java.timeFormatUTC(86400000,'yyyy-MM-dd HH:mm',28800000),
                         timeFormatUTC(86400000,'HH:mm',-18000000)];
        console.log(JSON.stringify({calls,results}));
        """
        completed = subprocess.run(['node', '-e', script], cwd=ROOT, capture_output=True,
                                   text=True, encoding='utf8', timeout=10, check=True)
        outcome = json.loads(completed.stdout)
        self.assertEqual(outcome['calls'], [[86400000, 'yyyy-MM-dd HH:mm', 28800000],
                                             [86400000, 'HH:mm', -18000000]])
        self.assertEqual(outcome['results'], ['native-result', 'native-result'])


if __name__ == '__main__':
    unittest.main()
