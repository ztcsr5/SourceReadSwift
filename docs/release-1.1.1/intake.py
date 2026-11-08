from pathlib import Path
import collections, hashlib, json, shutil, subprocess

ROOT=Path(__file__).resolve().parents[2]
OUT=Path('F:/SourceReadSwift/release-1.1.1'); OUT.mkdir(parents=True,exist_ok=True)
baseline=OUT/'baseline.json'
if not baseline.exists():
    names=subprocess.check_output(['git','ls-files'],cwd=ROOT,text=True,encoding='utf-8').splitlines()
    manifest={}
    for name in names:
        src=ROOT/name
        if not src.is_file(): continue
        dst=OUT/'BASELINE'/name; dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
        manifest[name]=hashlib.sha256(dst.read_bytes()).hexdigest()
    baseline.write_text(json.dumps({'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'files':manifest},indent=2),encoding='utf-8')
print('BASELINE',json.loads(baseline.read_text())['head'])
for folder in [ROOT,ROOT.parent,Path('C:/Users/Edc21/Documents/IOS')]:
    p=folder/'AGENTS.md'
    if p.exists(): print('INSTRUCTIONS',p,p.read_text(encoding='utf-8'))
graph=Path('F:/SourceReadSwift/reader-toc-121/graphify-out/graph.json')
if graph.exists():
    d=json.loads(graph.read_text(encoding='utf-8')); nodes=d.get('nodes',[]); edges=d.get('links',d.get('edges',[]))
    ids={n['id'] for n in nodes if any(t in str(n) for t in ['SourceSwitch','TocFilterCache','SettingsView','ReaderView'])}
    print('GRAPH',len(nodes),len(edges),'selected',len(ids))
    print(json.dumps([n for n in nodes if n['id'] in ids][:14],ensure_ascii=False)[:4500])
paths=[Path('C:/Users/Edc21/Desktop/书源.json'),Path('C:/Users/Edc21/Documents/xwechat_files/wxid_rpsqr5rjmyc222_4e8b/msg/file/2026-11/轻阅书源诊断数据_1793472163.json')]
for i,p in enumerate(paths):
    print('INPUT',str(p),'exists',p.exists())
    if not p.exists(): continue
    raw=p.read_bytes(); dst=OUT/'INPUT'/p.name;dst.parent.mkdir(exist_ok=True);shutil.copy2(p,dst)
    d=json.loads(raw.decode('utf-8-sig'))
    print('BYTES/HASH',len(raw),hashlib.sha256(raw).hexdigest(),'TYPE',type(d).__name__)
    if isinstance(d,list):
        print('COUNT',len(d),'KEYS',list(d[0]) if d else [])
        print('TYPES',collections.Counter(str(x.get('bookSourceType')) for x in d))
    else:
        print('KEYS',[(k,type(v).__name__,len(v) if isinstance(v,(list,dict,str)) else v) for k,v in d.items()])
        (OUT/'diagnostic-schema.txt').write_text(json.dumps(d,ensure_ascii=False,indent=2)[:28000],encoding='utf-8')
print('READY',OUT)
