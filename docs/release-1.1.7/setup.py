from pathlib import Path
import json,shutil,subprocess,hashlib
R=Path(__file__).resolve().parents[2];O=Path('F:/SourceReadSwift/release-1.1.7')
H=subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip()
assert H=='68b68b7abbb7bea06e7fe53d95edc89ec8ee7c79'
assert not subprocess.check_output(['git','diff','--name-only'],cwd=R).strip()
O.mkdir(parents=True,exist_ok=True)
if not (O/'baseline.json').exists():
 files=subprocess.check_output(['git','ls-files'],cwd=R,text=True,encoding='utf8').splitlines()
 for n in files:
  p=R/n
  if p.is_file():
   q=O/'BASELINE'/n;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
 (O/'baseline.json').write_text(json.dumps({'head':H,'files':len(files),'version':'1.1.6','build':127}),encoding='utf8')
 for n in ['ci.py','ci_timing.py','watch_ci.py','syntax_compare.py','package_release.py','graph.py','collect_evidence.py']:
  s=(R/'docs/release-1.1.6'/n).read_text(encoding='utf8').replace('release-1.1.6','release-1.1.7').replace('bcb22284458db6a7bc8f6ae68a3ac60936df20a9',H)
  (Path(__file__).parent/n).write_text(s,encoding='utf8')
 subprocess.run(['git','switch','-c','codex/release-1.1.7'],cwd=R,check=True)
g=json.loads(Path('F:/SourceReadSwift/release-1.1.6/graphify-out/graph.json').read_text(encoding='utf8'))
nodes=g['nodes'];ids={n['id'] for n in nodes if 'ReaderView' in str(n.get('label',''))}
print('Existing graph orientation:',[(n.get('label'),n.get('source_file')) for n in nodes if n['id'] in ids][:8])
edges=g.get('links',g.get('edges',[]));print('Adjacent graph edges:',[e for e in edges if e.get('source') in ids or e.get('target') in ids][:8])
print('Copy-first baseline ready:',O)
