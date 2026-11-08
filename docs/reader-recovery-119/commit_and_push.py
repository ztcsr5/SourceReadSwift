from pathlib import Path
import hashlib,json,re,subprocess,sys,os

ROOT=Path(__file__).resolve().parents[2]
OUT=Path('F:/SourceReadSwift/recovery-119')

def run(args):
    p=subprocess.run(args,cwd=ROOT,capture_output=True,text=True,encoding='utf8',errors='replace')
    text=re.sub(r'https://[^\s/@]+:[^\s/@]+@','https://[REDACTED]@',p.stdout+p.stderr)
    text=re.sub(r'\b(?:ghp_|github_pat_|gho_)[A-Za-z0-9_]+','[REDACTED_TOKEN]',text)
    print(text,flush=True)
    if p.returncode:raise SystemExit(p.returncode)
    return p.stdout.strip()

if __name__=='__main__':
    source=ROOT/'.github/workflows/ios.yml'
    baseline=OUT/'BASELINE/.github/workflows/ios.yml'
    if not baseline.exists():
        baseline.parent.mkdir(parents=True,exist_ok=True)
        baseline.write_bytes(subprocess.check_output(['git','show','5686485:.github/workflows/ios.yml'],cwd=ROOT))
    run(['git','diff','--check'])
    paths=[p.relative_to(ROOT).as_posix() for p in (ROOT/'SourceReadSwift/Features/Reader').glob('*.swift')]
    paths+=['SourceReadSwiftTests/ReaderRecovery119Tests.swift','SourceReadSwiftTests/ReaderPageTextBuilderTests.swift','SourceReadSwift/Shared/AppVersion.swift','project.yml','.github/workflows/ios.yml','docs/reader-recovery-119/RECOVERY.md']
    run(['git','add','--',*paths])
    run(['git','diff','--cached','--check'])
    run(['git','commit','-m',sys.argv[1] if len(sys.argv)>1 else 'fix(reader): unify TextKit pages, version render caches, restore native menu and interruptible paging'])
    head=run(['git','rev-parse','HEAD'])
    (OUT/'current-head.txt').write_text(head+'\n',encoding='utf8')
    route=['-c','http.curloptResolve=github.com:443:20.205.243.166'] if os.environ.get('READER_GIT_RESOLVED_ROUTE') else []
    run(['git',*route,'push','-u','origin','HEAD:codex/reader-recovery-119'])
