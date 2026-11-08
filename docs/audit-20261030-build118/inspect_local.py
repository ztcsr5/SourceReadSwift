import json
import sys
import collections
from pathlib import Path

if len(sys.argv) > 1:
    p=Path(sys.argv[1]); lines=p.read_text(encoding='utf-8-sig').splitlines()
    start=int(sys.argv[2]) if len(sys.argv)>2 else 1
    end=int(sys.argv[3]) if len(sys.argv)>3 else len(lines)
    for i in range(start-1,min(end,len(lines))): print(f'{i+1}: {lines[i]}')
else:
    p=next(Path('F:/Codex/.codex/sessions/2026/10/29').glob('*01a1870b-2d3c-7541-97a5-cf146a4daee9.jsonl'))
    counts=collections.Counter(); samples={}
    with p.open(encoding='utf8') as f:
        for i,line in enumerate(f):
            d=json.loads(line)
            if d.get('type')=='event_msg':
                sub=d.get('payload',{});typ=sub.get('type');counts[typ]+=1
                if typ not in samples: samples[typ]=list(sub)
                if typ=='item_completed':
                    item=sub.get('item',{});key='item:'+str(item.get('type'))
                    counts[key]+=1
                    if key not in samples:samples[key]=list(item)
            if d.get('type')=='response_item' and d.get('payload',{}).get('type')=='message':
                sub=d['payload'];key='message:'+sub.get('role','')
                if key not in samples: samples[key]={k:v for k,v in sub.items() if k!='content'};samples[key]['content_schema']=[{k:(str(v)[:80] if k!='text' else 'TEXT') for k,v in x.items()} for x in sub.get('content',[])[:1]]
    print('EVENT COUNTS',counts);print('SCHEMA',samples)
    root=Path(__file__).resolve().parents[2]/'SourceReadSwift/Features/Reader/graphify-out'
    if root.exists(): print('GRAPH FILES',[(p.name,p.stat().st_size) for p in root.iterdir()])
