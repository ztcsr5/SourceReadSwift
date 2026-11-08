from pathlib import Path
import hashlib,json,shutil,subprocess
R=Path(__file__).resolve().parents[2];O=Path('F:/SourceReadSwift/release-1.1.4')
H=subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip()
assert H=='d8c3a1f0133b19014b9f5af983d16df9f0fa8985'
assert not subprocess.check_output(['git','diff','--name-only'],cwd=R).strip()
assert not (O/'baseline.json').exists()
O.mkdir(parents=True,exist_ok=True)
files=subprocess.check_output(['git','ls-files'],cwd=R,text=True,encoding='utf8').splitlines()
for n in files:
 p=R/n
 if p.is_file():
  q=O/'BASELINE'/n;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
(O/'baseline.json').write_text(json.dumps({'head':H,'files':len(files),'version':'1.1.3','build':124}),encoding='utf8')
for n in ['ci.py','ci_timing.py','watch_ci.py','syntax_compare.py','package_release.py','graph.py','download_ipa.py','finalize.py']:
 s=(R/'docs/release-1.1.3'/n).read_text(encoding='utf8')
 s=s.replace('release-1.1.3','release-1.1.4').replace('0785bf059059fabf9e98775369e9bd64dff893b6',H)
 if n=='download_ipa.py':
  s=s.replace("== '1.1.3'","== '1.1.4'").replace("== '124'","== '125'").replace('SourceReadSwift-1.1.3-build124','SourceReadSwift-1.1.4-build125').replace('build124 IPA','build125 IPA')
 if n=='finalize.py':
  s=s.replace("=='1.1.3'","=='1.1.4'").replace("=='124'","=='125'").replace("'version':'1.1.3'","'version':'1.1.4'").replace("'build':124","'build':125")
  s=s.replace('SourceReadSwift-1.1.2-build123','SourceReadSwift-1.1.3-build124').replace('8d3f60d136ecfebc4186290a0c2de72449b66e2611ee52f1b439722d28dc9124','e888fe076c7f390335030bd08e0be66b39d769c04c00bd655e84dd2bef2ec9c7')
 (Path(__file__).parent/n).write_text(s,encoding='utf8')
# Load the last verified, focused reader graph for orientation, not fresh claims.
g=R/'graphify-out';g.mkdir(exist_ok=True)
shutil.copy2('F:/SourceReadSwift/release-1.1.3/graphify-out/graph.json',g/'graph.json')
subprocess.run(['git','switch','-c','codex/release-1.1.4'],cwd=R,check=True)
print('Copy-first baseline saved',H,len(files))
