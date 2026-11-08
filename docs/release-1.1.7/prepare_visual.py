from pathlib import Path
import json, sys
from PIL import Image, ImageDraw

out=Path('F:/SourceReadSwift/release-1.1.7/native-evidence')
head=sys.argv[1]
folder=out/head
index=[]
for runtime in ['ios18-ui','ios26-ui']:
    root=folder/runtime
    if not (root/'manifest.json').exists(): continue
    manifest=json.loads((root/'manifest.json').read_text(encoding='utf8'))
    images=[]
    for test in manifest:
        for a in test['attachments']:
            name=a['suggestedHumanReadableName'].split('_0_')[0]
            path=root/a['exportedFileName']
            if not name.startswith('release117-') or path.suffix.lower() not in ('.png','.jpg','.jpeg'): continue
            dest=root/'named'/(name+path.suffix); dest.parent.mkdir(exist_ok=True)
            dest.write_bytes(path.read_bytes())
            images.append((name,dest)); index.append({'runtime':runtime,'name':name,'path':str(dest)})
    for i in range(0,len(images),2):
        batch=images[i:i+2]
        sheet=Image.new('RGB',(640,740),'#dddddd');draw=ImageDraw.Draw(sheet)
        for col,(name,path) in enumerate(batch):
            draw.text((col*320+4,4),name.replace('release117-',''),fill='black')
            im=Image.open(path).convert('RGB');im.thumbnail((312,706))
            sheet.paste(im,(col*320+(320-im.width)//2,28))
        path=folder/f'{runtime}-release117-{i//2}.jpg';sheet.save(path,quality=88,optimize=True)
        print(path)
(folder/'release117-screen-index.json').write_text(json.dumps(index,ensure_ascii=False,indent=2),encoding='utf8')
print('Screens',len(index))
