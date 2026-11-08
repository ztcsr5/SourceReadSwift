from PIL import Image, ImageStat
import json
import ci

folder = ci.OUT/'native-evidence'/ci.ci.HEAD
screens = json.loads((folder/'screen-index.json').read_text(encoding='utf8'))
checks = []
colours = {'classic':('F2F2F7','000000'), 'botanical':('EFF3EA','101B15'),
           'editorial':('F3EFE6','1B1813'), 'coast':('EDF4F8','101C25'),
           'rose':('F8EFF1','23171E'), 'graphite':('ECEDEF','141518')}
for runtime in ['ios18-ui','ios26-ui']:
    images = {r['name']:r for r in screens if r['runtime']==runtime}
    for theme, pair in colours.items():
        for style, hexvalue in zip(['light','dark'],pair):
            name = f'release116-theme-{theme}-{style}'
            im = Image.open(images[name]['path']).convert('RGBA')
            pixel = im.getpixel((5,im.height//2))
            expected = tuple(int(hexvalue[i:i+2],16) for i in (0,2,4))
            assert pixel[3] == 255 and max(abs(a-b) for a,b in zip(pixel[:3],expected)) <= 5, (runtime,name,pixel,expected)
            checks.append({'runtime':runtime,'name':name,'pixel':pixel,'expected':expected,'result':'PASS'})
    for name in ['release116-reader-top-white','release116-reader-top-bamboo']:
        im = Image.open(images[name]['path']).convert('RGB')
        scale = im.width/390
        safe_area = ImageStat.Stat(im.crop((0,0,im.width,int(40*scale))))
        assert max(safe_area.stddev) < 1, (runtime,name,'Nonuniform top safe area',safe_area.stddev)
        body = im.crop((int(16*scale),int(170*scale),im.width-int(16*scale),int(600*scale)))
        dark = sum(max(pixel)<100 for pixel in body.getdata())
        assert dark > 200, (runtime,name,'Reader body did not render',dark)
        checks.append({'runtime':runtime,'name':name,'safe_area_stddev':safe_area.stddev,'dark_body_pixels':dark,'result':'PASS'})
(folder/'visual-pixel-checks.json').write_text(json.dumps({'head':ci.ci.HEAD,'checks':checks},indent=2),encoding='utf8')
print('PASS actual dark/light paper colours, opaque safe area, nonblank reader body:',len(checks),'checks')
