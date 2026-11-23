"""Replay the document's actual visible-node selection at chapter boundaries.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_web_reader_visible_position.py
"""
import json
from pathlib import Path
import subprocess
import unittest

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parents[1]


class WebReaderVisiblePositionTests(unittest.TestCase):
    def test_review_tap_isolated_from_reader_and_marks_use_native_utf16_offsets(self):
        source = (ROOT / "SourceReadSwift/Features/Reader/WebReaderDocument.swift").read_text(encoding="utf8")
        start = source.index("<!doctype html>")
        shell = source[start:source.index('"""#', start)]
        candidates = [Path("C:/Program Files/Google/Chrome/Application/chrome.exe"),
                      Path("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe")]
        executable = next((path for path in candidates if path.exists()), None)
        with sync_playwright() as runtime:
            browser = runtime.chromium.launch(executable_path=str(executable) if executable else None)
            try:
                page = browser.new_page(viewport={"width": 375, "height": 667}, has_touch=True)
                requests = []
                page.on("request", lambda req: requests.append(req.url))
                page.route("**/*", lambda route: route.abort())
                page.set_content(shell, wait_until="domcontentloaded")
                page.evaluate('''() => {
                    window.events = [];
                    window.webkit = {messageHandlers:{reader:{postMessage:m => events.push(m)}}};
                    window.styleFixture = {fontFamily:'sans-serif',fontWeight:400,fontSize:18,lineHeight:1.55,
                        letterSpacing:0,paragraphSpacing:10,paragraphIndent:36,sidePadding:20,topInset:28,
                        bottomInset:24,titleSize:21,titleSpacing:16,textColor:'#202020',surfaceColor:'#fff',
                        highlightColor:'#ffff00',accentColor:'#426859',bodyUnderline:true,highlightRules:[{
                        id:'quote',bold:true,inkStops:['#923333','#246a56']}]};
                    window.fixture = {key:'c2',chapter:2,title:'章名',sig:'v1',start:0,titleFlat:0,first:true,
                        paragraphs:[{flat:0,local:0,text:'🚀「正文」',marks:[['quote',2,6]]}],
                        reviews:[{p:0,slot:0,label:'段评 · 7'},{p:-1,slot:1,label:'章评'}]};
                    __reader.setStyle(styleFixture);
                    __reader.setContent({revision:'r1',total:1,sections:[fixture]});
                }''')
                paragraph = page.locator('.para:not(.image)').first
                self.assertEqual(paragraph.locator('mark.rainbow').text_content(), '「正文」')
                self.assertEqual(paragraph.evaluate('p=>getComputedStyle(p).textDecorationLine'), 'underline')
                bubble = page.get_by_role('button', name='段评 · 7')
                self.assertEqual(bubble.evaluate('b=>getComputedStyle(b).color'), 'rgb(66, 104, 89)')
                self.assertGreaterEqual(bubble.bounding_box()['height'], 44)
                self.assertGreaterEqual(bubble.bounding_box()['width'], 44)
                # Make sure the ordinary reader tap is armed; otherwise a scroll debounce could hide a double event.
                page.wait_for_timeout(320)
                bubble.tap()
                review = page.evaluate('events.filter(m=>m.type==="review")')
                self.assertEqual([(m['chapter'], m['slot']) for m in review], [(2, 0)])
                self.assertFalse(page.evaluate('events.some(m=>m.type==="tap")'))
                paragraph.tap(position={'x': 90, 'y': 3})
                self.assertTrue(page.evaluate('events.some(m=>m.type==="tap")'))
                page.evaluate("__reader.setStyle({...styleFixture,bodyUnderline:false,bionicReading:true,compactReviews:true,reviewTint:'#814c63'})")
                self.assertEqual(paragraph.evaluate('p=>getComputedStyle(p).textDecorationLine'), 'none')
                self.assertEqual(bubble.count(), 1)
                self.assertEqual(bubble.evaluate('b=>getComputedStyle(b).color'), 'rgb(129, 76, 99)')
                page.get_by_role('button', name='章评').click()
                self.assertEqual(page.evaluate('events.filter(m=>m.type==="review").at(-1).slot'), 1)
                page.evaluate("__reader.setContent({revision:'r2',total:1,sections:[{...fixture,reviews:[],sig:'off'}]})")
                self.assertEqual(page.locator('.review-bubble').count(), 0)
                self.assertEqual(paragraph.text_content(), '🚀「正文」')
                self.assertEqual(requests, [])
            finally:
                browser.close()

    def test_crossing_a_heading_reports_its_own_first_paragraph_in_both_directions(self):
        source = (ROOT / "SourceReadSwift/Features/Reader/WebReaderDocument.swift").read_text(encoding="utf8")
        start = source.index("<!doctype html>")
        shell = source[start:source.index('"""#', start)]
        candidates = [Path("C:/Program Files/Google/Chrome/Application/chrome.exe"),
                      Path("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe")]
        executable = next((path for path in candidates if path.exists()), None)
        with sync_playwright() as runtime:
            browser = runtime.chromium.launch(executable_path=str(executable) if executable else None, headless=True)
            try:
                page = browser.new_page(viewport={"width": 390, "height": 844})
                page.route("**/*", lambda route: route.abort())
                page.set_content(shell, wait_until="domcontentloaded")
                outcome = page.evaluate("""async () => {
                    const messages = [];
                    window.webkit = {messageHandlers:{reader:{postMessage:m=>messages.push(m)}}};
                    window.__reader.setStyle({fontFamily:'sans-serif',fontWeight:400,fontSize:20,lineHeight:1.4,
                        letterSpacing:0,paragraphSpacing:12,paragraphIndent:40,sidePadding:20,topInset:50,
                        bottomInset:24,titleSize:26,titleSpacing:16,textColor:'#000000',surfaceColor:'#ffffff',
                        highlightColor:'#ffff00',accentColor:'#6666cc',selectable:false});
                    const sections = [0,1].map(chapter=>({
                        key:'c'+chapter, chapter, title:'连续阅读第'+(chapter+1)+'章', sig:'chapter'+chapter,
                        start:chapter*9, titleFlat:chapter ? 8 : 0, first:chapter===0,
                        paragraphs:Array.from({length:8}, (_, local)=>({flat:chapter*9+local, local,
                            text:('【连续章'+(chapter+1)+'·段'+(local+1)+'】窗外的风吹过树梢。').repeat(8)}))
                    }));
                    window.__reader.setContent({revision:'heading-boundary',total:17,sections});
                    const wait = () => new Promise(resolve=>setTimeout(resolve, 170));
                    await wait();
                    const samples = [];
                    for (const selector of ['[data-flat="7"]','h2','[data-flat="10"]','h2','[data-flat="7"]']) {
                        const element = document.querySelector(selector);
                        const inset = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--top')) || 0;
                        window.scrollTo(0, element.getBoundingClientRect().top + window.scrollY - inset);
                        window.dispatchEvent(new Event('scroll'));
                        await wait();
                        const position = messages.filter(m=>m.type==='visible').at(-1);
                        const firstProse = document.querySelector('[data-key="c1"] .para').getBoundingClientRect();
                        samples.push({flat:position.flat,offset:position.utf16Offset,
                            firstProseTop:firstProse.top, firstProseBottom:firstProse.bottom});
                    }
                    return samples;
                }""")
                self.assertEqual([sample["flat"] for sample in outcome], [7, 9, 10, 9, 7], outcome)
                for sample in (outcome[1], outcome[3]):
                    self.assertEqual(sample["offset"], 0)
                    self.assertGreater(sample["firstProseBottom"], 20)
                    self.assertLess(sample["firstProseTop"], 422)
            finally:
                browser.close()

    def test_whitespace_after_previous_chapter_does_not_report_offscreen_prose(self):
        source = (ROOT / "SourceReadSwift/Features/Reader/WebReaderDocument.swift").read_text(encoding="utf8")
        start = source.index("      function metricAt(y, allowMetricsRebuild) {")
        end = source.index("      function captureAnchor()", start)
        script = """
        const window = {scrollY: 0};
        const boxes = [[0,40],[60,240],[340,400],[420,640]];
        const state = {nodes: boxes.map(([top,bottom],index)=>({index,
          getBoundingClientRect:()=>({top,bottom,height:bottom-top})})),
          metricsDirty: true, metricsInvalidFrom: 0, metricTops: [], metricHeights: []};
        const nodeMetric = element => ({index:element.index});
        """ + source[start:end] + """
        console.log(JSON.stringify([-10,0,100,239,240,300,340,500,700].map(y=>metricAt(y).index)));
        """
        outcome = subprocess.run(["node", "-e", script], cwd=ROOT, capture_output=True,
                                 text=True, encoding="utf8", timeout=10, check=True)
        self.assertEqual(json.loads(outcome.stdout), [0,0,1,1,2,2,2,3,3])


if __name__ == "__main__":
    unittest.main()
