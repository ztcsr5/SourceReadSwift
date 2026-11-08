"""Merge structural extraction and reviewed semantic edges into Graphify outputs."""
import json
from pathlib import Path

OUT=Path(__file__).resolve().parent

def main():
    from graphify.build import build_from_json
    from graphify.cluster import cluster,score_all
    from graphify.analyze import god_nodes,surprising_connections,suggest_questions
    from graphify.report import generate
    from graphify.export import to_json,to_html
    extraction=json.loads((OUT/'graph-ast.json').read_text(encoding='utf8'))
    extraction.setdefault('hyperedges',[])
    for path in OUT.glob('graph-*.json'):
        if path.name in ('graph-ast.json','graph-detection.json','graph-analysis.json','graph-extraction.json'):continue
        fragment=json.loads(path.read_text(encoding='utf8'))
        if not isinstance(fragment,dict) or 'nodes' not in fragment:continue
        extraction['nodes'].extend(fragment.get('nodes',[]))
        extraction['edges'].extend(fragment.get('edges',[]))
        extraction['hyperedges'].extend(fragment.get('hyperedges',[]))
    extraction['nodes']=list({n['id']:n for n in extraction['nodes']}.values())
    (OUT/'graph-extraction.json').write_text(json.dumps(extraction,ensure_ascii=False,indent=2),encoding='utf8')
    graph=build_from_json(extraction)
    communities=cluster(graph)
    cohesion=score_all(graph,communities)
    labels={}
    for cid,members in communities.items():
        words=' '.join(str(graph.nodes[n].get('label',n)) for n in members)
        if any(w in words for w in ('CoverPageHost','PageCurl','settlePage')):label='翻页与控制器'
        elif any(w in words for w in ('Paginator','Typography','Geometry','LayoutEngine')):label='排版与几何'
        elif any(w in words for w in ('History','Build118','CI','Antigravity')):label='历史与验证'
        elif 'Speech' in words or 'Audio' in words:label='朗读与音频'
        elif 'WebReader' in words or 'WebScroll' in words:label='网页滚动渲染'
        elif 'ReaderView' in words:label='阅读会话集成'
        else:label='阅读器组件'
        labels[cid]=f'{label} {cid}'
    gods=god_nodes(graph);surprises=surprising_connections(graph,communities)
    questions=suggest_questions(graph,communities,labels)
    detection=json.loads((OUT/'graph-detection.json').read_text(encoding='utf8'))
    report=generate(graph,communities,cohesion,labels,gods,surprises,detection,{'input':0,'output':0},str(OUT.parents[1]),suggested_questions=questions)
    report='> 范围：25个阅读器Swift文件的结构提取，加上已核对的历史/审查语义分片。不是全项目业务正确性证明；token usage未从子代理取得，未统计。\n\n'+report
    (OUT/'GRAPH_REPORT.md').write_text(report,encoding='utf8')
    to_json(graph,communities,str(OUT/'graph.json'))
    to_html(graph,communities,str(OUT/'graph.html'),community_labels=labels)
    (OUT/'graph-analysis.json').write_text(json.dumps({'communities':communities,'labels':labels,'cohesion':cohesion},ensure_ascii=False,indent=2),encoding='utf8')
    print('GRAPH',graph.number_of_nodes(),'nodes',graph.number_of_edges(),'edges',len(communities),'communities')

if __name__=='__main__':main()
