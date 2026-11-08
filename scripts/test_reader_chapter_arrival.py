"""Replay production DOM updates when a chapter arrives under a visible title.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_reader_chapter_arrival.py
"""
from pathlib import Path
import unittest

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parents[1]


class ReaderChapterArrivalTests(unittest.TestCase):
    def replay(self, bottom_inset):
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
                result = page.evaluate("""bottomInset => {
                    window.webkit = {messageHandlers:{reader:{postMessage:()=>{}}}};
                    const reader = window.__reader;
                    reader.setStyle({fontFamily:'sans-serif',fontWeight:400,fontSize:20,lineHeight:1.4,
                        letterSpacing:0,paragraphSpacing:12,paragraphIndent:40,sidePadding:20,topInset:50,
                        bottomInset,titleSize:26,titleSpacing:16,textColor:'#000000',surfaceColor:'#ffffff',
                        highlightColor:'#ffff00',accentColor:'#6666cc',selectable:false});
                    const first = {key:'c0',chapter:0,title:'第一章',sig:'first',start:0,titleFlat:0,first:true,
                        paragraphs:Array.from({length:40},(_,i)=>({flat:i,local:i,text:'窗外的风穿过树梢。'.repeat(10)}))};
                    const pending = {key:'c1',chapter:1,title:'第二章',sig:'pending',start:41,titleFlat:40,
                        first:false,paragraphs:[],loading:true};
                    reader.setContent({revision:'pending',total:41,sections:[first,pending]});
                    const section = document.querySelector('[data-key="c1"]');
                    const heading = section.firstElementChild;
                    window.scrollTo(0,heading.getBoundingClientRect().top + window.scrollY - 50);
                    const headingY = heading.getBoundingClientRect().top;
                    let commands = 0;
                    const scroll = window.scrollTo.bind(window);
                    window.scrollTo = (...args)=>{commands++;scroll(...args);};
                    const observer = new MutationObserver(()=>{});
                    observer.observe(document.getElementById('content'),{childList:true,subtree:true});
                    const loaded = {...pending,sig:'loaded',loading:false,
                        paragraphs:Array.from({length:30},(_,i)=>({flat:41+i,local:i,text:'下一章的正文已经到达。'.repeat(8)}))};
                    const accepted = reader.setContent({revision:'loaded',baseRevision:'pending',total:71,
                        sections:[{...first,reuse:true,paragraphs:undefined},loaded]});
                    const removed = observer.takeRecords().flatMap(r=>Array.from(r.removedNodes));
                    observer.disconnect();
                    return {accepted,commands,headingY,newHeadingY:heading.getBoundingClientRect().top,
                        sameHeading:document.querySelector('[data-key="c1"]').firstElementChild===heading,
                        detached:removed.some(node=>node===heading || node===section),
                        text:document.querySelector('[data-key="c1"] .para').textContent};
                }""", bottom_inset)
                return result
            finally:
                browser.close()

    def test_loaded_body_keeps_the_visible_heading_and_does_not_stop_its_scroll(self):
        # The larger footer also puts the heading at the reading anchor, covering
        # an overscrolled title without relying on compositor-driven touch input.
        for inset in [24, 900]:
            with self.subTest(bottom_inset=inset):
                result = self.replay(inset)
                self.assertTrue(result["accepted"], result)
                self.assertGreater(result["headingY"], 0, result)
                self.assertLess(result["headingY"], 844, result)
                self.assertTrue(result["sameHeading"], result)
                self.assertFalse(result["detached"], result)
                self.assertEqual(result["commands"], 0, result)
                self.assertAlmostEqual(result["newHeadingY"], result["headingY"], delta=1)
                self.assertIn("下一章的正文", result["text"])


if __name__ == "__main__":
    unittest.main()
