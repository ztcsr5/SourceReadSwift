from pathlib import Path
import hashlib, io, json, plistlib, sys, zipfile
import ci
api, signed_download, OUT, HEAD = ci.ci.api, ci.ci.signed_download, ci.OUT, ci.ci.HEAD

status = json.loads((OUT / 'ci-status.json').read_text(encoding='utf8'))
assert status['head'] == HEAD
runs = {r['name']: r for r in status['runs']}
package = runs['Unsigned IPA']
assert package['conclusion'] == 'success' and package['head_sha'] == HEAD
assert runs['iOS']['conclusion'] == 'success' and runs['iOS']['head_sha'] == HEAD
for artifact in api(f"actions/runs/{package['id']}/artifacts")['artifacts']:
    archive = signed_download(f"actions/artifacts/{artifact['id']}/zip")
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        names = [n for n in z.namelist() if n.lower().endswith('.ipa')]
        if not names: continue
        assert len(names) == 1
        ipa = z.read(names[0])
    break
else: raise SystemExit('No IPA found in successful package artifact')
digest = hashlib.sha256(ipa).hexdigest()
with zipfile.ZipFile(io.BytesIO(ipa)) as z:
    assert z.testzip() is None
    names = [n for n in z.namelist() if n.startswith('Payload/') and n.count('/') == 2 and n.endswith('.app/Info.plist')]
    assert len(names) == 1
    info = plistlib.loads(z.read(names[0]))
assert info['CFBundleShortVersionString'] == '1.1.1'
assert info['CFBundleVersion'] == '122'
assert info['MinimumOSVersion'] == '16.0'
assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
assert info['CFBundleDisplayName'] == '纸间'
assert info.get('DTSDKName', '').startswith('iphoneos26'), info.get('DTSDKName')
assert set(info.get('UIAppFonts', [])) == {'MaShanZheng-Regular.ttf', 'ZhiMangXing-Regular.ttf'}
with zipfile.ZipFile(io.BytesIO(ipa)) as z:
    for name in info['UIAppFonts']:
        assert any(n.endswith('/'+name) for n in z.namelist()), name
path = Path('C:/Users/Edc21/Desktop/SourceReadSwift-1.1.1-build122-unsigned.ipa')
if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() != digest:
    raise SystemExit('Existing desktop build122 IPA differs; refusing to overwrite.')
path.write_bytes(ipa)
folder = OUT / 'IPA' / HEAD
folder.mkdir(parents=True, exist_ok=True)
(folder / path.name).write_bytes(ipa)
record = {'commit': HEAD, 'package_run': package['id'], 'ios_run': runs['iOS']['id'], 'native_tests_success': True,
          'path': str(path), 'bytes': len(ipa), 'sha256': digest, 'version': info['CFBundleShortVersionString'],
          'build': info['CFBundleVersion'], 'minimum_os': info['MinimumOSVersion'], 'bundle_id': info.get('CFBundleIdentifier'),
          'display_name': info['CFBundleDisplayName'], 'platforms': info['CFBundleSupportedPlatforms'],
          'sdk': info.get('DTSDKName'), 'bundled_fonts': info['UIAppFonts']}
(OUT / 'IPA_VERIFICATION.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf8')
print(json.dumps(record, ensure_ascii=False, indent=2))
