"""Exercise the production offline document against loopback-only fake APIs.

This is browser UI/contract evidence, not an iPhone LAN or real-site test.
"""
from pathlib import Path
import json, re, threading, time, urllib.parse
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from playwright.sync_api import sync_playwright

ROOT=Path(__file__).resolve().parents[2]
OUT=Path('F:/SourceReadSwift/release-1.1.7/lan-ui');OUT.mkdir(parents=True,exist_ok=True)
html=(ROOT/'SourceReadSwift/Resources/LANWorkbench.html').read_text(encoding='utf-8')
(OUT/'index.html').write_text(html,encoding='utf-8')
script=html.split('<script>',1)[1].split('</script>',1)[0]
(OUT/'workbench.js').write_text(script,encoding='utf-8')
TOKEN='1234567890abcdef1234567890abcdef'  # Synthetic fixture, not a user secret.
calls=[];changes=[];mode={'debugDelay':0,'libraryFailure':False}
rows=[{'name':f'书源 {i:04}', 'url':f'https://fixture{i}.invalid','group':'漫画' if i%3==0 else '小说',
       'enabled':i%4!=0,'healthStatus':['passed','failed','warning','untested'][i%4],'healthMessage':'本地 fixture'} for i in range(997)]
rows[0]['name']='引号 \' " <img src=x onerror="window.pwned=1">'

class Handler(BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def send(self,status,value,content_type='application/json'):
  data=value.encode('utf-8') if isinstance(value,str) else json.dumps(value,ensure_ascii=False).encode('utf-8')
  self.send_response(status);self.send_header('Content-Type',content_type);self.send_header('Content-Length',len(data))
  self.send_header('Cache-Control','no-store');self.end_headers()
  try:self.wfile.write(data)
  except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError):pass
 def do_GET(self):
  url=urllib.parse.urlsplit(self.path)
  if url.path=='/':return self.send(200,html,'text/html; charset=utf-8')
  if url.path=='/favicon.ico':return self.send(204,'')
  calls.append(('GET',url.path))
  if self.headers.get('X-SourceRead-Token')!=TOKEN:return self.send(401,{'ok':False})
  if url.path=='/api/status':return self.send(200,{'ok':True,'sourceCount':len(rows),'enabledSourceCount':sum(r['enabled'] for r in rows)})
  if url.path=='/api/sources/health':
   if mode['libraryFailure']:return self.send(503,{'ok':False,'error':'fixture offline'})
   return self.send(200,{'ok':True,'items':rows})
  if url.path=='/api/source':
   name=urllib.parse.parse_qs(url.query).get('url',[''])[0]
   found=next((r for r in rows if r['url']==name),None)
   if not found:return self.send(404,{'ok':False,'error':'missing fixture'})
   return self.send(200,{'ok':True,'data':{'bookSourceName':found['name'],'bookSourceUrl':name,'ruleContent':{'content':'#content@text'}}})
  if url.path=='/api/sources/export':return self.send(200,{'sources':[{'bookSourceName':r['name'],'bookSourceUrl':r['url']} for r in rows]})
  return self.send(404,{'ok':False,'error':'unknown'})
 def do_POST(self):
  path=urllib.parse.urlsplit(self.path).path;calls.append(('POST',path))
  if self.headers.get('X-SourceRead-Token')!=TOKEN:return self.send(401,{'ok':False})
  body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
  if path=='/api/source/debug':
   time.sleep(mode['debugDelay'])
   return self.send(200,{'ok':False,'logs':['搜索成功','目录失败（fixture）'],'error':'fixture toc unavailable',
      'durationMs':42,'search':[{'name':'<svg onload="window.pwned=1">','bookUrl':'javascript:alert(1)'}]})
  changes.append((path,body))
  if path=='/api/sources/toggle':
   next(r for r in rows if r['url']==body['url'])['enabled']=body['enabled']
  if path=='/api/sources/delete':rows[:]=[r for r in rows if r['url']!=body['url']]
  return self.send(200,{'ok':True,'message':'fixture import accepted'})

server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
base=f'http://127.0.0.1:{server.server_port}'
checks=[]
def check(label,condition):
 assert condition,label
 checks.append(label);print('PASS',label,flush=True)

with sync_playwright() as p:
 exe=Path('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe')
 browser=p.chromium.launch(executable_path=str(exe) if exe.exists() else None,headless=True)
 context=browser.new_context(viewport={'width':1280,'height':900},device_scale_factor=1,accept_downloads=True)
 page=context.new_page();errors=[];requests=[]
 page.on('pageerror',lambda e:errors.append(str(e)))
 page.on('request',lambda req:requests.append(req.url))
 page.goto(base);page.wait_for_timeout(100)
 check('landing makes no API request before pairing',not calls)
 page.get_by_role('button',name='连接手机',exact=True).click()
 page.locator('#pair-token').fill('a'*32);page.locator('#pair-submit').click()
 page.locator('#pair-error').get_by_text('配对密钥无效',exact=False).wait_for()
 check('invalid key never reads source library',not any(c[1]=='/api/sources/health' for c in calls))
 page.locator('#pair-token').fill(TOKEN);page.locator('#pair-submit').click()
 page.locator('#source-count').get_by_text('997',exact=True).wait_for()
 page.wait_for_function('document.querySelectorAll("#source-rows tr").length===20')
 check('997-source library renders only 20 DOM rows',page.locator('#source-rows tr').count()==20)
 check('untrusted names render as literal text, not executable HTML',page.evaluate('window.pwned===undefined') and page.locator('#source-rows img').count()==0)
 page.locator('#page-next').click()
 check('pagination starts next 20 without fetching again','21–40' in page.locator('#page-summary').inner_text())
 page.locator('#filter-search').fill('书源 0996')
 check('filter resets to first page with exact result',page.locator('#source-rows tr').count()==1 and '1 / 1' in page.locator('#page-number').inner_text())
 page.locator('#filter-search').fill('')
 page.screenshot(path=str(OUT/'library-1280-light.png'))
 page.locator('#source-rows button').filter(has_text='编辑').first.click()
 page.locator('#panel-editor:not([hidden])').wait_for()
 check('single-source editor uses selected-source endpoint, not full export',any(c[1]=='/api/source' for c in calls) and not any(c[1]=='/api/sources' for c in calls))
 page.locator('#source-code').fill(json.dumps({'bookSourceName':'新书源','bookSourceUrl':'https://new.invalid','ruleContent':{'content':'#body'}},ensure_ascii=False))
 page.get_by_role('button',name='检查并推送',exact=True).click()
 page.locator('#confirm-dialog[open]').wait_for();check('import requires explicit confirmation',not changes)
 page.locator('#confirm-cancel').click();check('cancel import changes nothing',not changes)
 page.get_by_role('button',name='检查并推送',exact=True).click();page.locator('#confirm-accept').click()
 page.wait_for_function('document.getElementById("draft-status").textContent.includes("已推送")')
 check('confirmed import sends once',sum(c[0]=='/api/sources/import' for c in changes)==1)
 page.get_by_role('button',name='前往调试',exact=True).click()
 page.locator('#run-debug').click();page.locator('#confirm-accept').click()
 page.wait_for_function('document.getElementById("debug-state").textContent==="本次失败"')
 check('failed debug keeps logs and partial results','目录失败' in page.locator('#debug-logs').inner_text() and 'fixture toc unavailable' in page.locator('#debug-results').inner_text())
 check('debug result does not execute URLs or markup',page.locator('#debug-results a,#debug-results svg').count()==0 and page.evaluate('window.pwned===undefined'))
 mode['debugDelay']=.8
 page.locator('#run-debug').click();page.locator('#confirm-accept').click();page.locator('#cancel-debug').click();page.wait_for_timeout(1100)
 check('stopped debug discards late result',page.locator('#debug-state').inner_text()=='已停止等待')
 page.locator('#nav-editor').click();page.screenshot(path=str(OUT/'editor-1280-light.png'))
 for width,scheme in [(390,'light'),(920,'dark'),(1280,'dark')]:
  page.set_viewport_size({'width':width,'height':900});page.emulate_media(color_scheme=scheme)
  for tab in ['library','editor','debugger']:
   page.locator('#nav-'+tab).click();page.screenshot(path=str(OUT/f'{tab}-{width}-{scheme}.png'))
   check(f'{tab} at {width}px {scheme}: no page-wide overflow',page.evaluate('document.documentElement.scrollWidth<=innerWidth+1'))
 page.set_viewport_size({'width':1280,'height':900});page.locator('#nav-library').click()
 mode['libraryFailure']=True;page.get_by_role('button',name='刷新',exact=True).click()
 page.locator('#offline-notice:not([hidden])').wait_for()
 check('network failure preserves last source list and draft',page.locator('#source-rows tr').count()==20 and '新书源' in page.locator('#source-code').input_value())
 check('page has no unhandled JS errors',not errors)
 check('page requests only its local fixture origin',all(u.startswith(base) for u in requests))
 check('no credentials persisted in browser storage',page.evaluate('localStorage.length===0 && sessionStorage.length===0'))
 page.locator('#pair-button').click();check('disconnect clears displayed private library',page.locator('#source-rows tr').count()==1 and page.locator('#source-count').inner_text()=='—')
 browser.close()
server.shutdown()
(OUT/'VERIFICATION.json').write_text(json.dumps({'scope':'Production HTML in headless Edge against local fake APIs; not phone LAN acceptance','checks':checks,'api_calls':calls,'mutation_counts':{name:sum(c[0]==name for c in changes) for name,_ in changes},'page_errors':errors},ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS',len(checks),'checks',OUT,flush=True)
