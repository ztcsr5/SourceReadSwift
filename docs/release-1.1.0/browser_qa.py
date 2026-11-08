from pathlib import Path
import json,re,hashlib,subprocess
from playwright.sync_api import sync_playwright
R=Path(__file__).resolve().parents[2];O=Path('F:/SourceReadSwift/release-1.1.0')
source=(R/'SourceReadSwift/Features/Discover/SourceWritingView.swift').read_text(encoding='utf8')
a=source.index('<!DOCTYPE html>',source.index('private func getWebPageHtml'));b=source.index('"""#',a)
html=source[a:b]
(O/'workbench.html').write_text(html,encoding='utf8')
reader=(R/'SourceReadSwift/Features/Reader/WebReaderDocument.swift').read_text(encoding='utf8')
a=reader.index('<!doctype html>');b=reader.index('"""#',a)
reader_html=reader[a:b]
(O/'browser-source-manifest.json').write_text(json.dumps({'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=R).decode().strip(),
 'sources':{name:hashlib.sha256((R/name).read_bytes()).hexdigest() for name in
 ['SourceReadSwift/Features/Discover/SourceWritingView.swift','SourceReadSwift/Features/Reader/WebReaderDocument.swift']}},indent=2),encoding='utf8')
candidates=[Path('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'),Path('C:/Program Files/Google/Chrome/Application/chrome.exe')]
candidates+=list(Path('C:/Users/Edc21/AppData/Local/ms-playwright/b').glob('**/chrome.exe'))
exe=next((p for p in candidates if p.exists()),None)
print('BROWSER',str(exe) if exe else 'playwright chromium default',flush=True)
rows=[]
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path=str(exe) if exe else None,headless=True)
 for width,height,scheme in [(1280,900,'light'),(390,844,'light'),(1280,900,'dark')]:
  page=browser.new_page(viewport={'width':width,'height':height},color_scheme=scheme)
  errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  # All calls are fixture responses. Do not send debug/push requests to a phone.
  page.route('**/*',lambda route:route.fulfill(status=200,content_type='application/json',body='{"sources":[],"healthy":true,"status":"ok","logs":[],"sessions":[]}'))
  page.set_content(html,wait_until='domcontentloaded')
  page.wait_for_timeout(120)
  for tab in ['editor','debugger','library']:
   page.evaluate('(tab)=>switchTab(tab)',tab)
   assert page.locator('#tab-'+tab).is_visible()
  page.evaluate("switchTab('editor')")
  metrics=page.evaluate('({width:innerWidth,scroll:document.documentElement.scrollWidth,title:document.title})')
  assert metrics['scroll']<=width,(width,metrics)
  shot=O/f'workbench-{width}-{scheme}.png';page.screenshot(path=str(shot),full_page=False)
  rows.append({'viewport':[width,height],'scheme':scheme,'metrics':metrics,'errors':errors,'screenshot':str(shot)})
  page.close()
 page=browser.new_page(viewport={'width':390,'height':844})
 errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.add_init_script('window.__messages=[];window.webkit={messageHandlers:{reader:{postMessage:m=>window.__messages.push(m)}}};')
 page.goto('about:blank')
 page.evaluate('window.__messages=[];window.webkit={messageHandlers:{reader:{postMessage:m=>window.__messages.push(m)}}};')
 page.set_content(reader_html,wait_until='domcontentloaded')
 def section(i,start):
  return {'key':f'c{i}','chapter':i,'title':f'第{i}章','sig':str(i),'start':start,'titleFlat':max(start-1,0),'first':i==22,'paragraphs':[{'flat':start+j,'local':j,'text':f'第{i}章正文{j}，内容不能乱跳。'*5} for j in range(35)]}
 payload={'revision':'rev-29','sections':[section(22,0),section(29,36)],'total':71}
 page.evaluate('(p)=>window.__reader.setContent(p)',payload)
 page.evaluate("window.__reader.scrollToFlat(36,false,'jump29','rev-29')")
 page.wait_for_timeout(60)
 messages=page.evaluate('window.__messages')
 assert any(m.get('type')=='scroll-applied' and m.get('requestKey')=='jump29' and m.get('revision')=='rev-29' for m in messages),messages
 before=page.evaluate('scrollY')
 page.evaluate("window.__reader.scrollToFlat(0,false,'old-jump','old-revision')")
 assert page.evaluate('scrollY')==before
 assert not any(m.get('requestKey')=='old-jump' for m in page.evaluate('window.__messages'))
 # Missing targets cannot silently settle on the closest old paragraph.
 page.evaluate("window.__reader.scrollToFlat(9999,false,'missing','rev-29')")
 assert page.evaluate('scrollY')==before
 assert any(m.get('type')=='scroll-miss' for m in page.evaluate('window.__messages'))
 assert not any(m.get('type')=='scroll-applied' and m.get('requestKey')=='missing' for m in page.evaluate('window.__messages'))
 # Speech keeps animation; its acknowledgement must not precede settlement.
 page.evaluate("window.__reader.scrollToFlat(0,true,'speech','rev-29')")
 immediate=page.evaluate('scrollY')
 assert not any(m.get('type')=='scroll-applied' and m.get('requestKey')=='speech' for m in page.evaluate('window.__messages'))
 page.wait_for_timeout(480)
 assert page.evaluate('scrollY') < before
 assert any(m.get('type')=='scroll-applied' and m.get('requestKey')=='speech' for m in page.evaluate('window.__messages'))
 # A newer explicit jump owns the final position, even during old animation.
 page.wait_for_timeout(800)
 page.evaluate("window.__reader.scrollToFlat(36,true,'old-animation','rev-29');window.__reader.scrollToFlat(0,false,'new-explicit','rev-29')")
 explicit=page.evaluate('scrollY')
 page.wait_for_timeout(480)
 settled=page.evaluate('scrollY')
 assert abs(settled-explicit)<2,('old animation moved new explicit jump',explicit,settled)
 assert not any(m.get('type')=='scroll-applied' and m.get('requestKey')=='old-animation' for m in page.evaluate('window.__messages'))
 assert not errors,errors
 rows.append({'reader':'DOM revision / exact target / old revision ignored / speech animation / newer jump wins',
  'chapter29ScrollY':before,'speechImmediateY':immediate,'explicitY':explicit,'settledY':settled,'errors':errors})
 browser.close()
(O/'browser-qa.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(rows,ensure_ascii=False),flush=True)
