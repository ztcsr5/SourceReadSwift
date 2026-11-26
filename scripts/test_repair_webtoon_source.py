import json
import shutil
import subprocess
import unittest

from repair_webtoon_source import CONTENT, repair_sources


class WebtoonRepairTests(unittest.TestCase):
    def test_repairs_only_webtoon_and_preserves_original_export(self):
        webtoon = {
            'bookSourceUrl': 'https://m.webtoons.com/zh-hant',
            'searchUrl': "return 'https://m.webtoons.com/undefined/search/result?keyword=' + key",
            'loginUi': 'authored configuration',
            'header': 'authored mobile user agent',
            'ruleContent': {'content': 'old images', 'imageStyle': 'FULL'},
        }
        other = {'bookSourceUrl': 'https://other.example', 'ruleContent': {'content': 'unchanged'}}
        fixed = repair_sources([webtoon, other])
        self.assertNotIn('/undefined/', fixed[0]['searchUrl'])
        self.assertIn('/zh-hant/search/result', fixed[0]['searchUrl'])
        self.assertEqual(fixed[0]['header'], webtoon['header'])
        self.assertEqual(fixed[0]['loginUi'], webtoon['loginUi'])
        self.assertEqual(fixed[0]['ruleContent']['imageStyle'], 'FULL')
        self.assertEqual(fixed[1], other)
        self.assertEqual(webtoon['ruleContent']['content'], 'old images')

    def test_rejects_wrong_export_shape_and_missing_source(self):
        for sources in ({}, [None], []):
            with self.assertRaises(ValueError):
                repair_sources(sources)

    @unittest.skipUnless(shutil.which('node'), 'Node is required to execute the authored content rule')
    def test_legacy_pages_exclude_unrelated_images_after_array(self):
        body = "var imageList = [{url:'https://pages.example/1.png'}];var ad={url:'https://ads.example/a.png'};"
        script = ('const result=' + json.dumps(body) + ';const java={getString:()=>null};'
                  'const pages=' + CONTENT.removeprefix('@js:') + ';process.stdout.write(pages);')
        result = subprocess.run(['node', '-e', script], capture_output=True, text=True, check=True, timeout=10)
        self.assertEqual(result.stdout, 'https://pages.example/1.png')

    @unittest.skipUnless(shutil.which('node'), 'Node is required to execute the authored content rule')
    def test_lazy_loaded_page_urls_take_priority_over_legacy_array(self):
        script = ('const result=' + json.dumps("var imageList=[{url:'https://old.example/1.png'}];") +
                  ';const java={getString:()=> ' + json.dumps(' https://pages.example/1.png\n/relative.png\nhttps://pages.example/2.png ') +
                  '};const pages=' + CONTENT.removeprefix('@js:') + ';process.stdout.write(pages);')
        result = subprocess.run(['node', '-e', script], capture_output=True, text=True, check=True, timeout=10)
        self.assertEqual(result.stdout.splitlines(), ['https://pages.example/1.png', 'https://pages.example/2.png'])


if __name__ == '__main__':
    unittest.main()
