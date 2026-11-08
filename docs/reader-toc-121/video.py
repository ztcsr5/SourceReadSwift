import cv2, json
from PIL import Image, ImageDraw
from pathlib import Path
src='C:/Users/Edc21/Documents/Tencent Files/2865460461/nt_qq/nt_data/Video/2026-10/Ori/56f63ab59cd249af0d690b374e0a839f.mp4'
out=Path('F:/SourceReadSwift/reader-toc-121');out.mkdir(exist_ok=True,parents=True)
cap=cv2.VideoCapture(src)
fps=cap.get(cv2.CAP_PROP_FPS);count=cap.get(cv2.CAP_PROP_FRAME_COUNT)
duration=count/fps
print(json.dumps({'fps':fps,'frames':count,'seconds':duration,'width':cap.get(3),'height':cap.get(4)}))
times=[float(v) for v in __import__('sys').argv[1:]] or [duration*i/17 for i in range(18)]
sheet=Image.new('RGB',(6*200,3*440),'#dddddd');draw=ImageDraw.Draw(sheet)
for i,t in enumerate(times):
 cap.set(cv2.CAP_PROP_POS_MSEC,t*1000);ok,frame=cap.read()
 if not ok: continue
 im=Image.fromarray(cv2.cvtColor(frame,cv2.COLOR_BGR2RGB));im.thumbnail((196,414))
 x=(i%6)*200;y=(i//6)*440
 sheet.paste(im,(x,y+22));draw.text((x+4,y+4),f'{t:.2f}s',fill='black')
name='video-detail.jpg' if __import__('sys').argv[1:] else 'video-contact.jpg'
sheet.save(out/name,quality=80)
print(out/name)
