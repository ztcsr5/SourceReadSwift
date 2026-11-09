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
        start = source.index("      function metricAt(y) {")
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
