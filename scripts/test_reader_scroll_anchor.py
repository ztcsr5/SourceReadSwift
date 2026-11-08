"""Replay chapter-window and style changes against the production reader DOM.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_reader_scroll_anchor.py
"""
from pathlib import Path
import unittest

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = """
const reader = window.__reader;
const style = {fontFamily:'sans-serif',fontWeight:400,fontSize:20,lineHeight:1.4,
    letterSpacing:0,paragraphSpacing:12,paragraphIndent:40,sidePadding:20,topInset:50,
    bottomInset:24,titleSize:26,titleSpacing:16,textColor:'#000',surfaceColor:'#fff',
    highlightColor:'#ff0',accentColor:'#66c',selectable:false};
reader.setStyle(style);
const chapter = index => ({key:'c'+index,chapter:index,title:'章节 '+index,sig:'s'+index,
    start:index*11,titleFlat:index ? index*11-1 : 0,first:index===0,
    paragraphs:Array.from({length:10},(_,local)=>({flat:index*11+local,local,
        text:'窗外的风穿过树梢。'.repeat(10)}))});
const sections = [0,1,2].map(chapter);
reader.setContent({revision:'initial',total:32,sections});
const describe = (section,index) => ({key:section.key,sig:section.sig,reuse:true,
    first:index===0,start:index*11,titleFlat:index ? index*11-1 : 0});
"""


class ReaderScrollAnchorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = (ROOT / "SourceReadSwift/Features/Reader/WebReaderDocument.swift").read_text(encoding="utf8")
        start = source.index("<!doctype html>")
        cls.shell = source[start:source.index('"""#', start)]
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

    def replay(self, script, argument=None):
        page = self.browser.new_page(viewport={"width": 390, "height": 844})
        try:
            page.route("**/*", lambda route: route.abort())
            page.set_content(self.shell, wait_until="domcontentloaded")
            return page.evaluate("argument => {" + FIXTURE + script + "}", argument)
        finally:
            page.close()

    def test_window_changes_preserve_the_reading_point_inside_a_chapter_gap(self):
        for operation in ["trim", "prepend"]:
            with self.subTest(operation=operation):
                result = self.replay("""
                    const heading = document.querySelector('[data-key="c2"] h2');
                    const tail = document.querySelector('[data-key="c1"] [data-local="9"]');
                    const gapTop = tail.getBoundingClientRect().bottom + window.scrollY;
                    const gapBottom = heading.getBoundingClientRect().top + window.scrollY;
                    window.scrollTo(0,(gapTop+gapBottom)/2-style.topInset-1);
                    const before = heading.getBoundingClientRect().top;
                    const paragraph = document.querySelector('[data-key="c1"] .para');
                    const next = argument === 'trim' ? sections.slice(1).map(describe) :
                        [{...chapter(-1),start:0,titleFlat:0,first:true,paragraphs:chapter(0).paragraphs},
                            ...sections.map((section,index)=>describe(section,index+1))];
                    const accepted = reader.setContent({revision:'changed',baseRevision:'initial',
                        total:argument==='trim' ? 21 : 43,sections:next});
                    return {accepted,before,after:heading.getBoundingClientRect().top,
                        gap:gapBottom-gapTop,
                        sameParagraph:document.querySelector('[data-key="c1"] .para')===paragraph};
                """, operation)
                self.assertTrue(result["accepted"], result)
                self.assertTrue(result["sameParagraph"], result)
                self.assertGreater(result["gap"], 20, result)
                self.assertAlmostEqual(result["after"], result["before"], delta=1, msg=result)

    def test_font_size_change_keeps_the_fraction_inside_the_visible_paragraph(self):
        result = self.replay("""
            const paragraph = document.querySelector('[data-key="c1"] [data-local="4"]');
            const rect = paragraph.getBoundingClientRect();
            window.scrollTo(0,rect.top+window.scrollY+rect.height*0.45-style.topInset-1);
            const fraction = () => (style.topInset+1-paragraph.getBoundingClientRect().top)/
                paragraph.getBoundingClientRect().height;
            const before = fraction();
            const oldHeight = paragraph.getBoundingClientRect().height;
            reader.setStyle({...style,fontSize:28});
            return {before,after:fraction(),oldHeight,newHeight:paragraph.getBoundingClientRect().height};
        """)
        self.assertGreater(result["newHeight"], result["oldHeight"], result)
        self.assertAlmostEqual(result["after"], result["before"], delta=0.01, msg=result)

    def test_appending_and_resolving_a_placeholder_does_not_rewrite_unchanged_sections(self):
        result = self.replay("""
            const mounted = sections.map(section=>document.querySelector('[data-key="'+section.key+'"]'));
            const observer = new MutationObserver(()=>{});
            for (const node of mounted) observer.observe(node,{attributes:true,childList:true,subtree:true});
            const pending = {...chapter(3),loading:true,paragraphs:[],sig:'pending'};
            const appended = reader.setContent({revision:'pending',baseRevision:'initial',total:33,
                sections:[...sections.map(describe),pending]});
            const appendMutations = observer.takeRecords().length;
            const resolved = reader.setContent({revision:'ready',baseRevision:'pending',total:43,
                sections:[...sections.map(describe),chapter(3)]});
            const resolutionMutations = observer.takeRecords().length;
            observer.disconnect();
            return {appended,resolved,appendMutations,resolutionMutations,
                sameNodes:mounted.every(node=>document.querySelector('[data-key="'+node.dataset.key+'"]')===node)};
        """)
        self.assertTrue(result["appended"], result)
        self.assertTrue(result["resolved"], result)
        self.assertTrue(result["sameNodes"], result)
        self.assertEqual(result["appendMutations"], 0, result)
        self.assertEqual(result["resolutionMutations"], 0, result)


if __name__ == "__main__":
    unittest.main()
