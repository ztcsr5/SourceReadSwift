"""Read bounded compatibility evidence and non-secret gateway identity.
Usage: python -X utf8 scripts/release117_closeout_intake.py [sources|gateway]
"""
from pathlib import Path
import json,re,sys,base64
ROOT=Path(__file__).resolve().parents[1]
mode=sys.argv[1] if len(sys.argv)>1 else 'sources'
def scrub(value):
    if isinstance(value,dict):return {k:('[REDACTED]' if re.search('token|secret|key|authorization|cookie|password',k,re.I) and k!='checkKeyWord' else scrub(v)) for k,v in value.items()}
    if isinstance(value,list):return [scrub(v) for v in value]
    if isinstance(value,str):
        value=re.sub(r'([?&](?:token|key|api_key|auth|secret)=)[^&\s]+',r'\1[REDACTED]',value,flags=re.I)
        return value
    return value
if mode=='sources':
    data=json.loads((ROOT/'SourceReadSwiftTests/Fixtures/comic-sources-20261101.json').read_text(encoding='utf-8'))
    for i in [1,3,5,6,10,17,18,29]:
        s=data[i]
        print('INDEX',i,json.dumps(scrub({k:s.get(k) for k in ['bookSourceName','bookSourceUrl','searchUrl','ruleSearch','ruleToc','ruleContent']}),ensure_ascii=False))
elif mode=='gateway':
    data=json.loads((Path.home()/'.workbuddy/models.json').read_text(encoding='utf-8'))
    for i,m in enumerate(data):
        identifiers={k:v for k,v in m.items() if k in ['id','name','model','modelId','displayName','url','provider','supportsImages']}
        if 'deepseek' in json.dumps(identifiers).lower():print('MODEL',i,json.dumps(identifiers,ensure_ascii=False))
elif mode=='comment':
    data=json.loads((ROOT/'SourceReadSwiftTests/Fixtures/comic-sources-20261101.json').read_text(encoding='utf-8'))
    source=data[6]
    script=source['ruleContent']['content']
    for encoded in re.findall(r"base64Decode\('([A-Za-z0-9+/=]+)'\)",script):
        nested=base64.b64decode(encoded).decode('utf-8')
        print('nested original rule',nested[:1400])
        for expected in re.findall(r"base64Decode\('([A-Za-z0-9+/=]+)'\)",nested)[:1]:
            marker=base64.b64decode(expected).decode('utf-8')
            comment=source.get('bookSourceComment','')
            print('guard marker',repr(marker),'comment length',len(comment),'contains',marker in comment,'other comment keys',[k for k in source if 'comment' in k.lower()])
