import json
import shutil
import subprocess
import unittest
from pathlib import Path

from repair_webtoon_source import CONTENT, EXPLORE_LIST, SEARCH_BOOK_URL, TOC_URL, repair_sources


class WebtoonRepairTests(unittest.TestCase):
    def test_native_fixture_matches_the_repaired_rules(self):
        fixture_path = Path(__file__).resolve().parents[1] / 'SourceReadSwiftTests/Fixtures/webtoon-anonymous-source.json'
        fixture = json.loads(fixture_path.read_text(encoding='utf-8'))
        self.assertEqual(fixture['ruleExplore']['bookList'], EXPLORE_LIST)
        self.assertEqual(fixture['ruleExplore']['bookUrl'], '@href')
        self.assertEqual(fixture['ruleBookInfo']['tocUrl'], TOC_URL)
        self.assertEqual(fixture['ruleContent']['content'], CONTENT)
        self.assertFalse({'loginUrl', 'loginUi'} & fixture.keys())
        self.assertEqual(json.loads(fixture['header']), {
            'Cookie': 'locale=zh_TW', 'Referer': 'https://m.webtoons.com/'
        })

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

    def test_removes_only_static_webtoon_cookie_and_preserves_other_headers(self):
        for header in ({'User-Agent': 'authored mobile UA', 'cOoKiE': 'expired=fixture', 'Referer': 'https://m.webtoons.com/'},
                       json.dumps({'User-Agent': 'authored mobile UA', 'Cookie': 'expired=fixture', 'Accept-Language': 'zh-TW'})):
            source = {'bookSourceUrl': 'https://m.webtoons.com/zh-hant', 'searchUrl': '/search', 'header': header}
            other = {'bookSourceUrl': 'https://other.example', 'header': {'Cookie': 'keep=fixture'}}
            fixed = repair_sources([source, other])
            cleaned = json.loads(fixed[0]['header']) if isinstance(header, str) else fixed[0]['header']
            original = json.loads(header) if isinstance(header, str) else header
            self.assertEqual(cleaned, {key: value for key, value in original.items() if key.lower() != 'cookie'})
            self.assertEqual(fixed[1], other)
            self.assertEqual(repair_sources(fixed), fixed)

    def test_preserves_public_locale_cookie_but_removes_authored_session_cookies(self):
        for cookie, expected in [
            ('locale=zh_TW', 'locale=zh_TW'),
            ('session=expired-fixture; locale=zh_TW; auth=expired-fixture', 'locale=zh_TW'),
            ('locale=invalid/value; session=expired-fixture', None),
        ]:
            for serialized in (False, True):
                with self.subTest(cookie=cookie, serialized=serialized):
                    header = {'User-Agent': 'authored mobile UA', 'Cookie': cookie}
                    source = {'bookSourceUrl': 'https://m.webtoons.com/zh-hant', 'searchUrl': '/search',
                              'header': json.dumps(header) if serialized else header}
                    fixed = repair_sources([source])[0]
                    cleaned = json.loads(fixed['header']) if serialized else fixed['header']
                    self.assertEqual(cleaned.get('Cookie'), expected)
                    self.assertEqual(cleaned['User-Agent'], 'authored mobile UA')
                    self.assertEqual(repair_sources([fixed])[0], fixed)

    def test_does_not_invent_a_locale_when_the_input_has_already_lost_it(self):
        source = {'bookSourceUrl': 'https://m.webtoons.com/zh-hant', 'searchUrl': '/search',
                  'header': json.dumps({'User-Agent': 'authored mobile UA'})}
        repaired = repair_sources([source])[0]
        self.assertEqual(repaired['header'], source['header'])

    def test_explore_keeps_the_html_detail_address_instead_of_episode_json(self):
        source = {
            'bookSourceUrl': 'https://m.webtoons.com/zh-hant',
            'searchUrl': '/search',
            'ruleExplore': {'bookList': 'a[href]', 'bookUrl': '@js: result="https://m.webtoons.com/api/v1/webtoon/1234/episodes";result'},
        }
        fixed = repair_sources([source])[0]
        self.assertEqual(fixed['ruleExplore']['bookUrl'], '@href')

    @unittest.skipUnless(shutil.which('node'), 'Node is required to execute the authored listing rule')
    def test_explore_canvas_and_weekday_only_select_the_requested_group(self):
        source = {'bookSourceUrl': 'https://m.webtoons.com/zh-hant', 'searchUrl': '/search',
                  'ruleExplore': {'bookList': 'a[href]', 'bookUrl': '@href'}}
        listing = repair_sources([source])[0]['ruleExplore']['bookList']
        for address, expected in [
            ('https://m.webtoons.com/zh-hant/canvas/list?genre=ALL', '._genreTitleList_ALL '),
            ('https://m.webtoons.com/zh-hant/canvas/list?genre=ROMANCE', '._genreTitleList_ROMANCE '),
            ('https://m.webtoons.com/zh-hant/originals/monday', '.originals_MONDAY_list '),
            ('https://m.webtoons.com/zh-hant/genres/romance', '.genre_ROMANCE_list '),
            ('https://m.webtoons.com/zh-hant/ranking/trending', '.webtoon_list '),
            ('https://m.webtoons.com/zh-hant/ranking/popular', '.webtoon_list '),
            ('https://m.webtoons.com/zh-hant/new', '.webtoon_scroll_list '),
            ('https://m.webtoons.com/zh-hant/originals/complete', '.originals_COMPLETE_list '),
        ]:
            script = ('const baseUrl=' + json.dumps(address) + ';const java={getElements:x=>x};'
                      'const selected=' + listing.removeprefix('@js:') + ';process.stdout.write(selected);')
            with self.subTest(address=address):
                result = subprocess.run(['node', '-e', script], capture_output=True, text=True, check=True, timeout=10)
                self.assertTrue(result.stdout.startswith('@css:' + expected), result.stdout)

    @unittest.skipUnless(shutil.which('node'), 'Node is required to execute the authored TOC rule')
    def test_toc_kind_follows_actual_book_url_not_current_explore_mode(self):
        for address, mode, expected in [
            ('https://m.webtoons.com/zh-hant/romance/fixture/list?title_no=1234', 'CANVAS', 'webtoon/1234/episodes?pageSize=9999'),
            ('https://m.webtoons.com/zh-hant/canvas/fixture/list?title_no=2345', 'WEBTOON', 'canvas/2345/episodes?pageSize=9999'),
            ('https://m.webtoons.com/api/v1/canvas/2345/episodes?pageSize=10', 'WEBTOON', 'canvas/2345/episodes?pageSize=10'),
        ]:
            script = ('const baseUrl=' + json.dumps(address) + ';const source={getVariable:()=>'+json.dumps(mode)+'};'
                      'const target=' + TOC_URL.removeprefix('@js:') + ';process.stdout.write(target);')
            with self.subTest(address=address, mode=mode):
                result = subprocess.run(['node', '-e', script], capture_output=True, text=True, check=True, timeout=10)
                self.assertEqual(result.stdout, 'https://m.webtoons.com/api/v1/' + expected)

    @unittest.skipUnless(shutil.which('node'), 'Node is required to execute the authored search rule')
    def test_search_preserves_canvas_kind_in_html_book_address(self):
        for mode, kind in [('CANVAS', 'canvas'), ('WEBTOON', 'wt')]:
            script = ('const java={getString:()=>"9218"};const source={getVariable:()=>'+json.dumps(mode)+'};'
                      'const target=' + SEARCH_BOOK_URL.removeprefix('@js:') + ';process.stdout.write(target);')
            with self.subTest(mode=mode):
                result = subprocess.run(['node', '-e', script], capture_output=True, text=True, check=True, timeout=10)
                self.assertEqual(result.stdout, 'https://m.webtoons.com/zh-hant/' + kind + '/t9218/list?title_no=9218')

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
