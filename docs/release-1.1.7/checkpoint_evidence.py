"""Write an honest checkpoint receipt; no release/IPA or physical FPS claim."""
from pathlib import Path
import subprocess, json, re, hashlib
root=Path(__file__).resolve().parents[2]
out=Path('F:/SourceReadSwift/release-1.1.7')
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
status=json.loads((out/'ci-status.json').read_text(encoding='utf8'))
assert status['head']==head
rows=[]
for run in status['runs']:
    for job in run['jobs']:
        log=out/f"job-{job['id']}.log"
        text=log.read_text(encoding='utf8',errors='replace') if log.exists() else ''
        totals=re.findall(r'Executed (\d+) tests, with (?:(\d+) tests skipped and )?(\d+) failures',text)
        suites={}
        for name in ['AIChatTests','WebsiteSourceInferenceTests','Release117PurificationTests','Release117ChromeTests','Release117DetailTests','LANWorkbenchTests','ReadingNotesNavigationTests','TabChromeRegressionTests']:
            hits=re.findall(r"Test Suite '"+name+r"' (passed|failed)",text)
            suites[name]=hits[-1] if hits else 'NOT RUN / log not available'
        rows.append({'run':run['id'],'job':job['id'],'status':job['status'],'conclusion':job.get('conclusion'),
                     'counts':totals[-1] if totals else None,'suites':suites,
                     'log':str(log) if log.exists() else None,'sha256':hashlib.sha256(log.read_bytes()).hexdigest() if log.exists() else None})
receipt={'head':head,'state':'checkpoint, not final release','native':rows,
         'ai_api':'Injected transport tests only; no real user key, paid request or provider-end-to-end claim.',
         'comics':'559b5a3 live probe31 source configs,10 first-image decodes,21 failures. Not complete comics or997 live checks.',
         'ui_review':'559b5a3 local detail320/390 inspected on iOS18/iOS26. Later remote detail/chrome/AI pixel review pending.',
         'lan':'Item14 implemented; see native LANWorkbenchTests status above. Edge27 UI +10 file/paired CLI checks against loopback fake APIs; no physical phone LAN acceptance or blanket security claim.',
         'notes_navigation':'Items15–16 implemented:48 launch-scoped original notes and shared寻书/books.vertical navigation. Native result follows ReadingNotesNavigationTests and TabChromeRegressionTests above.',
         'remaining':'Items17–20, full comic compatibility, physical iOS16/17/26 acceptance and FPS measurements. Items14–16 native/packaging gate follows statuses above; visual acceptance remains partial.',
         'rollback':'VERIFICATION-local.json proves byte rollback/reapply only, not native behavior after rollback.'}
(out/'CHECKPOINT.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf8')
lines=['SourceReadSwift1.1.7 CHECKPOINT (NOT RELEASED)',f'HEAD {head}']
for row in rows: lines.append(json.dumps(row,ensure_ascii=False))
if (out/'VERIFICATION-local.json').exists():
    local=json.loads((out/'VERIFICATION-local.json').read_text(encoding='utf8'))
    assert local['head']==head
    lines+=['Byte reconstruction/rollback proof: '+str(out/'VERIFICATION-local.json'), 'Scope: '+local['scope']]
lines += [receipt['ai_api'],receipt['comics'],receipt['ui_review'],receipt['lan'],receipt['notes_navigation'],'Remaining: '+receipt['remaining']]
(out/'VERIFICATION.txt').write_text('\n'.join(lines)+'\n',encoding='utf8')
print(json.dumps({'head':head,'jobs':[{'job':r['job'],'conclusion':r['conclusion'],'counts':r['counts']} for r in rows],'receipt':str(out/'CHECKPOINT.json')},ensure_ascii=False))
