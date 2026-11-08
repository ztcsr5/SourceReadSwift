from pathlib import Path
import hashlib,io,json,plistlib,sys,zipfile
from ci_status import api,signed_download,OUT,HEAD

release='--release' in sys.argv
status=json.loads((OUT/'ci-status.json').read_text(encoding='utf8'))
assert status['head']==HEAD
runs={r['name']:r for r in status['runs']}
package=runs['Unsigned IPA'];assert package['conclusion']=='success' and package['head_sha']==HEAD
if release:assert runs['iOS']['conclusion']=='success' and runs['iOS']['head_sha']==HEAD
artifacts=api(f"actions/runs/{package['id']}/artifacts")['artifacts']
for artifact in artifacts:
    archive=signed_download(f"actions/artifacts/{artifact['id']}/zip")
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        names=[n for n in z.namelist() if n.lower().endswith('.ipa')]
        if not names:continue
        assert len(names)==1
        ipa=z.read(names[0])
    break
else:raise SystemExit('No IPA in successful package artifacts')
sha=hashlib.sha256(ipa).hexdigest()
with zipfile.ZipFile(io.BytesIO(ipa)) as z:
    assert z.testzip() is None
    plists=[n for n in z.namelist() if n.startswith('Payload/') and n.count('/')==2 and n.endswith('.app/Info.plist')]
    assert len(plists)==1,plists
    info=plistlib.loads(z.read(plists[0]))
assert info['CFBundleShortVersionString']=='1.0.119' and info['CFBundleVersion']=='119'
folder=OUT/'CI-CANDIDATE'/HEAD;folder.mkdir(parents=True,exist_ok=True)
path=folder/'SourceReadSwift-1.0.119-unsigned.ipa';path.write_bytes(ipa)
if release:
    path=Path('C:/Users/Edc21/Desktop/SourceReadSwift-1.0.119-unsigned.ipa')
    if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest()!=sha:
        raise SystemExit('Existing desktop IPA differs; not overwriting it.')
    path.write_bytes(ipa)
record={'commit':HEAD,'package_run':package['id'],'ios_run':runs['iOS']['id'],
        'native_tests_success':runs['iOS']['conclusion']=='success','release':release,
        'path':str(path),'bytes':len(ipa),'sha256':sha,
        'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],
        'minimum_os':info.get('MinimumOSVersion'),'bundle_id':info.get('CFBundleIdentifier')}
(OUT/('IPA_VERIFICATION.json' if release else 'IPA_CANDIDATE.json')).write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(record,ensure_ascii=False,indent=2))
