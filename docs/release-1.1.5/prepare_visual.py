from pathlib import Path
import json,shutil
from PIL import Image,ImageDraw,ImageFont
import ci
folder=ci.OUT/'native-evidence'/ci.ci.HEAD
tiles=[]
order=['home-390','settings-390','sources-390','source-organization','settings-accessibility',
       'home-320','settings-320','sources-320','settings-dark','sources-accessibility']
for runtime in ['ios18-ui','ios26-ui']:
    p=folder/runtime
    manifest=json.loads((p/'manifest.json').read_text(encoding='utf8'))
    images={}
    for test in manifest:
        for a in test['attachments']:
            name=a['suggestedHumanReadableName'].split('_0_')[0].removeprefix('density-')
            if name not in order:continue
            source=p/a['exportedFileName']
            target=p/('density-'+name+'.png');shutil.copyfile(source,target)
            images[name]=target
    assert set(images)==set(order),(runtime,images.keys())
    for name in order:
        im=Image.open(images[name]).convert('RGB')
        # A review contact sheet, not a modified product screenshot. Original
        # full-height attachments remain alongside it for reproducibility.
        crop_height=min(im.height,int(im.width*450/(320 if name.endswith('320') else 390)))
        im=im.crop((0,0,im.width,crop_height))
        im.thumbnail((250,292))
        tile=Image.new('RGB',(256,318),'#dddddd')
        ImageDraw.Draw(tile).text((4,3),runtime[:5]+' / '+name,fill='black')
        tile.paste(im,((256-im.width)//2,22))
        tiles.append(tile)
sheet=Image.new('RGB',(1280,1272),'white')
for i,tile in enumerate(tiles):sheet.paste(tile,((i%5)*256,(i//5)*318))
sheet.save(folder/'layout-review.jpg',quality=84,optimize=True)
print(folder/'layout-review.jpg')
