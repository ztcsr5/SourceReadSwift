"""Replay the repaired aggregate source's actual JavaScript without network requests.

Usage: python -B -X utf8 -m unittest discover -s scripts -p 'test_aggregate_source_config.py'
Requires the existing Node runtime; source scripts execute in an isolated vm with a timeout.
"""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/sources/uxx-aggregate-compatible.json"


def replay(script):
    wrapper = """
    const vm = require('node:vm');
    const sourceDefinition = JSON.parse(require('node:fs').readFileSync(process.argv[1], 'utf8'))[0];
    let saved = '', keyword = '';
    const context = vm.createContext({
      source: {getVariable: () => saved, setVariable: value => { saved = value; }},
      java: {toast: () => {}, refreshExplore: () => {}, searchBook: value => { keyword = value; },
             ajax: url => { if (!url.startsWith('https://uxxtv.com/uxxhmapi.php?')) throw Error('Unexpected request');
               return '<img src="/one.png"><img data-src="/two.png">'; }},
      infoMap: {'关键字': '三国'}, book: {}, baseUrl: '', src: ''
    });
    const run = script => vm.runInContext(script.replace(/^@js:/, ''), context, {timeout: 2000});
    """
    completed = subprocess.run(["node", "-e", wrapper + script, str(SOURCE)],
                               cwd=ROOT, text=True, encoding="utf8", capture_output=True, timeout=10, check=True)
    return json.loads(completed.stdout)


class AggregateSourceConfigTests(unittest.TestCase):
    def test_each_discovery_mode_changes_the_actual_search_rule(self):
        result = replay("""
        const modes = ['小说','有声','漫画','视频'];
        const addresses = modes.map(mode => {
          const menu = JSON.parse(run(sourceDefinition.exploreUrl));
          const button = menu.find(row => row.action && row.title.endsWith(' '+mode));
          if (!button) throw Error('Missing mode control');
          run(button.action);
          return run(sourceDefinition.searchUrl);
        });
        console.log(JSON.stringify(addresses));
        """)
        self.assertEqual([url.rsplit("cid=", 1)[1] for url in result], ["2", "3", "4", "1"])

    def test_source_search_button_preserves_user_input_and_refreshes_menu(self):
        result = replay("""
        let menu = JSON.parse(run(sourceDefinition.exploreUrl));
        run(menu.find(row => row.action && row.title.endsWith(' 漫画')).action);
        menu = JSON.parse(run(sourceDefinition.exploreUrl));
        run(menu.find(row => row.action && row.action.includes('java.searchBook')).action);
        console.log(JSON.stringify({keyword, category:menu.find(row=>row.url).url, saved}));
        """)
        self.assertEqual(result["keyword"], "三国")
        self.assertIn("/type/4/", result["category"])
        self.assertEqual(json.loads(result["saved"]), {"mode": "漫画"})

    def test_content_rule_uses_persisted_book_type_when_chapter_url_lacks_mode(self):
        result = replay("""
        context.book={type:64,bookUrl:'https://uxxtv.com/show/1.html'};
        context.baseUrl='https://uxxtv.com/play/1.html';
        context.src='<iframe src="uxxhmapi.php?id=fixture"></iframe>';
        console.log(JSON.stringify(run(sourceDefinition.ruleContent.content)));
        """)
        self.assertEqual(result, '<img src="/one.png">\n<img src="/two.png">')

    def test_legacy_plain_mode_is_still_accepted(self):
        result = replay("run(\"source.setVariable('漫画')\");console.log(JSON.stringify(run(sourceDefinition.searchUrl)));")
        self.assertTrue(result.endswith("cid=4"))


if __name__ == "__main__":
    unittest.main()
