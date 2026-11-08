from pathlib import Path
import hashlib,json,shutil,subprocess
R=Path(__file__).resolve().parents[2];O=Path('F:/SourceReadSwift/release-1.1.3')
H=subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip()
assert H=='0785bf059059fabf9e98775369e9bd64dff893b6'
assert not subprocess.check_output(['git','diff','--name-only'],cwd=R).strip()
assert not (O/'baseline.json').exists()
O.mkdir(parents=True,exist_ok=True)
files=subprocess.check_output(['git','ls-files'],cwd=R,text=True,encoding='utf8').splitlines()
for n in files:
 p=R/n
 if p.is_file():
  q=O/'BASELINE'/n;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
(O/'baseline.json').write_text(json.dumps({'head':H,'files':len(files),'version':'1.1.2','build':123}),encoding='utf8')
for n in ['ci.py','ci_timing.py','watch_ci.py','syntax_compare.py','package_release.py','graph.py','download_ipa.py','finalize.py']:
 s=(R/'docs/release-1.1.2'/n).read_text(encoding='utf8')
 s=s.replace('release-1.1.2','release-1.1.3').replace('272b38ae603abe0552c4b5c28e2246f377aa781d',H)
 if n=='download_ipa.py':
  s=s.replace("== '1.1.2'","== '1.1.3'").replace("== '123'","== '124'").replace('SourceReadSwift-1.1.2-build123','SourceReadSwift-1.1.3-build124').replace('build123 IPA','build124 IPA')
 if n=='finalize.py':
  s=s.replace("=='1.1.2'","=='1.1.3'").replace("=='123'","=='124'").replace("'version':'1.1.2'","'version':'1.1.3'").replace("'build':123","'build':124")
  s=s.replace('SourceReadSwift-1.1.1-build122','SourceReadSwift-1.1.2-build123').replace('5b80d9ca60053cb6176433c0e9d53b61bf4d22f96ad85c2fdc2373f5931c8338','8d3f60d136ecfebc4186290a0c2de72449b66e2611ee52f1b439722d28dc9124')
 (Path(__file__).parent/n).write_text(s,encoding='utf8')
source=Path('C:/Users/Edc21/Documents/xwechat_files/wxid_rpsqr5rjmyc222_4e8b/temp/RWTemp/2026-11/bb3b96445913ce671dac20c8773d584e/433a5996cfd24f69ad961b4980389777.jpg')
dest=O/'INPUT'/source.name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,dest)
(O/'input-manifest.json').write_text(json.dumps({'source':str(source),'sha256':hashlib.sha256(dest.read_bytes()).hexdigest()}),encoding='utf8')
subprocess.run(['git','switch','-c','codex/release-1.1.3'],cwd=R,check=True)
print('Copy-first baseline saved',H,len(files))
