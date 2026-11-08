from pathlib import Path
import hashlib,json,re,shutil
p=Path('D:/QQ游戏/Analytics-2026-10-26-080012.ips.ca.synced')
out=Path('F:/SourceReadSwift/release-1.1.4/ios17-video')
shutil.copy2(p,out/p.name)
raw=p.read_text(encoding='utf-8-sig',errors='replace')
decoder=json.JSONDecoder();objects=[];rest=raw
while rest.strip():
    obj,end=decoder.raw_decode(rest.lstrip());objects.append(obj);rest=rest.lstrip()[end:]
def expand(value,depth=0):
    if depth>8:return value
    if isinstance(value,dict):return {k:expand(v,depth+1) for k,v in value.items()}
    if isinstance(value,list):return [expand(v,depth+1) for v in value]
    if isinstance(value,str) and value.lstrip().startswith(('{','[')):
        try:return expand(json.loads(value),depth+1)
        except (ValueError,TypeError):pass
    return value
normalized=json.dumps(expand(objects),ensure_ascii=False)
result={'path':str(p),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),
        'objects':len(objects),'header':{k:objects[0].get(k) for k in ['bug_type','timestamp','os_version']},
        'record_shapes':[list(v)[:14] if isinstance(v,dict) else type(v).__name__ for v in objects[:4]],
        'matches':[],'encoding_check':'Nested JSON messages decoded, Unicode escapes normalized before matching.'}
for term in ['SourceReadSwift','com.edc21','纸间','faultingThread']:
    hits=list(re.finditer(re.escape(term),normalized,re.I))
    result['matches'].append({'term':term,'count':len(hits)})
(out/'analytics-check.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(result,ensure_ascii=False,indent=2))
