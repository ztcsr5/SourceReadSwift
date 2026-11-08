from pathlib import Path
import json
from graphify.build import build_from_json
out=Path('F:/SourceReadSwift/release-1.1.7/graphify-out')
old=json.loads((out/'graph.json').read_text(encoding='utf-8'))
new=build_from_json(json.loads((out/'extraction.json').read_text(encoding='utf-8')))
old_nodes={n['id']:n for n in old['nodes']}
print('removed',*[old_nodes[n] for n in old_nodes.keys()-set(new.nodes)],sep='\n')
print('added',*[new.nodes[n] for n in set(new.nodes)-old_nodes.keys()],sep='\n')
