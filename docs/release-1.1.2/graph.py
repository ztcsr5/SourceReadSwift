"""Focused code-only graph update; no semantic agents or historical findings merged."""
from pathlib import Path
import hashlib, json, subprocess
from graphify.extract import extract
from graphify.build import build_from_json
from graphify.cluster import cluster, score_all
from graphify.export import to_json, to_html

ROOT=Path(__file__).resolve().parents[2]
OUT=Path('F:/SourceReadSwift/release-1.1.2/graphify-out');OUT.mkdir(parents=True,exist_ok=True)
BASE='272b38ae603abe0552c4b5c28e2246f377aa781d'
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
names=subprocess.check_output(['git','diff','--name-only',BASE,head],cwd=ROOT,text=True).splitlines()
files=[ROOT/n for n in names if n.endswith('.swift')]
data=extract(files,parallel=False)
for edge in data.get('edges',[]):
    edge.setdefault('confidence','EXTRACTED')
(OUT/'extraction.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
graph=build_from_json(data);communities=cluster(graph)
to_json(graph,communities,str(OUT/'graph.json'))
to_html(graph,communities,str(OUT/'graph.html'))
record={'head':head,'baseline':BASE,'scope':'Changed Swift only; AST relationships are not runtime performance proof.',
        'files':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
        'nodes':graph.number_of_nodes(),'edges':graph.number_of_edges(),'communities':len(communities),
        'semantic_agents':'Not used: focused code-only extraction; prior release graph used for initial orientation.', 'tokens':'not metered'}
(OUT/'audit.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in record.items() if k!='files'},ensure_ascii=False))
