"""Read only GitHub Actions metadata using this repository's configured auth.

Never prints or persists the configured remote URL or its credentials.
"""
from pathlib import Path
import base64
import json
import subprocess
import urllib.parse
import urllib.request
import urllib.error

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[1]

def main():
    raw=subprocess.check_output(['git','-C',str(ROOT),'remote','get-url','origin']).decode().strip()
    parsed=urllib.parse.urlsplit(raw)
    if parsed.hostname not in ('github.com','www.github.com'):
        raise SystemExit('Configured remote is not HTTPS github.com; no credentials used.')
    repo=parsed.path.strip('/').removesuffix('.git')
    headers={'Accept':'application/vnd.github+json','User-Agent':'SourceReadSwift-readonly-audit','X-GitHub-Api-Version':'2022-11-28'}
    user=urllib.parse.unquote(parsed.username or '')
    password=urllib.parse.unquote(parsed.password or '')
    if password:
        headers['Authorization']='Basic '+base64.b64encode((user+':'+password).encode()).decode()
    elif user:
        headers['Authorization']='Bearer '+user
    results=[]
    for suffix in ('actions/runs/41078356580','actions/runs/41078356597','actions/runs?branch=codex%2Fbuild-118&per_page=8'):
        url='https://api.github.com/repos/'+repo+'/'+suffix
        try:
            with urllib.request.urlopen(urllib.request.Request(url,headers=headers),timeout=25) as response:
                data=json.load(response)
            runs=data.get('workflow_runs',[data])
            for r in runs:
                result={k:r.get(k) for k in ('id','name','status','conclusion','head_sha','head_branch','run_attempt','created_at','updated_at','html_url')}
                if result not in results:results.append(result)
        except urllib.error.HTTPError as exc:
            results.append({'endpoint':suffix,'http_status':exc.code})
        except Exception as exc:
            results.append({'endpoint':suffix,'error':type(exc).__name__})
    (OUT/'ci-readonly-metadata.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps(results,ensure_ascii=False,indent=2))

if __name__=='__main__':main()
