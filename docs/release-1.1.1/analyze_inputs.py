from pathlib import Path
import json, collections, sys
O=Path('F:/SourceReadSwift/release-1.1.1')
if sys.argv[1]=='diagnostic':
 d=json.loads((O/'INPUT/轻阅书源诊断数据_1793472163.json').read_text(encoding='utf-8-sig'))
 rows=d['reports']; steps=[s for r in rows for s in r['steps']]
 counts=collections.Counter(s.get('failureCode','passed') for s in steps)
 print('REPORTS',len(rows),'TIMES',d['startedAt'],d['finishedAt'],'FAILURES',counts)
 print('STAGES',collections.Counter((s['stage'],s['status']) for s in steps))
 js=[s for s in steps if s.get('failureCode') in ['javascript','unsupported-rule','parse'] or 'js' in s.get('failureClassification','').lower()]
 print('JS/PARSE',json.dumps([(s.get('ruleSummary'),s.get('responseSummary')) for s in js][:25],ensure_ascii=False))
 (O/'diagnostic-summary.json').write_text(json.dumps({'reports':len(rows),'failureCodes':counts,'stages':{str(k):v for k,v in collections.Counter((s['stage'],s['status']) for s in steps).items()}},ensure_ascii=False,indent=2),encoding='utf-8')
elif sys.argv[1]=='video':
 import cv2
 from PIL import Image,ImageDraw
 p=Path('C:/Users/Edc21/Documents/xwechat_files/wxid_rpsqr5rjmyc222_4e8b/msg/video/2026-11/c61f508c150a5b34034c9fbf228988b0.mp4')
 c=cv2.VideoCapture(str(p)); fps=c.get(5); dur=c.get(7)/fps
 print('VIDEO',{'fps':fps,'duration':dur,'width':c.get(3),'height':c.get(4)})
 sheet=Image.new('RGB',(1200,700),'#dddddd'); draw=ImageDraw.Draw(sheet)
 for i in range(12):
  t=dur*i/12;c.set(0 if False else cv2.CAP_PROP_POS_MSEC,t*1000);ok,f=c.read()
  if not ok:continue
  im=Image.fromarray(cv2.cvtColor(f,cv2.COLOR_BGR2RGB));im.thumbnail((196,320));x=i%6*200;y=i//6*350
  sheet.paste(im,(x,y+22));draw.text((x+4,y+2),f'{t:.2f}s',fill='black')
 sheet.save(O/'video.jpg',quality=82);print(O/'video.jpg')
