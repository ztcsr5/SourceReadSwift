from pathlib import Path
import sys, subprocess, json, re, urllib.request, importlib.util
ROOT=Path(__file__).resolve().parents[2]
OUT=Path('F:/SourceReadSwift/release-1.1.2');OUT.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(ROOT/'docs/reader-recovery-119'))
import ci_status as ci
ci.OUT=OUT
def git(*args):
 p=subprocess.run(['git',*args],cwd=ROOT,capture_output=True,text=True,encoding='utf8',errors='replace')
 text=re.sub(r'https://[^\s/@]+:[^\s/@]+@','https://[REDACTED]@',p.stdout+p.stderr)
 text=re.sub(r'\b(?:ghp_|github_pat_|gho_)[A-Za-z0-9_]+','[REDACTED_TOKEN]',text)
 print(text,flush=True)
 if p.returncode:raise SystemExit(p.returncode)
 return p.stdout.strip()
if __name__=='__main__':
 mode=sys.argv[1] if len(sys.argv)>1 else 'status'
 if mode=='commit':
  git('diff','--check')
  paths=git('diff','--name-only').splitlines()
  paths+=git('ls-files','--others','--exclude-standard','SourceReadSwift','SourceReadSwiftTests').splitlines()
  paths=[p for p in paths if p.endswith('.swift') and not '.bak' in p]
  git('add','--',*paths,'project.yml','.github/workflows/unsigned-ipa.yml','.github/workflows/ios.yml','docs/release-1.1.2/RECOVERY.md')
  git('diff','--cached','--check')
  git('commit','-m',' '.join(sys.argv[2:]).strip('"'))
  (OUT/'current-head.txt').write_text(git('rev-parse','HEAD'),encoding='utf8')
  args=['-c','http.proxy='+urllib.request.getproxies()['https']] if urllib.request.getproxies().get('https') else []
  git(*args,'push','-u','origin','HEAD:codex/release-1.1.2')
 else:
  runs=ci.api('actions/runs?branch=codex%2Frelease-1.1.2&per_page=12')['workflow_runs'];data=[]
  for run in runs:
   if run['head_sha']!=ci.HEAD:continue
   jobs=ci.api(f"actions/runs/{run['id']}/jobs")['jobs']
   row={k:run.get(k) for k in ('id','name','head_sha','status','conclusion','html_url')};row['jobs']=jobs;data.append(row)
   print(run['id'],run['name'],run['status'],run['conclusion'])
   for job in jobs:
    print(job['id'],[(s['name'],s['conclusion']) for s in job['steps'] if s['conclusion'] not in ('success','skipped')])
    if job['status']=='completed':
     log=OUT/f"job-{job['id']}.log"
     if not log.exists():
      try:log.write_bytes(ci.signed_download(f"actions/jobs/{job['id']}/logs"))
      except Exception as e:print('LOG_ERROR',type(e).__name__)
     if log.exists() and mode != 'brief':
      lines=[x for x in log.read_text(encoding='utf8',errors='replace').splitlines() if re.search(r'error:|Test Case .* failed|Executed \d+ tests, with [1-9]|Test Suite .All tests.|\*\* (TEST|BUILD)',x)]
      print('\n'.join(lines[-45:]))
  (OUT/'ci-status.json').write_text(json.dumps({'head':ci.HEAD,'runs':data},ensure_ascii=False,indent=2),encoding='utf8')
