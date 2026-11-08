from pathlib import Path
import hashlib,json,subprocess,shutil
ROOT=Path(__file__).resolve().parents[2]
DOC=Path(__file__).resolve().parent
OUT=Path('F:/SourceReadSwift/release-1.1.0')
OUT.mkdir(parents=True,exist_ok=True)
def git(*a):return subprocess.check_output(['git',*a],cwd=ROOT)
head=git('rev-parse','HEAD').decode().strip()
for p in [Path('D:/AGENTS.md'),Path('D:/Gemini反重力/AGENTS.md'),ROOT/'AGENTS.md']:
    if p.exists():print('INSTRUCTIONS',p,'\n',p.read_text(encoding='utf8'))
assert not git('diff','--name-only').strip(), 'Tracked changes must be preserved before setup'
branch=git('branch','--show-current').decode().strip()
if branch!='codex/release-1.1.0':
    assert head=='71156be1ac148d6328dccc2844ed2555a41313b0'
    subprocess.run(['git','switch','-c','codex/release-1.1.0'],cwd=ROOT,check=True)
manifest=[]
for name in git('ls-files').decode().splitlines():
    source=ROOT/name
    if not source.is_file():continue
    dest=OUT/'BASELINE'/name
    if not dest.exists():dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,dest)
    manifest.append({'path':name,'sha256':hashlib.sha256(dest.read_bytes()).hexdigest()})
(OUT/'baseline.json').write_text(json.dumps({'head':head,'files':manifest},ensure_ascii=False,indent=2),encoding='utf8')
graph=json.loads((ROOT/'docs/audit-20261030-build118/graph.json').read_text(encoding='utf8'))
nodes=graph['nodes']
matches=[n for n in nodes if any(t in str(n.get('label','')).lower() for t in ['reader','catalog','detail','setting','search','theme','web'])]
print('EXISTING_GRAPH_ORIENTATION',json.dumps(matches[:25],ensure_ascii=False)[:8000])
for p in sorted((ROOT/'SourceReadSwift').rglob('*.swift')):
    if any(t in p.name.lower() for t in ['reader','catalog','detail','setting','search','theme','web','login','purif','replac','diagnos','root','tab','cover']):
        print('FILE',p.relative_to(ROOT),len(p.read_text(encoding='utf8').splitlines()))
print('BASELINE',head,'files',len(manifest),'branch codex/release-1.1.0')
