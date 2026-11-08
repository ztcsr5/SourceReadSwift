"""Inspect and refresh failed comic endpoints without login/TLS bypass.
Usage: python -X utf8 scripts/release117_comic_evidence.py [--probe]
Only bounded public sample bodies are saved; credentials/cookies are not logged.
"""
from pathlib import Path
import json,requests,re,sys,hashlib,time,ssl
OUT=Path('F:/SourceReadSwift/release-1.1.7/closeout34');OUT.mkdir(parents=True,exist_ok=True)
data=json.loads(Path('F:/SourceReadSwift/release-1.1.7/source-audit/a37e8b871a718c41aab3246c699e7344a93f212f/comic-pipeline-31.json').read_text(encoding='utf-8'))['rows']
rows={r['index']:r for r in data}
for i in [1,3,5,6,17,29]:
    r=rows[i];print(json.dumps({k:r.get(k) for k in ['index','name','stage','chapterTitle','imageCount','firstImageURL','contentPreview','message']},ensure_ascii=False))
if '--probe' not in sys.argv:raise SystemExit()
session=requests.Session();session.headers['User-Agent']='Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1'
roots=Path(requests.certs.where()).read_bytes()
for cert,encoding,trust in ssl.enum_certificates('ROOT'):
    if encoding=='x509_asn':roots+=b'\n'+ssl.DER_cert_to_PEM_cert(cert).encode('ascii')
ca=OUT/'machine-ca.pem';ca.write_bytes(roots);session.verify=str(ca)
targets=[('mangadex','https://api.mangadex.org/manga?limit=2&title=One%20Piece'),
         ('mht-search','https://m.manhuatai.com/api/serachcomic/?product_id=2&productname=mht&platformname=wap&serachKey=%E9%95%BF%E7%9B%B8%E6%80%9D&topNumber=11')]
targets +=[(f'image-{i}',rows[i]['firstImageURL']) for i in [3,6,29] if rows[i].get('firstImageURL')]
records=[]
for name,url in targets:
    rec={'name':name,'url':url};start=time.monotonic()
    try:
        with session.get(url,timeout=(8,12),stream=True) as response:
            body=b''
            for chunk in response.iter_content(65536):
                body+=chunk
                if len(body)>1_000_000:body=body[:1_000_000];break
            (OUT/(name+'.bin')).write_bytes(body)
            rec.update(status=response.status_code,content_type=response.headers.get('content-type'),bytes=len(body),sha256=hashlib.sha256(body).hexdigest(),url=response.url)
            if 'json' in response.headers.get('content-type','') or 'text' in response.headers.get('content-type',''):rec['head']=body[:500].decode('utf-8',errors='replace')
    except requests.RequestException as error:
        rec.update(error=type(error).__name__,message=str(error)[:350])
    rec['seconds']=round(time.monotonic()-start,2);records.append(rec);print(json.dumps(rec,ensure_ascii=False),flush=True)
(OUT/'endpoint-probes.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
