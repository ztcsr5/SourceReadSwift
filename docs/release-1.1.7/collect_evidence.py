from pathlib import Path
import io, json, zipfile, sys
import ci

filename=next((v for v in sys.argv[1:] if not v.startswith('--')), 'ci-status.json')
status=json.loads((ci.OUT/filename).read_text(encoding='utf8'))
ui_only='--ui-only' in sys.argv
head=status['head']
run=next(r for r in status['runs'] if r['name']=='iOS')
folder=ci.OUT/'native-evidence'/head
folder.mkdir(parents=True,exist_ok=True)
manifest=[]
artifacts=ci.ci.api(f"actions/runs/{run['id']}/artifacts")['artifacts']
prefixes=('ios-ui-snapshots-', 'ios26-ui-snapshots-') if ui_only else ('ios-test-evidence-', 'ios26-tab-evidence-')
for artifact in artifacts:
    if not artifact['name'].startswith(prefixes): continue
    name=artifact['name']
    archive=folder/(name+'.zip')
    print('EVIDENCE',name,artifact['size_in_bytes'],flush=True)
    if not archive.exists(): archive.write_bytes(ci.ci.signed_download(f"actions/artifacts/{artifact['id']}/zip"))
    native=name.startswith('ios26-')
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for member in z.namelist():
            p=Path(member)
            if p.name in ['xcodebuild-test.log','native-tab-test.log']:
                (folder/p.name).write_bytes(z.read(member))
            if (ui_only or 'ui-snapshots/' in member) and p.suffix.lower() in ['.png','.jpg','.jpeg','.json']:
                # Exported xcresult names are evidence only; flatten filenames.
                target=folder/('ios26-ui' if native else 'ios18-ui')/p.name
                target.parent.mkdir(parents=True,exist_ok=True)
                target.write_bytes(z.read(member))
                manifest.append({'runtime':'ios26' if native else 'ios18','member':member,'path':str(target)})
(folder/'extracted.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'head':head,'folder':str(folder),'files':len(manifest)},ensure_ascii=False))
