"""Exercise the production reader DOM without compositor frames.

Usage: python -X utf8 scripts/test_reader_jump_reports.py
Uses the project's existing Playwright install and a local Chromium browser; no network or iOS FPS claim.
"""
from pathlib import Path
import json
import re
import subprocess
import textwrap
import unittest

from playwright.sync_api import sync_playwright


class ReaderJumpReportTests(unittest.TestCase):
    def test_isolated_cancellation_fixture_has_all_explicit_jump_dependencies(self):
        root = Path(__file__).resolve().parents[1]
        fixture = (root / 'SourceReadSwiftTests/Release110RegressionTests.swift').read_text(encoding='utf8')
        blocks = re.findall(r'context\.evaluateScript\("""\n(.*?)\n\s*"""\)', fixture, re.S)
        source = (root / 'SourceReadSwift/Features/Reader/WebReaderDocument.swift').read_text(encoding='utf8')
        motion_start = source.index('function stopScrollAnimation()')
        motion_end = source.index('function pageStep(', motion_start)
        jump_start = source.index('function scrollToFlat(')
        jump_end = source.index('/// 回到文档顶端', jump_start)
        program = '\n'.join([textwrap.dedent(blocks[0]), source[motion_start:motion_end],
                             source[jump_start:jump_end], textwrap.dedent(blocks[1])])
        runner = """const vm=require('node:vm');let input='';
process.stdin.on('data',chunk=>input+=chunk);process.stdin.on('end',()=>{
 const context=vm.createContext({});vm.runInContext(input,context);
 process.stdout.write(JSON.stringify({y:context.window.scrollY,messages:context.messages}));
});"""
        result = subprocess.run(['node', '-e', runner], input=program, text=True,
                                encoding='utf8', capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        outcome = json.loads(result.stdout)
        self.assertEqual(outcome['y'], 0)
        acknowledged = [message['requestKey'] for message in outcome['messages']
                        if message['type'] == 'scroll-applied']
        self.assertEqual(acknowledged, ['new-toc'])
        reports = [message for message in outcome['messages'] if message['type'] == 'visible']
        self.assertEqual([message['requestKey'] for message in reports], ['new-toc'])
        self.assertEqual(reports[0]['at'], 123)

    def test_explicit_character_jump_reports_after_acknowledgement_without_animation_frames(self):
        source = (Path(__file__).resolve().parents[1] /
                  'SourceReadSwift/Features/Reader/WebReaderDocument.swift').read_text(encoding='utf8')
        start = source.index('<!doctype html>')
        shell = source[start:source.index('"""#', start)]
        bootstrap = """<script>
window.readerMessages=[];
window.webkit={messageHandlers:{reader:{postMessage:function(message){window.readerMessages.push(message);}}}};
window.requestAnimationFrame=function(){return 0;};
</script>"""
        shell = shell.replace('<head>', '<head>' + bootstrap, 1)
        candidates = [Path('C:/Program Files/Google/Chrome/Application/chrome.exe'),
                      Path('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe')]
        executable = next((path for path in candidates if path.exists()), None)
        with sync_playwright() as runtime:
            browser = runtime.chromium.launch(executable_path=str(executable) if executable else None, headless=True)
            try:
                page = browser.new_page(viewport={'width': 390, 'height': 844})
                page.route('**/*', lambda route: route.abort())
                page.set_content(shell, wait_until='domcontentloaded')
                style = dict(fontFamily='sans-serif', fontWeight=400, fontSize=20, lineHeight=1.4,
                             letterSpacing=0, paragraphSpacing=12, paragraphIndent=40, sidePadding=20,
                             topInset=50, bottomInset=24, titleSize=26, titleSpacing=16,
                             textColor='#000000', surfaceColor='#ffffff', highlightColor='#ffff00',
                             accentColor='#6666cc', selectable=False)
                page.evaluate('(style)=>window.__reader.setStyle(style)', style)
                section = dict(key='c0', chapter=0, title='长段落', sig='long-text', start=0,
                               titleFlat=0, first=True, paragraphs=[dict(flat=0, local=0,
                               text='长段正文，模式切换不能回到段首。👩🏽‍💻' * 150)])
                page.evaluate('(payload)=>window.__reader.setContent(payload)',
                              dict(revision='jump-report', sections=[section], total=1))
                page.evaluate("window.readerMessages=[];window.__reader.resetScroll()")
                opening = page.evaluate("window.readerMessages.filter(message=>message.type==='visible')")
                self.assertTrue(opening, 'A first-page reader covered by its book jacket must not wait for a compositor frame')
                self.assertEqual(opening[-1]['flat'], 0)
                self.assertEqual(opening[-1]['utf16Offset'], 0)
                page.evaluate("window.readerMessages=[];window.__reader.scrollToFlat(0,false,'character600','jump-report',600)")
                page.wait_for_timeout(180)
                messages = page.evaluate('window.readerMessages')
                acknowledgements = [i for i, message in enumerate(messages) if message['type'] == 'scroll-applied']
                reports = [(i, message) for i, message in enumerate(messages) if message['type'] == 'visible']
                self.assertEqual(len(acknowledgements), 1)
                self.assertTrue(reports, 'An acknowledged jump must report its position without waiting for requestAnimationFrame')
                self.assertGreater(reports[0][0], acknowledgements[0], 'Native clears its pending key at acknowledgement')
                self.assertGreater(reports[0][1]['utf16Offset'], 500)
                self.assertLessEqual(reports[0][1]['utf16Offset'], 600)
                self.assertEqual(reports[0][1]['revision'], 'jump-report')
                before = len(messages)
                page.evaluate("window.__reader.scrollToFlat(0,false,'stale','old-revision',0)")
                self.assertEqual(len(page.evaluate('window.readerMessages')), before, 'An obsolete document must not publish a jump')
                anchored_y = page.evaluate('window.scrollY')
                page.evaluate("window.readerMessages=[];window.__reader.scrollToFlat(0,true,'old-animation','jump-report',0);window.__reader.scrollToFlat(0,false,'new-explicit','jump-report',600)")
                page.wait_for_timeout(480)
                settled = page.evaluate('window.readerMessages')
                completed = [message['requestKey'] for message in settled if message['type'] == 'scroll-applied']
                self.assertEqual(completed, ['new-explicit'], 'A cancelled old animation cannot acknowledge or publish a later position')
                self.assertAlmostEqual(page.evaluate('window.scrollY'), anchored_y, delta=2)
            finally:
                browser.close()


if __name__ == '__main__':
    unittest.main()
