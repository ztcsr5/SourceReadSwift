from pathlib import Path
import hashlib, io, json, re, shutil, zipfile
import ci
O=ci.OUT; R=ci.ROOT; H=ci.ci.HEAD
status=json.loads((O/'ci-status.json').read_text(encoding='utf8'))
assert status['head']==H
runs={r['name']:r for r in status['runs']}
assert all(runs[n]['head_sha']==H and runs[n]['conclusion']=='success' for n in ['iOS','Unsigned IPA'])
evidence=O/'native-evidence'/H;evidence.mkdir(parents=True,exist_ok=True)
for artifact in ci.ci.api(f"actions/runs/{runs['iOS']['id']}/artifacts")['artifacts']:
 if not artifact['name'].startswith('ios-test-evidence-'):continue
 data=ci.ci.signed_download(f"actions/artifacts/{artifact['id']}/zip")
 (evidence/'native-evidence.zip').write_bytes(data)
 with zipfile.ZipFile(io.BytesIO(data)) as z:
  assert z.testzip() is None
  for name in z.namelist():
   if Path(name).name in ['xcodebuild-build.log','xcodebuild-test.log']:
    (evidence/Path(name).name).write_bytes(z.read(name))
 break
else:raise RuntimeError('Missing native XCTest artifact')
log=(evidence/'xcodebuild-test.log').read_text(encoding='utf8',errors='replace')
assert '** TEST SUCCEEDED **' in log
counts=[(int(a),int(b)) for a,b in re.findall(r'Executed (\d+) tests?, with (\d+) failures?',log)]
assert counts and all(f==0 for _,f in counts)
count=max(n for n,_ in counts)
new_tests=re.findall(r'func (test\w+)\(', (R/'SourceReadSwiftTests/Release111RegressionTests.swift').read_text(encoding='utf8'))
assert count >= 1403+len(new_tests),(count,len(new_tests))
for name in new_tests: assert name in log,name
ipa=json.loads((O/'IPA_VERIFICATION.json').read_text(encoding='utf8'))
assert ipa['commit']==H and ipa['version']=='1.1.1' and ipa['build']=='122'
assert hashlib.sha256(Path(ipa['path']).read_bytes()).hexdigest()==ipa['sha256']
for p in ['source-contracts.json','graphify-out/audit.json','VERIFICATION-local.json']:
 assert json.loads((O/p).read_text(encoding='utf8'))['head']==H,p
old=Path('C:/Users/Edc21/Desktop/SourceReadSwift-1.1.0-build121-unsigned.ipa')
assert hashlib.sha256(old.read_bytes()).hexdigest()=='515931c3983d77d24b35fb8800ac0cc16f4a8225b127bee112f1db00086cf9c5'
record={'commit':H,'version':'1.1.1','build':122,'native_tests':count,'failures':0,'new_regressions':new_tests,
 'runs':{n:{k:runs[n][k] for k in ['id','head_sha','conclusion','html_url']} for n in ['iOS','Unsigned IPA']},
 'ipa':ipa,'test_log':str(evidence/'xcodebuild-test.log'),
 'test_log_sha256':hashlib.sha256((evidence/'xcodebuild-test.log').read_bytes()).hexdigest(),
 'scope':'Simulator native XCTest and Xcode26 generic-device build. Not physical iOS16/26 runtime validation or measured device FPS.',
 'unverified':['Aidoku WASM execution/subscription integration not implemented', 'Full 1466-source live network retest not run',
 'Azure online synthesis requires user Speech resource key; request construction tested only',
 'Physical-device chapter jump latency, scroll FPS, glass animation and all-feature iOS16 runtime not measured'],
 'artifacts':{k:str(O/v) for k,v in [('MODIFIED_FILE','MODIFIED_FILE'),('DIFF_FILE','DIFF_FILE.patch'),('VERIFICATION','VERIFICATION.txt'),('ROLLBACK','ROLLBACK.py')]}}
(O/'delivery-verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
lines=[f'1.1.1 / Build122 / {H}',f'Observed: native XCTest {count} tests, 0 failures; Xcode26 device build successful.',
 'Observed: IPA plist MinimumOSVersion 16.0; this is deployment metadata, not all-feature iOS16 device testing.',
 f"IPA: {ipa['path']}",f"SHA256: {ipa['sha256']}",
 'Executed byte drill: baseline -> patch -> modified hashes -> rollback -> baseline hashes -> reapply -> Windows worktree rollback.',
 'Original build121 desktop IPA hash unchanged.',
 *[f'{k}: {v}' for k,v in record['artifacts'].items()],
 'Unverified / unfinished:', *record['unverified'], 'Literal native summaries:',
 *[x for x in log.splitlines() if re.search(r'Executed \d+ tests?, with|\*\* TEST SUCCEEDED',x)][-20:]]
(O/'VERIFICATION.txt').write_text('\n'.join(lines),encoding='utf8')
tools=O/'reproduction-tools';tools.mkdir(exist_ok=True)
for p in Path(__file__).parent.glob('*.py'):shutil.copy2(p,tools/p.name)
print(json.dumps(record,ensure_ascii=False,indent=2))
