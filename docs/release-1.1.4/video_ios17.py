from pathlib import Path
import cv2,json,hashlib,sys
from PIL import Image,ImageDraw
src=Path('C:/Users/Edc21/Documents/Tencent Files/2865460461/nt_qq/nt_data/Video/2026-11/Ori/81df71fe9cb4fce20aacdc3a39691e68.mp4')
out=Path('F:/SourceReadSwift/release-1.1.4/ios17-video');out.mkdir(parents=True,exist_ok=True)
cap=cv2.VideoCapture(str(src))
fps=cap.get(cv2.CAP_PROP_FPS);count=cap.get(cv2.CAP_PROP_FRAME_COUNT)
assert fps>0 and count>0,'Cannot read supplied video'
duration=count/fps
record={'source':str(src),'sha256':hashlib.file_digest(src.open('rb'),'sha256').hexdigest(),'fps':fps,'frames':count,'seconds':duration,'width':cap.get(3),'height':cap.get(4)}
(out/'metadata.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
times=[float(x) for x in sys.argv[1:]] or [max(0,duration-.2)*i/14 for i in range(15)]
sheet=Image.new('RGB',(1000,1245),'#dddddd');draw=ImageDraw.Draw(sheet)
for i,t in enumerate(times):
 cap.set(cv2.CAP_PROP_POS_MSEC,t*1000);ok,frame=cap.read()
 if not ok:continue
 im=Image.fromarray(cv2.cvtColor(frame,cv2.COLOR_BGR2RGB));im.thumbnail((196,390))
 x=(i%5)*200;y=(i//5)*415;sheet.paste(im,(x,y+22));draw.text((x+4,y+4),f'{t:.2f}s',fill='black')
sheet.save(out/'contact.jpg',quality=82)
print(json.dumps(record,ensure_ascii=False));print(out/'contact.jpg')
