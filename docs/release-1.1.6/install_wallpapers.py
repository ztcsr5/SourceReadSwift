from pathlib import Path
import hashlib,json,shutil
R=Path(__file__).resolve().parents[2]
S=Path('C:/Users/Edc21/.codex/generated_images/01a18d70-2f1a-73d0-9377-247ba1da1bba')
assets={'Bamboo':'exec-4b5b7af0-e0e5-4276-998c-af5fb8264395.png','Mountains':'exec-72a23ded-fd3c-4694-ac9e-949ad0ebf739.png','Ginkgo':'exec-fec2c672-6242-4723-b977-d1f5a7267d10.png','Tide':'exec-dea2299a-a1d4-4faf-93ea-997d770449f4.png'}
records=[]
for name,file in assets.items():
    folder=R/'SourceReadSwift/App/Assets.xcassets'/('Reading'+name+'.imageset');folder.mkdir(parents=True,exist_ok=True)
    target=folder/(name+'.png');assert not target.exists();shutil.copy2(S/file,target)
    (folder/'Contents.json').write_text(json.dumps({'images':[{'filename':target.name,'idiom':'universal'}],'info':{'author':'xcode','version':1}},indent=2),encoding='utf8')
    records.append({'name':name,'file':str(target),'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'generation':'built-in image_gen, original raster artwork'})
(Path('F:/SourceReadSwift/release-1.1.6')/'wallpapers.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(records,ensure_ascii=False))
