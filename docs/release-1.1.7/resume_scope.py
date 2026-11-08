from pathlib import Path
import json,re,sys,tomllib,base64,collections
ROOT=Path(__file__).resolve().parents[2];OUT=Path('F:/SourceReadSwift/release-1.1.7')
mode=sys.argv[1]
if mode=='graph':
 data=json.loads((OUT/'graphify-out/graph.json').read_text(encoding='utf-8'))
 nodes={n['id']:n for n in data['nodes']}
 found={k for k,n in nodes.items() if any(s in n.get('label','').lower() for s in ['comic','website','aichat'])}
 for k in sorted(found)[:40]:print(nodes[k])
 print('matching nodes',len(found))
elif mode=='gateway':
 for p in [Path.home()/'.workbuddy/settings.json',Path.home()/'.workbuddy/models.json',Path.home()/'.codex/config.toml']:
  if not p.exists():continue
  print('FILE',p)
  data=tomllib.loads(p.read_text(encoding='utf-8')) if p.suffix=='.toml' else json.loads(p.read_text(encoding='utf-8'))
  def walk(value,path='',depth=0):
   if depth>8:return
   if isinstance(value,dict):
    for k,v in value.items():
     key=path+'.'+k
     if re.search('key|token|secret|authorization|credential|cookie|password',k,re.I):
      print(key,'[credential field present]' if v else '[empty]');continue
     walk(v,key,depth+1)
   elif isinstance(value,list):
    print(path,'list',len(value))
    for i,v in enumerate(value[:60]):walk(v,path+'.'+str(i),depth+1)
   elif isinstance(value,str):
    if re.search(r'url|endpoint|host|port|model|provider|gateway',path,re.I):
     safe=re.sub(r'(?<=://)[^/@\s]+:[^/@\s]+@','[REDACTED]@',value)
     safe=re.sub(r'([?&](?:key|token|api_key|auth|secret)=)[^&\s]+',r'\1[REDACTED]',safe,flags=re.I)
     print(path,safe[:250])
   elif isinstance(value,(bool,int,float)) and re.search('model|gateway|proxy|port',path,re.I):print(path,value)
  walk(data)
elif mode=='comics':
 status=json.loads((OUT/'ci-a37e8b8.json').read_text(encoding='utf-8'))
 run=next(r for r in status['runs'] if r['name']=='iOS')
 job=next(j for j in run['jobs'] if j['name']=='build')
 log=(OUT/f"job-{job['id']}.log").read_text(encoding='utf-8',errors='replace')
 rows={}
 for b64 in re.findall(r'COMIC_ROW_B64 ([A-Za-z0-9+/=]+)',log):
  row=json.loads(base64.b64decode(b64));rows[row['index']]=row
 rows=list(rows.values());target=OUT/'source-audit'/status['head'];target.mkdir(parents=True,exist_ok=True)
 (target/'comic-pipeline-31.json').write_text(json.dumps({'head':status['head'],'rows':rows},ensure_ascii=False,indent=2),encoding='utf-8')
 print('ROWS',len(rows),'decoded',sum(bool(r.get('decoded')) for r in rows))
 for r in rows:print(json.dumps({k:v for k,v in r.items() if k in ['index','name','stage','decoded','message','sourceUrl','imageUrl','keyword']},ensure_ascii=False))
