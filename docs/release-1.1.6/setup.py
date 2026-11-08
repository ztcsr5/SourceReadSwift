from pathlib import Path
import hashlib, json, shutil, subprocess
R=Path(__file__).resolve().parents[2]
O=Path('F:/SourceReadSwift/release-1.1.6')
H=subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip()
assert H=='bcb22284458db6a7bc8f6ae68a3ac60936df20a9'
assert not subprocess.check_output(['git','diff','--name-only'],cwd=R).strip()
assert not (O/'baseline.json').exists()
O.mkdir(parents=True,exist_ok=True)
files=subprocess.check_output(['git','ls-files'],cwd=R,text=True,encoding='utf8').splitlines()
for n in files:
    p=R/n
    if p.is_file():
        q=O/'BASELINE'/n;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
(O/'baseline.json').write_text(json.dumps({'head':H,'files':len(files),'version':'1.1.5','build':126}),encoding='utf8')
for n in ['ci.py','ci_timing.py','watch_ci.py','syntax_compare.py','package_release.py','graph.py','download_ipa.py']:
    s=(R/'docs/release-1.1.5'/n).read_text(encoding='utf8').replace('release-1.1.5','release-1.1.6').replace('08b9e4a35671ed3a1eaf3a58369a1c60fbfd536c',H)
    if n=='download_ipa.py':
        s=s.replace("== '1.1.5'","== '1.1.6'").replace("== '126'","== '127'").replace('SourceReadSwift-1.1.5-build126','SourceReadSwift-1.1.6-build127').replace('build126 IPA','build127 IPA')
    (Path(__file__).parent/n).write_text(s,encoding='utf8')
subprocess.run(['git','switch','-c','codex/release-1.1.6'],cwd=R,check=True)
print('Copy-first:',H,len(files))
