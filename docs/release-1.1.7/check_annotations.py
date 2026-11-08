import ci, json
status=json.loads((ci.OUT/'ci-status.json').read_text(encoding='utf8'))
for run in status['runs']:
    for job in run['jobs']:
        if not any(s.get('conclusion')=='failure' for s in job.get('steps',[])): continue
        url=job.get('check_run_url','')
        if not url: continue
        annotations=ci.ci.api('check-runs/'+url.rsplit('/',1)[-1]+'/annotations?per_page=100')
        for a in annotations:
            print(a['path'],a['start_line'],a.get('title'),a['message'])
