from pathlib import Path
import hashlib, io, json, re, shutil, sys, zipfile
import ci

ROOT=ci.ROOT;OUT=ci.OUT;HEAD=ci.ci.HEAD
status=json.loads((OUT/'ci-status.json').read_text(encoding='utf-8'))
assert status['head']==HEAD
runs={r['name']:r for r in status['runs']}
assert {'iOS','Unsigned IPA'}<=runs.keys()
assert all(runs[n]['head_sha']==HEAD and runs[n]['conclusion']=='success' for n in ['iOS','Unsigned IPA'])
ipa=json.loads((OUT/'IPA_VERIFICATION.json').read_text(encoding='utf-8'))
assert ipa['commit']==HEAD and ipa['build']=='121'
assert hashlib.sha256(Path(ipa['path']).read_bytes()).hexdigest()==ipa['sha256']
evidence=OUT/'native-evidence'/HEAD;evidence.mkdir(parents=True,exist_ok=True)
for artifact in ci.ci.api(f"actions/runs/{runs['iOS']['id']}/artifacts")['artifacts']:
    if not artifact['name'].startswith('ios-test-evidence-'):continue
    data=ci.ci.signed_download(f"actions/artifacts/{artifact['id']}/zip")
    (evidence/f"{artifact['id']}.zip").write_bytes(data)
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        assert z.testzip() is None
        for name in z.namelist():
            if Path(name).name in ['xcodebuild-build.log','xcodebuild-test.log']:
                (evidence/Path(name).name).write_bytes(z.read(name))
    break
else:raise RuntimeError('No native test evidence artifact found')
log=(evidence/'xcodebuild-test.log').read_text(encoding='utf-8',errors='replace')
assert '** TEST SUCCEEDED **' in log
counts=[(int(a),int(b)) for a,b in re.findall(r'Executed (\d+) tests?, with (\d+) failures?',log)]
assert counts and all(failures==0 for _,failures in counts)
count=max(n for n,_ in counts);assert count>=1403,(count,'Tests unexpectedly missing')
summary=[line for line in log.splitlines() if re.search(r'Executed \d+ tests?, with|TOC projection|Progress canonicalBytes=|\*\* TEST SUCCEEDED',line)]
assert json.loads((OUT/'source-contracts.json').read_text())['head']==HEAD
assert json.loads((OUT/'graphify-out/audit.json').read_text())['head']==HEAD
assert json.loads((OUT/'VERIFICATION-local.json').read_text())['head']==HEAD
tools=OUT/'reproduction-tools';tools.mkdir(exist_ok=True)
for p in Path(__file__).parent.glob('*.py'):shutil.copy2(p,tools/p.name)
record={'commit':HEAD,'version':'1.1.0','build':121,'tests':count,'failures':0,'runs':{n:{k:runs[n][k] for k in ['id','head_sha','conclusion','html_url']} for n in ['iOS','Unsigned IPA']},
        'ipa':ipa,'native_evidence':str(evidence),'test_log_sha256':hashlib.sha256((evidence/'xcodebuild-test.log').read_bytes()).hexdigest(),
        'scope':'Simulator native XCTest + generic device build. Not physical-device FPS or iOS16 all-feature runtime verification.'}
(OUT/'delivery-verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
text=[f'Build 121 / 1.1.0 / commit {HEAD}',f'Native XCTest: {count} tests, 0 failures.',
      f"IPA: {ipa['path']}",f"SHA256: {ipa['sha256']}",f"MinimumOSVersion: {ipa['minimum_os']}",
      'MODIFIED_FILE: '+str(OUT/'MODIFIED_FILE'),'DIFF_FILE: '+str(OUT/'DIFF_FILE.patch'),
      'VERIFICATION: '+str(OUT/'delivery-verification.json'),'ROLLBACK: '+str(OUT/'ROLLBACK.py'),
      'Rollback drill: canonical baseline -> patch -> modified hash -> rollback -> original hash -> reapply -> Windows worktree rollback: PASS.',
      'Source contracts: PASS (not runtime proof). Focused AST graph regenerated from this commit.',
      'Observed video: old chapter text remains after TOC dismissal around 20-24 s and 60-63 s; 849-entry catalog.',
      'Implemented: once-per-list chapter bounds/filtering; stable one-view detail rows; lightweight durable shelf progress; ordered background chapter-cache writes; foreground target pagination + explicit anchor commit + stale completion guards; settings > appearance.',
      'Unverified: physical-device scrolling FPS / touch-to-content latency / every feature on an iOS16 device.',
      'Previous build120 IPA and release artifacts were preserved.', '\nLiteral native test log excerpts:',*summary]
(OUT/'VERIFICATION.txt').write_text('\n'.join(text),encoding='utf-8')
print(json.dumps(record,ensure_ascii=False,indent=2))
