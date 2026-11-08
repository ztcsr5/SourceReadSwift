import json,sys
from ci_status import api
run=int(sys.argv[1])
for job in api(f'actions/runs/{run}/jobs')['jobs']:
    print('JOB',job['id'],job['name'],job['status'])
    for step in job['steps']:
        if step['name'] in ('Build','Test','Build unsigned device app'):
            print(json.dumps(step,ensure_ascii=False))
