import ci
for run in ci.ci.api('actions/runs?branch=codex%2Frelease-1.1.5&per_page=10')['workflow_runs']:
    print(run['id'],run['name'],run['head_sha'][:8],run['status'],run['conclusion'])
    if run['name']=='iOS' and run['status']!='completed':
        for job in ci.ci.api(f"actions/runs/{run['id']}/jobs")['jobs']:
            print('  ',job['id'],job['status'],job['conclusion'],job.get('started_at'))
