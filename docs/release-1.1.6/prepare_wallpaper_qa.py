from pathlib import Path
from PIL import Image,ImageDraw
import json,shutil
root=Path(__file__).resolve().parents[2]
out=Path('F:/SourceReadSwift/release-1.1.6')
canvas=Image.new('RGB',(1120,650),'#dddddd');draw=ImageDraw.Draw(canvas)
manifest=[]
prompts={
'Bamboo':'Original portrait reading wallpaper, pale ivory handmade paper, sage bamboo ink-wash leaves confined to extreme corners, central 85 percent empty and calm, no text, UI, borders or logos.',
'Mountains':'Original portrait reading wallpaper, misty warm-white rice paper, distant pale grey-green ink-wash mountains confined to bottom 12 percent and extreme edges, central 85 percent empty for black reading text, no text, UI, borders or logos.',
'Ginkgo':'Original portrait reading wallpaper, warm cream paper with very pale golden ginkgo watercolor leaves confined to corners, central 85 percent empty and calm, no text, UI, borders or logos.',
'Tide':'Original portrait reading wallpaper, pale cool-blue paper, subtle coastal watercolor tide confined to bottom 8 percent and extreme edges, central 85 percent empty and calm, no text, UI, borders or logos.'}
for i,name in enumerate(prompts):
 p=root/f'SourceReadSwift/App/Assets.xcassets/Reading{name}.imageset/{name}.png'
 im=Image.open(p);im.thumbnail((260,600));canvas.paste(im,(10+i*280,30));draw.text((10+i*280,8),name,fill='black')
 manifest.append({'name':name,'tool':'built-in image_gen.imagegen','purpose':'Original reader background; no third-party artwork copied','design_brief':prompts[name],'file':str(p)})
canvas.save(out/'wallpaper-qa.jpg',quality=90)
(out/'wallpaper-generation-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
shutil.copyfile(root/'docs/release-1.1.5/collect_evidence.py',root/'docs/release-1.1.6/collect_evidence.py')
print(out/'wallpaper-qa.jpg')
