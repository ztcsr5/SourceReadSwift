from PIL import Image
import json
import ci
folder=ci.OUT/'native-evidence'/ci.ci.HEAD
for runtime in ['ios18-ui','ios26-ui']:
    p=folder/runtime
    if not (p/'manifest.json').exists(): continue
    manifest=json.loads((p/'manifest.json').read_text(encoding='utf8'))
    images={a['suggestedHumanReadableName'].split('_0_')[0]:p/a['exportedFileName'] for t in manifest for a in t['attachments']}
    pixels={}
    for name in ['settings-dark','settings-390']:
        im=Image.open(images['density-'+name]).convert('RGBA')
        pixel=im.getpixel((round(im.width*0.025),round(im.width*0.4)))
        pixels[name]=pixel
        assert pixel[3]>200,(runtime,name,pixel)
    assert sum(pixels['settings-dark'][:3])<240,(runtime,pixels)
    assert sum(pixels['settings-390'][:3])>600,(runtime,pixels)
    print(runtime,pixels,'PASS actual dark/light raster contrast')
