from pathlib import Path
import requests, hashlib, json
from fontTools.ttLib import TTFont
root=Path(__file__).resolve().parents[2]
dest=root/'SourceReadSwift/Resources/Fonts';dest.mkdir(parents=True,exist_ok=True)
records=[]
for directory,name in [('mashanzheng','MaShanZheng-Regular'),('zhimangxing','ZhiMangXing-Regular')]:
 base=f'https://raw.githubusercontent.com/google/fonts/main/ofl/{directory}/'
 for remote,local in [(name+'.ttf',name+'.ttf'),('OFL.txt',name+'-OFL.txt')]:
  p=dest/local
  if not p.exists():
   r=requests.get(base+remote,timeout=90);r.raise_for_status();p.write_bytes(r.content)
  row={'file':local,'source':base+remote,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
  if p.suffix=='.ttf':
   font=TTFont(p);row['postscript']=font['name'].getDebugName(6)
   row['glyphs']=len(font.getBestCmap());font.close()
  records.append(row)
out=Path('F:/SourceReadSwift/release-1.1.1/font-manifest.json')
out.write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf8')
print(out.read_text(encoding='utf8'))
