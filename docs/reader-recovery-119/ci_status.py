from pathlib import Path
import base64,json,re,subprocess,time,urllib.request,urllib.parse,urllib.error,os

PROXY=os.environ.get('READER_CI_PROXY')
if PROXY:
    assert urllib.parse.urlsplit(PROXY).hostname in ('127.0.0.1','localhost')
    urllib.request.install_opener(urllib.request.build_opener(urllib.request.ProxyHandler({'http':PROXY,'https':PROXY})))

ROOT=Path(__file__).resolve().parents[2]
OUT=Path('F:/SourceReadSwift/recovery-119');OUT.mkdir(parents=True,exist_ok=True)
remote=urllib.parse.urlsplit(subprocess.check_output(['git','remote','get-url','origin'],cwd=ROOT).decode().strip())
assert remote.hostname=='github.com'
REPO=remote.path.strip('/').removesuffix('.git')
HEAD=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT).decode().strip()
HEADERS={'Accept':'application/vnd.github+json','User-Agent':'SourceReadSwift-reader-recovery','X-GitHub-Api-Version':'2022-11-28'}
user=urllib.parse.unquote(remote.username or '');password=urllib.parse.unquote(remote.password or '')
if password:HEADERS['Authorization']='Basic '+base64.b64encode((user+':'+password).encode()).decode()
elif user:HEADERS['Authorization']='Bearer '+user

def api(path):
    if os.environ.get('READER_CI_RESOLVED_ROUTE'):
        from github_transport import request
        status,_,body=request('https://api.github.com/repos/'+REPO+'/'+path,HEADERS)
        if status!=200:raise RuntimeError('GitHub API HTTP '+str(status))
        return json.loads(body)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request('https://api.github.com/repos/'+REPO+'/'+path,headers=HEADERS),timeout=30) as r:return json.load(r)
        except urllib.error.HTTPError:raise
        except (urllib.error.URLError,TimeoutError,ConnectionResetError) as error:
            print('READ_RETRY',attempt+1,type(error).__name__,flush=True)
            if attempt==2:raise
            time.sleep(2**attempt)

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args):return None

def signed_download(path):
    url='https://api.github.com/repos/'+REPO+'/'+path
    if os.environ.get('READER_CI_RESOLVED_ROUTE'):
        from github_transport import request
        status,headers,body=request(url,HEADERS)
        if status==200:return body
        if status not in (301,302,303,307,308):raise RuntimeError('GitHub download HTTP '+str(status))
        target=next(v for k,v in headers.items() if k.lower()=='location')
        assert urllib.parse.urlsplit(target).scheme=='https'
        with urllib.request.urlopen(urllib.request.Request(target,headers={'User-Agent':HEADERS['User-Agent']}),timeout=90) as r:return r.read()
    try:
        handlers=[NoRedirect]
        if PROXY:handlers.append(urllib.request.ProxyHandler({'http':PROXY,'https':PROXY}))
        with urllib.request.build_opener(*handlers).open(urllib.request.Request(url,headers=HEADERS),timeout=30) as r:return r.read()
    except urllib.error.HTTPError as e:
        if e.code not in (301,302,303,307,308):raise
        target=e.headers['Location']
        assert urllib.parse.urlsplit(target).scheme=='https'
        with urllib.request.urlopen(urllib.request.Request(target,headers={'User-Agent':HEADERS['User-Agent']}),timeout=60) as r:return r.read()

def main():
    runs=api('actions/runs?branch=codex%2Freader-recovery-119&per_page=10')['workflow_runs']
    results=[]
    for run in runs:
        if run['head_sha']!=HEAD:continue
        r={k:run.get(k) for k in ('id','name','status','conclusion','head_sha','html_url','created_at','updated_at')}
        try:jobs=api(f"actions/runs/{run['id']}/jobs")['jobs']
        except Exception as error:
            r['job_read_error']=type(error).__name__
            results.append(r)
            print(run['id'],run['name'],run['status'],run['conclusion'],'JOB_READ_FAILED',type(error).__name__)
            continue
        r['jobs']=[{'id':j['id'],'name':j['name'],'status':j['status'],'conclusion':j['conclusion'],'steps':[{'name':s['name'],'status':s['status'],'conclusion':s['conclusion']} for s in j.get('steps',[])]} for j in jobs]
        results.append(r)
        print(run['id'],run['name'],run['status'],run['conclusion'])
        for job in r['jobs']:
            print('  ',job['name'],[(s['name'],s['conclusion']) for s in job['steps'] if s['status']!='completed' or s['conclusion'] not in ('success','skipped')])
            if job['status']=='completed':
                log=OUT/f"job-{job['id']}.log"
                if not log.exists():
                    try:log.write_bytes(signed_download(f"actions/jobs/{job['id']}/logs"))
                    except Exception as error:print('LOG_READ_FAILED',type(error).__name__)
                if log.exists():
                    important=[line for line in log.read_text(encoding='utf8',errors='replace').splitlines() if re.search(r'error:|Test Case .* failed|Executed \d+ tests, with [1-9]|Test Suite .All tests.|\*\* (TEST|BUILD)',line)]
                    print('\n'.join(important[-40:]))
    (OUT/'ci-status.json').write_text(json.dumps({'head':HEAD,'runs':results},ensure_ascii=False,indent=2),encoding='utf8')

if __name__=='__main__':main()
