"""Additional loopback-only file, backup and paired CLI contract checks."""
from pathlib import Path
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import json, os, subprocess, sys, threading
from playwright.sync_api import sync_playwright

ROOT=Path(__file__).resolve().parents[2]
OUT=Path('F:/SourceReadSwift/release-1.1.7/lan-ui');OUT.mkdir(parents=True,exist_ok=True)
HTML=(ROOT/'SourceReadSwift/Resources/LANWorkbench.html').read_bytes()
TOKEN='1234567890abcdef1234567890abcdef'
state={'writes':[], 'reject':False,'redirect':False,'redirect_hits':0}
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def reply(self,status,value):
  data=value if isinstance(value,bytes) else json.dumps(value).encode()
  self.send_response(status);self.send_header('Content-Type','text/html' if isinstance(value,bytes) else 'application/json')
  self.send_header('Content-Length',len(data));self.end_headers();self.wfile.write(data)
 def do_GET(self):
  if self.path=='/':return self.reply(200,HTML)
  if self.path=='/redirect-target':state['redirect_hits']+=1;return self.reply(200,{'ok':True})
  if self.path=='/favicon.ico':return self.reply(204,b'')
  if self.headers.get('X-SourceRead-Token')!=TOKEN:return self.reply(401,{'ok':False})
  if self.path=='/api/status' and state['redirect']:
   self.send_response(302);self.send_header('Location','/redirect-target');self.send_header('Content-Length','0');self.end_headers();return
  if self.path=='/api/sources/health':return self.reply(200,{'ok':True,'items':[]})
  if self.path=='/api/sources/export':return self.reply(200,{'sources':[{'bookSourceName':'备份','bookSourceUrl':'https://backup.invalid'}],'rssSources':[],'catalogs':[]})
  return self.reply(200,{'ok':True,'sourceCount':0,'enabledSourceCount':0})
 def do_POST(self):
  body=self.rfile.read(int(self.headers['Content-Length']))
  if self.headers.get('X-SourceRead-Token')!=TOKEN:return self.reply(401,{'ok':False})
  state['writes'].append(body)
  return self.reply(400 if state['reject'] else 200,{'ok':not state['reject'],'message':'fixture accepted'})
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
BASE=f'http://127.0.0.1:{server.server_port}'
checks=[]
def check(label,result):assert result,label;checks.append(label);print('PASS',label,flush=True)

with sync_playwright() as p:
 exe='C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
 browser=p.chromium.launch(executable_path=exe,headless=True)
 context=browser.new_context(viewport={'width':1280,'height':900},accept_downloads=True)
 page=context.new_page();page.goto(BASE)
 page.locator('#pair-button').click();page.locator('#pair-token').fill(TOKEN);page.locator('#pair-submit').click()
 page.wait_for_function('document.getElementById("connection-label").textContent==="已连接手机"')
 source={'bookSourceName':'带 BOM 的本地文件','bookSourceUrl':'https://local.invalid','header':'{"Cookie":"PRIVATE_FIXTURE"}'}
 text=json.dumps(source,ensure_ascii=False)
 page.locator('#json-file').set_input_files({'name':'sources.json','mimeType':'application/json','buffer':b'\xef\xbb\xbf'+text.encode('utf-8')})
 page.wait_for_function('document.getElementById("source-code").value.includes("带 BOM")')
 check('UTF8 BOM file opens locally without importing',not state['writes'] and '带 BOM' in page.locator('#source-code').input_value())
 page.locator('#source-code').fill(text+' ')
 page.get_by_role('button',name='从标准模板开始',exact=True).click();page.locator('#confirm-dialog[open]').wait_for()
 page.locator('#confirm-cancel').click()
 check('cancel draft replacement preserves unsaved file',page.locator('#source-code').input_value()==text+' ')
 page.locator('#json-file').set_input_files({'name':'invalid.json','mimeType':'application/json','buffer':b'\xff\xfe\x00'})
 page.get_by_role('status').filter(has_text='打开失败').wait_for()
 check('invalid encoding never replaces current draft',page.locator('#source-code').input_value()==text+' ')
 page.locator('#json-file').set_input_files({'name':'huge.json','mimeType':'application/json','buffer':b' '*(12*1024*1024+1)})
 page.locator('#toast').get_by_text('文件超过',exact=False).wait_for()
 check('over-limit file is rejected before decoding',not state['writes'])
 with page.expect_download() as draft:
  page.get_by_role('button',name='下载草稿',exact=True).click()
 draft_bytes=Path(draft.value.path()).read_bytes()
 check('downloaded draft retains original exact bytes',draft_bytes==(text+' ').encode('utf-8'))
 page.locator('#nav-library').click()
 with page.expect_download() as backup:
  page.get_by_role('button',name='导出备份',exact=True).click()
 backup_data=json.loads(Path(backup.value.path()).read_text(encoding='utf-8'))
 check('backup download is a restorable snapshot object',backup_data['sources'][0]['bookSourceName']=='备份' and 'rssSources' in backup_data)
 browser.close()

fixture=OUT/'cli-fixture.json'
sources=[{'bookSourceName':f'CLI {i} '+'测试'*40,'bookSourceUrl':f'https://cli{i}.invalid'} for i in range(12)]
fixture.write_text(json.dumps(sources,ensure_ascii=False),encoding='utf-8')
env=dict(os.environ,SOURCE_READ_LAN_TOKEN=TOKEN)
command=[sys.executable,'-X','utf8',str(ROOT/'tools/lan_import.py'),str(fixture),'--base',BASE,'--limit','1024']
result=subprocess.run(command,env=env,capture_output=True,text=True,encoding='utf-8')
check('paired CLI succeeds in size-bounded source batches',result.returncode==0 and 'confirmed_imported=12' in result.stdout and all(len(b)<=1024 for b in state['writes']))
check('CLI output contains no key or source header',TOKEN not in result.stdout+result.stderr and 'PRIVATE_FIXTURE' not in result.stdout+result.stderr)
before=len(state['writes']);state['reject']=True
failed=subprocess.run(command,env=env,capture_output=True,text=True,encoding='utf-8')
check('failed CLI mutation stops without per-source blind retries',failed.returncode!=0 and len(state['writes'])==before+1)
state['reject']=False;state['redirect']=True;before=len(state['writes'])
redirected=subprocess.run(command,env=env,capture_output=True,text=True,encoding='utf-8')
check('CLI refuses redirects before any imports or capability forwarding',redirected.returncode!=0 and len(state['writes'])==before and state['redirect_hits']==0)
server.shutdown()
(OUT/'VERIFICATION-files-cli.json').write_text(json.dumps({'scope':'Loopback fixture browser/file/CLI tests, not iPhone LAN acceptance','checks':checks,'successful_cli_stdout':result.stdout,'failed_cli_stdout':failed.stdout,'failed_cli_stderr':failed.stderr,'redirect_cli_stderr':redirected.stderr},ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS',len(checks),'checks')
