from datetime import datetime, timezone
import json
import ci

d = json.loads((ci.OUT/'ci-status.json').read_text(encoding='utf8'))
now = datetime.now(timezone.utc)
for run in d['runs']:
    for job in run['jobs']:
        print(run['name'], job['status'], 'started', job['started_at'])
        for step in job['steps']:
            if step.get('started_at') and step.get('status') == 'in_progress':
                t = datetime.fromisoformat(step['started_at'].replace('Z', '+00:00'))
                print(step['name'], round((now-t).total_seconds()), 'seconds')
