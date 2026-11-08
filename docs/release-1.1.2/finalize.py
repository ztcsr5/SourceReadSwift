from pathlib import Path
import hashlib, io, json, re, zipfile
import ci
O, R, H = ci.OUT, ci.ROOT, ci.ci.HEAD
status=json.loads((O/'ci-status.json').read_text(encoding='utf8'))
assert status['head']==H
runs={r['name']:r for r in status['runs']}
assert all(runs[n]['conclusion']=='success' and runs[n]['head_sha']==H for n in ['iOS','Unsigned IPA'])
folder=O/'native-evidence'/H;folder.mkdir(parents=True,exist_ok=True)
for artifact in ci.ci.api(f"actions/runs/{runs['iOS']['id']}/artifacts")['artifacts']:
    if not artifact['name'].startswith(('ios-test-evidence-', 'ios26-tab-evidence-')):continue
    archive=ci.ci.signed_download(f"actions/artifacts/{artifact['id']}/zip")
    (folder/(artifact['name']+'.zip')).write_bytes(archive)
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        assert z.testzip() is None
        for name in z.namelist():
            if Path(name).name in ['xcodebuild-test.log','native-tab-test.log']:
                (folder/Path(name).name).write_bytes(z.read(name))
counts={}
for name in ['xcodebuild-test.log','native-tab-test.log']:
    log=(folder/name).read_text(encoding='utf8',errors='replace')
    assert '** TEST SUCCEEDED **' in log,name
    rows=[(int(n),int(f)) for n,f in re.findall(r'Executed (\d+) tests?,(?: with \d+ tests? skipped and)? with (\d+) failures?',log)]
    # XCTest changes the grammar when a suite contains skipped tests.
    rows += [(int(n),int(f)) for n,f in re.findall(r'Executed (\d+) tests?, with \d+ tests? skipped and (\d+) failures?',log)]
    assert rows and all(f==0 for _,f in rows),(name,rows)
    counts[name]=max(n for n,_ in rows)
native=(folder/'native-tab-test.log').read_text(encoding='utf8',errors='replace')
assert counts['native-tab-test.log']==3
assert counts['xcodebuild-test.log']>=1420
assert not re.search(r'with [1-9]\d* tests? skipped|Test Case .* skipped',native)
tests=re.findall(r'func (test\w+)\(', (R/'SourceReadSwiftTests/TabChromeRegressionTests.swift').read_text(encoding='utf8'))
for name in tests:
    assert re.search(r"Test Case .*"+re.escape(name)+r".*passed",native),name
ipa=json.loads((O/'IPA_VERIFICATION.json').read_text(encoding='utf8'))
assert ipa['commit']==H and ipa['version']=='1.1.2' and ipa['build']=='123'
assert hashlib.sha256(Path(ipa['path']).read_bytes()).hexdigest()==ipa['sha256']
assert json.loads((O/'VERIFICATION-local.json').read_text(encoding='utf8'))['head']==H
assert json.loads((O/'graphify-out/audit.json').read_text(encoding='utf8'))['head']==H
old=Path('C:/Users/Edc21/Desktop/SourceReadSwift-1.1.1-build122-unsigned.ipa')
assert hashlib.sha256(old.read_bytes()).hexdigest()=='5b80d9ca60053cb6176433c0e9d53b61bf4d22f96ad85c2fdc2373f5931c8338'
record={'head':H,'version':'1.1.2','build':123,'native_test_counts':counts,
    'iOS26_special_cases':tests,'iOS26_skipped':0,'failures':0,'ipa':ipa,
    'runs':{n:runs[n]['html_url'] for n in ['iOS','Unsigned IPA']},
    'scope':'Hosted UIKit/SwiftUI runtime checks on iOS26 plus full legacy regression; no physical iPhone visual acceptance.',
    'artifacts':{n:str(O/p) for n,p in [('MODIFIED_FILE','MODIFIED_FILE'),('DIFF_FILE','DIFF_FILE.patch'),('VERIFICATION','VERIFICATION.txt'),('ROLLBACK','ROLLBACK.py')]}}
(O/'delivery-verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
(O/'VERIFICATION.txt').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n\n'+
    '\n'.join(x for x in native.splitlines() if 'Test Case' in x or 'Executed ' in x or '** TEST' in x),encoding='utf8')
print(json.dumps(record,ensure_ascii=False,indent=2))
