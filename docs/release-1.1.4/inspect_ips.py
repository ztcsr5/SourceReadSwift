"""Read Apple crash/Jetsam .ips JSON without guessing a symbol or exception."""
import json,sys
from pathlib import Path
if len(sys.argv)!=2:
    raise SystemExit('Usage: python -X utf8 docs/release-1.1.4/inspect_ips.py PATH_TO_IPS')
path=Path(sys.argv[1]);raw=path.read_text(encoding='utf-8-sig',errors='replace')
decoder=json.JSONDecoder();parts=[]
while raw.strip():
    obj,end=decoder.raw_decode(raw.lstrip());parts.append(obj);raw=raw.lstrip()[end:]
header=parts[0];body=parts[-1]
keys=['app_name','app_version','build_version','bundleID','timestamp','os_version','bug_type',
      'procName','captureTime','modelCode','osVersion','bundleInfo','exception','termination',
      'faultingThread','asi','lastExceptionBacktrace']
result={key:body.get(key,header.get(key)) for key in keys if key in body or key in header}
threads=body.get('threads',[])
fault=body.get('faultingThread')
for i,thread in enumerate(threads):
    if thread.get('triggered') or i==fault:
        frames=[];images=body.get('usedImages',[])
        for frame in thread.get('frames',[])[:30]:
            row=dict(frame);index=row.get('imageIndex')
            if isinstance(index,int) and 0<=index<len(images):
                image=images[index]
                row['image']={key:image.get(key) for key in ['name','uuid','base','arch']}
            frames.append(row)
        result['triggeredThread']={'index':i,'queue':thread.get('queue'),'frames':frames}
        break
if 'largestProcess' in body: result['largestProcess']=body['largestProcess']
print(json.dumps(result,ensure_ascii=False,indent=2))
