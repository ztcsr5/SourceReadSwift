from pathlib import Path
import hashlib, json, shutil, subprocess
R=Path(__file__).resolve().parents[2]; O=Path('F:/SourceReadSwift/release-1.1.2'); O.mkdir(parents=True,exist_ok=True)
H=subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip()
assert H=='272b38ae603abe0552c4b5c28e2246f377aa781d'
assert not (O/'baseline.json').exists(), 'Preserve existing baseline'
files=subprocess.check_output(['git','ls-files'],cwd=R,text=True,encoding='utf8').splitlines()
for name in files:
    p=R/name
    if p.is_file():
        q=O/'BASELINE'/name;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
(O/'baseline.json').write_text(json.dumps({'head':H,'files':len(files),'version':'1.1.1','build':122},indent=2),encoding='utf8')
for name in ['ci.py','ci_timing.py','watch_ci.py','syntax_compare.py','package_release.py','graph.py','download_ipa.py']:
    s=(R/'docs/release-1.1.1'/name).read_text(encoding='utf8')
    s=s.replace('release-1.1.1','release-1.1.2').replace('f808c790ae6d78a24ae599a72d79060fb140974d',H)
    if name=='download_ipa.py':
        s=s.replace("== '1.1.1'","== '1.1.2'").replace("== '122'","== '123'").replace('build122','build123')
        s=s.replace('SourceReadSwift-1.1.1-','SourceReadSwift-1.1.2-')
    if name=='ci.py':
        s=s.replace("'project.yml','.github/workflows/unsigned-ipa.yml'","'project.yml','.github/workflows/unsigned-ipa.yml','.github/workflows/ios.yml'")
    (Path(__file__).parent/name).write_text(s,encoding='utf8')
subprocess.run(['git','switch','-c','codex/release-1.1.2'],cwd=R,check=True)
print('Copy-first baseline saved',H,len(files))
