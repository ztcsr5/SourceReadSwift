"""Replay the production declaration primitive against ECMAScript host bindings.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_search_key_binding.py
Node checks TDZ/result/write-back semantics only; XCTest checks Swift token selection.
"""
import json
from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SearchKeyBindingTests(unittest.TestCase):
    def test_production_declaration_primitive_matches_rhino_host_write_back(self):
        normalizer = ROOT / 'SourceReadSwift/Core/JavaScript/LegadoSearchKeyCompatibility.swift'
        source = normalizer.read_text(encoding='utf8') if normalizer.exists() else ''
        replacement = re.search(r'replaceSubrange\(candidate, with: "([a-z]+)"\)', source)
        keyword = replacement.group(1) if replacement else 'let'
        script = "let key = java.encodeURI(key); key;"
        harness = """
        const vm = require('node:vm');
        const input = JSON.parse(require('node:fs').readFileSync(0, 'utf8'));
        function replay(script) {
          const scope = vm.createContext({key: 'fixture key', java: {encodeURI: encodeURIComponent}});
          try { return {result: vm.runInContext(script, scope), hostKey: scope.key}; }
          catch (error) { return {error: error.name, hostKey: scope.key}; }
        }
        process.stdout.write(JSON.stringify({original: replay(input.original), adapted: replay(input.adapted)}));
        """
        completed = subprocess.run(['node', '-e', harness],
            input=json.dumps({'original': script, 'adapted': keyword + script[3:]}),
            capture_output=True, text=True, encoding='utf8', timeout=10, check=True)
        result = json.loads(completed.stdout)
        self.assertEqual(result['original'], {'error': 'ReferenceError', 'hostKey': 'fixture key'})
        self.assertEqual(result['adapted'], {'result': 'fixture%20key', 'hostKey': 'fixture%20key'})


if __name__ == '__main__':
    unittest.main()
