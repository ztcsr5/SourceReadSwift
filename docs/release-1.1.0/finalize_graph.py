"""Focused current-source graph, reusing explicitly dated semantic review fragments."""
from pathlib import Path
import hashlib, json, subprocess
from graphify.extract import extract
from graphify.build import build_from_json
from graphify.cluster import cluster, score_all
from graphify.analyze import god_nodes, surprising_connections, suggest_questions
from graphify.report import generate
from graphify.export import to_json, to_html

DOC = Path(__file__).resolve().parent
ROOT = DOC.parents[1]
OUT = Path('F:/SourceReadSwift/release-1.1.0/graphify-out')
OUT.mkdir(parents=True, exist_ok=True)
BASE = '71156be1ac148d6328dccc2844ed2555a41313b0'
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT).decode().strip()
names = subprocess.check_output(['git', 'diff', '--name-only', BASE, head], cwd=ROOT).decode().splitlines()
files = [ROOT / name for name in names if name.endswith('.swift')]
detection = {'total_files': len(files), 'total_words': sum(len(p.read_text(encoding='utf8').split()) for p in files),
             'files': {'code': [str(p) for p in files]}, 'skipped_sensitive': []}
(OUT / 'graph-detection.json').write_text(json.dumps(detection, ensure_ascii=False, indent=2), encoding='utf8')
data = extract(files, parallel=False)
(OUT / 'graph-ast.json').write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf8')
data.setdefault('hyperedges', [])
provenance = []
for kind in ('reader', 'performance', 'product'):
    path = DOC / f'graph-{kind}.json'
    fragment = json.loads(path.read_text(encoding='utf8'))
    for edge in fragment.get('edges', []) + fragment.get('hyperedges', []):
        if edge.get('confidence_tag'):
            edge['confidence_score'] = edge.get('confidence', 0.2)
            edge['confidence'] = edge['confidence_tag']
    for key in ('nodes', 'edges', 'hyperedges'):
        data.setdefault(key, []).extend(fragment.get(key, []))
    provenance.append({'fragment': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                       'scope': 'Semantic review from this release investigation; findings are hypotheses/resolutions, not current-runtime proof.'})
data['nodes'] = list({n['id']: n for n in data['nodes']}.values())
node_files = {n['id']: n.get('source_file', '') for n in data['nodes']}
for edge in data['edges']:
    edge.setdefault('source_file', node_files.get(edge['source'], ''))
(OUT / 'graph-extraction.json').write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf8')
graph = build_from_json(data)
communities = cluster(graph)
cohesion = score_all(graph, communities)
labels = {}
for cid, members in communities.items():
    terms = ' '.join(str(graph.nodes[n].get('label', n)) for n in members).lower()
    label = ('网页与章节状态' if 'webreader' in terms or 'scroll' in terms else
             '正文排版' if 'typography' in terms or 'paginator' in terms else
             '搜索与详情' if 'detail' in terms or 'discover' in terms else
             '外观与设置' if 'theme' in terms or 'setting' in terms else '集成与回归')
    labels[cid] = f'{label} {cid}'
report = generate(graph, communities, cohesion, labels, god_nodes(graph),
                  surprising_connections(graph, communities), detection, {'input': 0, 'output': 0}, str(ROOT),
                  suggested_questions=suggest_questions(graph, communities, labels))
report = (f'> 当前源码提交：{head}。范围：{len(files)} 个改动 Swift 文件；复用本轮三个语义审查分片，'
          '不等于全项目逐行审计。子代理 token 未计量；报告中的 0 不表示实际零成本。'
          '语义发现是否解决请查 ISSUES.md 和原生测试证据，图中的推断边不是运行验证。\n\n' + report)
(OUT / 'GRAPH_REPORT.md').write_text(report, encoding='utf8')
to_json(graph, communities, str(OUT / 'graph.json'))
to_html(graph, communities, str(OUT / 'graph.html'), community_labels=labels)
(OUT / 'graph-analysis.json').write_text(json.dumps({'head': head, 'provenance': provenance,
    'communities': communities, 'labels': labels, 'cohesion': cohesion, 'tokens': 'not metered'}, ensure_ascii=False, indent=2), encoding='utf8')
print('GRAPH', graph.number_of_nodes(), 'nodes', graph.number_of_edges(), 'edges', len(communities), 'communities', OUT)
