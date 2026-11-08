from pathlib import Path
import io, json, zipfile
import ci

status=json.loads((ci.OUT/'ci-status.json').read_text(encoding='utf8'))
assert status['head']==ci.ci.HEAD
run=next(r for r in status['runs'] if r['name']=='iOS')
folder=ci.OUT/'native-evidence'/ci.ci.HEAD
folder.mkdir(parents=True,exist_ok=True)
manifest=[]
for artifact in ci.ci.api(f"actions/runs/{run['id']}/artifacts")['artifacts']:
    if not artifact['name'].startswith(('ios-test-evidence-', 'ios26-tab-evidence-')): continue
    name=artifact['name']
    archive=folder/(name+'.zip')
    if not archive.exists(): archive.write_bytes(ci.ci.signed_download(f"actions/artifacts/{artifact['id']}/zip"))
    native=name.startswith('ios26-')
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for member in z.namelist():
            p=Path(member)
            if p.name in ['xcodebuild-test.log','native-tab-test.log']:
                (folder/p.name).write_bytes(z.read(member))
            if 'ui-snapshots/' in member and p.suffix.lower() in ['.png','.jpg','.jpeg','.json']:
                # Exported xcresult names are evidence only; flatten filenames.
                target=folder/('ios26-ui' if native else 'ios18-ui')/p.name
                target.parent.mkdir(parents=True,exist_ok=True)
                target.write_bytes(z.read(member))
                manifest.append({'runtime':'ios26' if native else 'ios18','member':member,'path':str(target)})
(folder/'extracted.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'head':ci.ci.HEAD,'folder':str(folder),'files':len(manifest)},ensure_ascii=False))
