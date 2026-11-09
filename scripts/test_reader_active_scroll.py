"""Replay dirty-layout progress and anchors in the production reader document.

Usage: python -B -X utf8 scripts/test_reader_active_scroll.py
This checks DOM behavior and geometry-query counts, not device frame rate.
"""
from pathlib import Path
import unittest

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]


class ReaderActiveScrollTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = (ROOT / "SourceReadSwift/Features/Reader/WebReaderDocument.swift").read_text(encoding="utf8")
        start = source.index("<!doctype html>")
        cls.shell = source[start:source.index('"""#', start)].replace(
            "window.__reader = {", "window.scrollProbe = {reportVisiblePosition, captureAnchor, restoreAnchor}; window.__reader = {")
        candidates = [Path("C:/Program Files/Google/Chrome/Application/chrome.exe"),
                      Path("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe")]
        executable = next((path for path in candidates if path.exists()), None)
        cls.runtime = sync_playwright().start()
        cls.browser = cls.runtime.chromium.launch(
            executable_path=str(executable) if executable else None, headless=True)

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.runtime.stop()

    def replay(self, script, *, mount=True):
        page = self.browser.new_page(viewport={"width": 390, "height": 844})
        try:
            page.route("**/*", lambda route: route.abort())
            page.set_content(self.shell, wait_until="domcontentloaded")
            return page.evaluate("() => {" + """
                const messages = [];
                window.webkit = {messageHandlers:{reader:{postMessage:m=>messages.push(m)}}};
                const reader = window.__reader, state = reader.state, probe = window.scrollProbe;
                reader.setStyle({fontFamily:'sans-serif',fontWeight:400,fontSize:20,lineHeight:1.4,
                    letterSpacing:0,paragraphSpacing:12,paragraphIndent:40,sidePadding:20,topInset:50,
                    bottomInset:24,titleSize:26,titleSpacing:16,textColor:'#000',surfaceColor:'#fff',
                    highlightColor:'#ff0',accentColor:'#66c',selectable:false});
                const chapter = index => ({key:'c'+index,chapter:index,title:'Chapter '+index,sig:'s'+index,
                    start:index*601,titleFlat:index ? index*601-1 : 0,first:index===0,
                    paragraphs:Array.from({length:600},(_,local)=>({flat:index*601+local,local,
                        text:'Continuous prose with an independently identified paragraph. '.repeat(5)}))});
                const sections = [0,1].map(chapter);
                const mountInitial = (reset=true, report=true) =>
                    reader.setContent({revision:'initial',total:1201,sections},reset,report);
                const measureGeometry = action => {
                    let reads = 0;
                    const elementRect = Element.prototype.getBoundingClientRect;
                    const rangeRect = Range.prototype.getBoundingClientRect;
                    Element.prototype.getBoundingClientRect = function() { reads++; return elementRect.call(this); };
                    Range.prototype.getBoundingClientRect = function() { reads++; return rangeRect.call(this); };
                    try { action(); return reads; }
                    finally {
                        Element.prototype.getBoundingClientRect = elementRect;
                        Range.prototype.getBoundingClientRect = rangeRect;
                    }
                };
            """ + ("mountInitial();" if mount else "") + """
                const land = flat => {
                    const node = document.querySelector('.para[data-flat="'+flat+'"]');
                    window.scrollTo(0,node.getBoundingClientRect().top+window.scrollY-50);
                    state.lastScrollAt = performance.now();
                };
            """ + script + "}")
        finally:
            page.close()

    def test_first_page_reports_ready_without_measuring_the_whole_window(self):
        result = self.replay("""
            const reads = measureGeometry(() => mountInitial());
            const visible = messages.filter(message => message.type === 'visible');
            return {reads,visible,dirty:state.metricsDirty,y:window.scrollY};
        """, mount=False)
        self.assertTrue(result['visible'], 'First position must publish synchronously behind the opening cover')
        self.assertEqual(result['visible'][-1]['flat'], 0, result)
        self.assertEqual(result['visible'][-1]['utf16Offset'], 0, result)
        self.assertEqual(result['y'], 0, result)
        self.assertLessEqual(result['reads'], 64, result)
        self.assertTrue(result['dirty'], 'First readiness must not require a full geometry table')

    def test_saved_character_position_reports_ready_without_measuring_the_whole_window(self):
        result = self.replay("""
            const reads = measureGeometry(() => {
                mountInitial(false,false);
                reader.scrollToFlat(850,false,'resume','initial',100);
            });
            const paragraph = document.querySelector('.para[data-flat="850"]');
            const target = document.createRange();
            target.setStart(paragraph.firstChild,100);
            target.setEnd(paragraph.firstChild,101);
            return {reads,visible:messages.filter(message=>message.type==='visible'),
                applied:messages.filter(message=>message.type==='scroll-applied'),
                targetY:target.getBoundingClientRect().top,dirty:state.metricsDirty};
        """, mount=False)
        self.assertEqual(result['applied'][-1]['requestKey'], 'resume', result)
        self.assertEqual(result['visible'][-1]['flat'], 850, result)
        self.assertGreater(result['visible'][-1]['utf16Offset'], 0, result)
        self.assertAlmostEqual(result['targetY'], 50, delta=1, msg=str(result))
        self.assertLessEqual(result['reads'], 64, result)
        self.assertTrue(result['dirty'], 'Restoring one character must not require every paragraph geometry')

    def test_dirty_metrics_keep_reporting_during_a_long_fling_without_full_scan(self):
        result = self.replay("""
            land(30);
            probe.reportVisiblePosition(performance.now(),false);
            reader.refreshMetrics();
            const outputs = [];
            for (const flat of [300,605,900,100]) {
                land(flat);
                let reads = 0;
                const original = Element.prototype.getBoundingClientRect;
                Element.prototype.getBoundingClientRect = function() { reads++; return original.call(this); };
                try {
                    probe.reportVisiblePosition(performance.now(),false,false);
                    outputs.push({flat:state.visible,reads,dirty:state.metricsDirty});
                } finally { Element.prototype.getBoundingClientRect = original; }
            }
            return outputs;
        """)
        self.assertEqual([sample['flat'] for sample in result], [300,605,900,100], result)
        for sample in result:
            self.assertLessEqual(sample['reads'], 24, result)
            self.assertTrue(sample['dirty'], 'Moving samples must not rebuild the full table')

    def test_dirty_chapter_heading_and_gap_report_next_prose_in_both_directions(self):
        result = self.replay("""
            const heading = document.querySelector('[data-key="c1"] h2');
            const tail = document.querySelector('[data-key="c0"] [data-local="599"]');
            const headingY = heading.getBoundingClientRect().top+window.scrollY;
            const gapY = (tail.getBoundingClientRect().bottom+window.scrollY+headingY)/2;
            const positions = [];
            for (const y of [gapY,headingY,headingY+1,gapY]) {
                reader.refreshMetrics();
                window.scrollTo(0,y-50);
                state.lastScrollAt = performance.now();
                probe.reportVisiblePosition(performance.now(),false,false);
                positions.push(state.visible);
            }
            return positions;
        """)
        self.assertEqual(result, [601,601,601,601])

    def test_dirty_anchor_tracks_current_viewport_instead_of_last_reported_paragraph(self):
        result = self.replay("""
            land(10);
            probe.reportVisiblePosition(performance.now(),false);
            land(850);
            reader.refreshMetrics();
            const before = window.scrollY;
            const anchor = probe.captureAnchor();
            probe.restoreAnchor(anchor);
            return {before,after:window.scrollY,key:anchor.key,local:anchor.local};
        """)
        self.assertEqual(result['key'], 'c1', result)
        self.assertEqual(result['local'], 249, result)
        self.assertAlmostEqual(result['before'], result['after'], delta=1)


if __name__ == '__main__':
    unittest.main()
