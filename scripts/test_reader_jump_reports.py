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
    def test_startup_probe_recovers_a_completed_empty_document(self):
        source = (Path(__file__).resolve().parents[1] /
                  'SourceReadSwift/Features/Reader/WebScrollReaderView.swift').read_text(encoding='utf8')
        method = source[source.index('private func verifyStartupBridge'):]
        probe = re.search(r'let script = """(.*?)"""', method, re.S)
        self.assertIsNotNone(probe)
        runner = """const vm=require('vm');let script='';
process.stdin.setEncoding('utf8');process.stdin.on('data',chunk=>script+=chunk);
process.stdin.on('end',()=>{
  const outcomes=[];
  for (const [ready,bridge,shell] of [['complete',false,false],['complete',false,true],
                                    ['loading',false,false],['complete',true,true]]) {
    outcomes.push(vm.runInNewContext(script,{
      window:{__reader:bridge?{setContent(){}}:undefined},
      document:{readyState:ready,getElementById(){return shell?{}:null}}
    }));
  }
  process.stdout.write(JSON.stringify(outcomes));
});"""
        result = subprocess.run(['node', '-e', runner], input=probe.group(1), text=True,
                                encoding='utf8', capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), [-1, -1, 0, 1],
                         'A completed empty document needs bounded recovery, not indefinite startup waiting')

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


    def test_scroll_burst_batches_layout_reads_and_reports_the_final_reverse_position(self):
        source = (Path(__file__).resolve().parents[1] /
                  'SourceReadSwift/Features/Reader/WebReaderDocument.swift').read_text(encoding='utf8')
        start = source.index('<!doctype html>')
        shell = source[start:source.index('"""#', start)]
        candidates = [Path('C:/Program Files/Google/Chrome/Application/chrome.exe'),
                      Path('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe')]
        executable = next((path for path in candidates if path.exists()), None)
        with sync_playwright() as runtime:
            browser = runtime.chromium.launch(executable_path=str(executable) if executable else None, headless=True)
            try:
                page = browser.new_page(viewport={'width': 390, 'height': 844})
                page.route('**/*', lambda route: route.abort())
                page.set_content(shell, wait_until='domcontentloaded')
                outcome = page.evaluate("""async () => {
                    const messages = [];
                    window.webkit = {messageHandlers:{reader:{postMessage:m=>messages.push(m)}}};
                    const reader = window.__reader;
                    reader.setContent({revision:'burst', total:60, sections:[{
                      key:'c0', chapter:0, title:'章', sig:'burst', start:0, titleFlat:0, first:true,
                      paragraphs:Array.from({length:60}, (_, i)=>({
                        flat:i, local:i, text:'可反向拖动的长段文字。'.repeat(45)
                      }))
                    }]});
                    const root = document.documentElement;
                    const height = root.scrollHeight;
                    let reads = 0;
                    Object.defineProperty(root, 'scrollHeight', { get(){ reads++; return height; } });
                    const wait = ms => new Promise(resolve=>setTimeout(resolve, ms));
                    for (let i=0; i<20; i++) {
                        window.scrollTo(0, i<10 ? (i+1)*130 : (19-i)*130);
                        await wait(12);
                    }
                    await wait(185);
                    return {reads, y:window.scrollY, last:messages.filter(m=>m.type==='visible').at(-1)};
                }""")
                self.assertEqual(outcome['y'], 0)
                self.assertEqual(outcome['last']['flat'], 0)
                self.assertEqual(outcome['last']['revision'], 'burst')
                self.assertLessEqual(outcome['reads'], 6, outcome)
            finally:
                browser.close()


if __name__ == '__main__':
    unittest.main()
