"""Preserve exact-head reader controls CI, including independent red and fixed branches.

Usage: python -X utf8 scripts/reader_controls_ci.py --head <SHA> --branch <BRANCH> [--watch]
Read-only GitHub transport; no packaging, dispatch, credentials or signed URLs in output.
"""
import argparse
import json
from pathlib import Path
import re
import time
from urllib.parse import quote

from reader_motion_ci import github, save_job_log


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--head', default=github.HEAD)
    parser.add_argument('--branch', default='codex/reader-motion-117')
    parser.add_argument('--watch', action='store_true')
    options = parser.parse_args()
    if not re.fullmatch('[0-9a-f]{40}', options.head):
        raise ValueError('Expected a complete lowercase Git commit SHA')
    if not re.fullmatch('[A-Za-z0-9/_-]{1,120}', options.branch):
        raise ValueError('Unexpected branch name')
    destination = Path('F:/SourceReadSwift/reader-controls-117') / options.head
    destination.mkdir(parents=True, exist_ok=True)
    previous = None
    for _ in range(40 if options.watch else 1):
        runs = github.api('actions/runs?branch=' + quote(options.branch, safe='') + '&per_page=12')['workflow_runs']
        records = []
        for run in runs:
            if run['head_sha'] != options.head or run['name'] != 'iOS':
                continue
            jobs = github.api(f"actions/runs/{run['id']}/jobs")['jobs']
            records.append({key: run.get(key) for key in ['id', 'head_sha', 'event', 'status', 'conclusion', 'html_url']} | {'jobs': jobs})
            for job in jobs:
                save_job_log(job, destination)
        signature = [(run['id'], run['status'], run['conclusion'], [(job['id'], job['status'], job['conclusion'],
            [step['name'] for step in job['steps'] if step['status'] == 'in_progress']) for job in run['jobs']]) for run in records]
        if signature != previous:
            print(json.dumps(signature, ensure_ascii=False), flush=True)
            previous = signature
        (destination / 'ci-status.json').write_text(json.dumps({'head': options.head, 'branch': options.branch,
            'scope': 'reader controls code verification; no IPA delivery', 'runs': records}, ensure_ascii=False, indent=2), encoding='utf8')
        if not options.watch or (records and all(run['status'] == 'completed' for run in records)):
            break
        time.sleep(30)


if __name__ == '__main__':
    main()
