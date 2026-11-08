from pathlib import Path
import json,re,time,requests,ssl

out=Path('F:/SourceReadSwift/release-1.1.7/comic-mht');out.mkdir(parents=True,exist_ok=True)
session=requests.Session();session.headers['User-Agent']='Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1'
# Use the machine trust store in addition to certifi; never disable TLS checks.
roots=Path(requests.certs.where()).read_bytes()
for cert,encoding,trust in ssl.enum_certificates('ROOT'):
    if encoding=='x509_asn': roots += b'\n'+ssl.DER_cert_to_PEM_cert(cert).encode('ascii')
ca=out/'machine-ca.pem';ca.write_bytes(roots);session.verify=str(ca)
rows=[]
def get(name,url):
    start=time.monotonic()
    r=session.get(url,timeout=12)
    (out/(name+'.bin')).write_bytes(r.content)
    rows.append(dict(stage=name,url=r.url,status=r.status_code,type=r.headers.get('content-type'),bytes=len(r.content),seconds=round(time.monotonic()-start,2)))
    print(rows[-1],flush=True)
    return r
try:
    r=get('search','https://m.manhuatai.com/api/serachcomic/?product_id=2&productname=mht&platformname=wap&serachKey=%E9%95%BF%E7%9B%B8%E6%80%9D&topNumber=11')
    data=r.json()
    def first(node):
        if isinstance(node,dict):
            if 'comic_newid' in node:return node
            for value in node.values():
                if (v:=first(value)):return v
        if isinstance(node,list):
            for value in node:
                if (v:=first(value)):return v
    book=first(data)
    if book:
        print({k:book.get(k) for k in ['comic_newid','comic_id','comic_name']})
        page=get('toc','https://m.manhuatai.com/'+str(book['comic_newid'])+'/')
        ids=re.findall(r'href=[\"\'](?:https://m\.manhuatai\.com)?/'+re.escape(str(book['comic_newid']))+r'/([^\"\'/]+)\.html',page.text)
        if ids:
            url='https://m.manhuatai.com/api/getchapterinfov2?product_id=2&productname=mht&platformname=wap&comic_id='+str(book['comic_id'])+'&chapter_newid='+ids[0]+'&isWebp=1&quality=low'
            chapter=get('content',url)
            print(chapter.text[:1500])
except Exception as e:
    rows.append(dict(error=type(e).__name__,message=str(e)[:900]))
    print(rows[-1])
finally:
    (out/'requests.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf8')
