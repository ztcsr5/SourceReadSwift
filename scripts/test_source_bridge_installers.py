"""Replay fixed JS object bridges before/after compilation using offline synthetic values.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_source_bridge_installers.py
Node checks rebinding semantics; native XCTest measures JavaScriptCore directory timing.
"""
import json
from pathlib import Path
import re
import subprocess
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SourceBridgeInstallerTests(unittest.TestCase):
    def test_compiled_installers_preserve_rebinding_and_persistent_variables(self):
        runtime = (ROOT / "SourceReadSwift/Core/JavaScript/JSCoreRuntime.swift").read_text(encoding="utf8")
        snippets = re.findall(r'let injectScript = """\n(.*?)\n\s+"""', runtime, re.S)
        self.assertEqual(len(snippets), 3)
        bridges = {name: textwrap.dedent(script).replace("\\\\", "\\")
                   for name, script in zip(("chapter", "source", "book"), snippets)}
        harness = r"""
        const vm = require('node:vm');
        const bridges = JSON.parse(require('node:fs').readFileSync(0, 'utf8'));
        function replay(shouldCompile) {
          const values = {};
          const scope = vm.createContext({java: {
            getVar: key => values[key] || '',
            put: (key, value) => values[key] = String(value),
            removeVar: key => delete values[key],
            removePrefix: prefix => Object.keys(values).filter(key => key.startsWith(prefix)).forEach(key => delete values[key]),
            keysWithPrefix: prefix => Object.keys(values).filter(key => key.startsWith(prefix))
          }, __sourceReadSynchronizeLoginInfo: () => {}, __sourceReadForgetLoginCache: () => {}});
          const compiled = Object.fromEntries(Object.entries(bridges).map(([name, script]) =>
            [name, shouldCompile ? vm.runInContext('(function(){\n' + script + '\n})', scope) : null]));
          const answers = [];
          for (let index = 0; index < 3; index++) {
            scope.source = {bookSourceName: 'Source ' + index, bookSourceUrl: 'https://fixture.example/' + index};
            scope.book = {name: 'Book ' + index, bookUrl: '/book/' + index};
            scope.chapter = {title: 'Chapter ' + index, url: '/chapter/' + index, index};
            for (const [name, script] of Object.entries(bridges)) {
              if (shouldCompile) compiled[name](); else vm.runInContext(script, scope);
            }
            answers.push(vm.runInContext(`
              source.setVariable('marker', source.getName());
              [source.getName(), book.getName(), chapter.getTitle(), chapter.getIndex(), source.getVariable('marker')].join('|')
            `, scope));
          }
          return {answers, marker: values['source.variable.marker']};
        }
        process.stdout.write(JSON.stringify({reference: replay(false), compiled: replay(true)}));
        """
        completed = subprocess.run(["node", "-e", harness], input=json.dumps(bridges), cwd=ROOT,
                                   capture_output=True, text=True, encoding="utf8", timeout=10)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        outcomes = json.loads(completed.stdout)
        expected = {"answers": [f"Source {index}|Book {index}|Chapter {index}|{index}|Source {index}"
                                for index in range(3)], "marker": "Source 2"}
        self.assertEqual(outcomes["reference"], expected)
        self.assertEqual(outcomes["compiled"], expected)


if __name__ == "__main__":
    unittest.main()
