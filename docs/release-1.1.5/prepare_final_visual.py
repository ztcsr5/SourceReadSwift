from PIL import Image,ImageDraw
import ci
folder=ci.OUT/'native-evidence'/ci.ci.HEAD
sheet=Image.new('RGB',(1280,1272),'#dddddd')
def paste(runtime,name,x,y,width,limit=None):
    im=Image.open(folder/runtime/('density-'+name+'.png')).convert('RGB')
    if limit: im=im.crop((0,0,im.width,min(im.height,int(im.width*limit/(320 if name.endswith('320') else 390)))))
    im=im.resize((width,round(im.height*width/im.width)))
    ImageDraw.Draw(sheet).text((x+4,y+3),runtime[:5]+' / '+name,fill='black')
    sheet.paste(im,(x,y+22))
for i,runtime in enumerate(['ios18-ui','ios26-ui']):
    paste(runtime,'home-390',0,i*636,280)
    paste(runtime,'source-organization',280,i*636,280)
    paste(runtime,'sources-320',560,i*636,340)
    paste(runtime,'settings-dark',900,i*460,380,450)
paste('ios26-ui','sources-accessibility',900,920,380,330)
sheet.save(folder/'final-layout-review.jpg',quality=84,optimize=True)
print(folder/'final-layout-review.jpg')
