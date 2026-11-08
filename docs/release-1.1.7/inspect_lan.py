from pathlib import Path
import json,sys
ROOT=Path(__file__).resolve().parents[2]
if len(sys.argv)>1:
 p=ROOT/sys.argv[1]; lines=p.read_text(encoding='utf-8').splitlines()
 start=int(sys.argv[2]) if len(sys.argv)>2 else 1
 end=int(sys.argv[3]) if len(sys.argv)>3 else len(lines)
 for i in range(start-1,min(end,len(lines))): print(f'{i+1}: {lines[i]}')
else:
 for release in ('release-1.1.7','release-1.1.6'):
  p=Path('F:/SourceReadSwift')/release/'graphify-out/graph.json'
  if not p.exists(): continue
  data=json.loads(p.read_text(encoding='utf-8'))
  nodes={n['id']:n for n in data['nodes']}
  ids={k for k,n in nodes.items() if any(w in str(n).lower() for w in ('sourcewriting','simplewebserver'))}
  print(release, 'matches', len(ids))
  for k in list(ids)[:15]:print(nodes[k])
  for e in data.get('links',data.get('edges',[])):
   if e['source'] in ids or e['target'] in ids: print(e)
